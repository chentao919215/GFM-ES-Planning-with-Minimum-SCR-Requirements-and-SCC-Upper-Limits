function tests = test_scc_scr_joint_sensitivity
% No optimize/Gurobi calls. Synthetic stage results exercise orchestration only.
tests = functiontests(localfunctions);
end

function setupOnce(T)
Root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
T.TestData.Root = Root;
T.TestData.OldPath = path;
addpath(genpath(fullfile(Root,'code','functions')));
clear run_multiple_snapshot_joint_sensitivity_scan build_multiple_snapshot_diagnostics
Output = tempname(fullfile(Root,'results'));
mkdir(Output);
Mock = fullfile(Output,'mock_stage'); mkdir(Mock);
copyfile(fullfile(Root,'code','tests','fixtures','joint_scan_stage_stub.txt'), ...
    fullfile(Mock,'solve_one_stage.m'));
addpath(Mock,'-begin');
clear solve_one_stage
assert(strcmp(which('solve_one_stage'),fullfile(Mock,'solve_one_stage.m')));
setappdata(0,'joint_scan_test_state',struct('Mode','target','Calls',0));
T.TestData.Output = Output;
T.TestData.Seed = fullfile(Output,'seed');
run_multiple_snapshot_joint_sensitivity_scan(Root,5.6,2.8, ...
    struct('Run_Directory',T.TestData.Seed));
fprintf('Synthetic test artifacts: %s\n',Output);
end

function teardownOnce(T)
path(T.TestData.OldPath);
clear solve_one_stage
if isappdata(0,'joint_scan_test_state'), rmappdata(0,'joint_scan_test_state'); end
end

function testDryGridAndSourceScenarios(T)
Dir = new_run(T);
set_mode('target');
[Rows,~,J] = scan(T,Dir,false,[5.9 5.5 5.6 5.8],[3 2.3 2.8 2.6 2.9 2.7]);
verifyEqual(T,calls(),0);
verifyEqual(T,height(Rows),24);
verifyEqual(T,size(J.Cost_Matrix),[6 4]);
verifyTrue(T,all(Rows.Status=="pending"));
verifyEqual(T,nnz(Rows.I_limit_kA==5.6 & Rows.CSCR==2.8),1);
for k = 1:height(Rows)
    P = jsondecode(fileread(Rows.Parameter_File(k)));
    verifyEqual(T,P.Security.I_limit_kA,Rows.I_limit_kA(k));
    verifyEqual(T,P.Security.SCR_min,Rows.CSCR(k));
    verifyEqual(T,Rows.SCR_Row(k),mod(k-1,6)+1);
    verifyEqual(T,Rows.SCC_Column(k),ceil(k/6));
end
P = jsondecode(fileread(J.Manifest.Baseline_File));
Source = load(J.Manifest.Sources(endsWith(string({J.Manifest.Sources.Path}), ...
    'rts_gmlc_typical_days_and_wind_scenarios_20260822_162606.mat')).Path,'Result');
d = find([Source.Result.Typical_Day_Sets.D]==4,1);
S = Source.Result.Wind_Scenario_Sets(d,:);
S = S(find([S.K]==4,1));
verifyEqual(T,P.Multiple_Snapshot.Wind_Scenarios.Probabilities,S.Probability);
Available = P.Multiple_Snapshot.Wind_Scenarios.P_GFL_Available_Scenarios;
verifyEqual(T,reshape(Available(11,:,:,:),4,4,24), ...
    60*S.Wind_Scenario_Normalized,'AbsTol',1e-12);
end

function testModuleMappingAndResume(T)
Dir = new_run(T); set_mode('target');
[Rows,~,J] = scan(T,Dir,true,[5.8 5.6],[2.8 2.9]);
verifyTrue(T,all(Rows.Status=="target_met"));
verifyEqual(T,Rows.GFM_Modules_Per_Bus,repmat("[1 2 0]",4,1));
verifyEqual(T,Rows.GFM_Configuration,repmat("[1 0 1 1 0 0]",4,1));
verifyEqual(T,Rows.GFM_Module_Count,3*ones(4,1));
verifyEqual(T,Rows.GFM_Power_MW,90*ones(4,1));
verifyEqual(T,Rows.GFM_Energy_MWh,180*ones(4,1));
verifyEqual(T,J.Cost_Matrix,reshape(Rows.Total_Annual_Cost,2,2));
verifyEqual(T,calls(),4);
scan(T,Dir,true,[5.6 5.8],[2.9 2.8]);
verifyEqual(T,calls(),4); % reordering axes must remap, not recompute
% A changed result must be rejected, despite a target_met checkpoint.
Data = load(Rows.Final_Result_File(1),'Result');
Result = Data.Result; Result.Cost.Total = Result.Cost.Total+1;
save(Rows.Final_Result_File(1),'Result','-v7.3');
scan(T,Dir,true,[5.8 5.6],[2.8 2.9]);
verifyEqual(T,calls(),5);
end

function testStatuses(T)
Modes = ["infeasible","stop","ambiguous","error","two_stage", ...
    "above_gap","stage2_error","stage2_stop","bad_cost"];
Expected = ["proven_infeasible","stopped_no_incumbent","no_incumbent_unknown", ...
    "solver_or_model_error","target_met","feasible_target_not_met", ...
    "solver_or_model_error","feasible_target_not_met","solver_or_model_error"];
for n = 1:numel(Modes)
    Dir = new_run(T); set_mode(Modes(n));
    Row = scan(T,Dir,true,5.6,2.8);
    verifyEqual(T,Row.Status,Expected(n));
    verifyEqual(T,Row.Is_Feasible,any(n==[5 6 7 8]));
    if n==1
        scan(T,Dir,true,5.6,2.8);
        verifyEqual(T,calls(),1); % only proven infeasibility is reusable
    elseif n==2
        scan(T,Dir,true,5.6,2.8);
        verifyEqual(T,calls(),2); % a time limit cannot prove infeasibility
    elseif n==7
        Before = calls(); set_mode('target',false);
        Row = scan(T,Dir,true,5.6,2.8);
        verifyEqual(T,calls(),Before+1); % reuse stage 1, retry stage 2
        verifyEqual(T,Row.Status,"target_met");
    elseif n==6
        Before = calls();
        run_multiple_snapshot_joint_sensitivity_scan(T.TestData.Root,5.6,2.8, ...
            struct('Run_Directory',Dir,'Execute',true,'Retry_Unfinished',false));
        verifyEqual(T,calls(),Before);
        scan(T,Dir,true,5.6,2.8);
        verifyEqual(T,calls(),Before+1); % repeat stage 2, retain validated stage 1
    end
end
end

function testInputIntegrityAndAxes(T)
Dir = new_run(T); set_mode('target');
Row = scan(T,Dir,true,5.6,2.8);
P = jsondecode(fileread(Row.Parameter_File)); P.Security.SCR_min = 3;
fid = fopen(Row.Parameter_File,'w'); fprintf(fid,'%s',jsonencode(P)); fclose(fid);
verifyError(T,@() scan(T,Dir,true,5.6,2.8),'JointScan:InputChanged');
verifyError(T,@() scan(T,new_run(T),false,5.5,2.8),'JointScan:MissingBaseline');
verifyError(T,@() scan(T,new_run(T),false,[5.6 5.6],2.8),'JointScan:DuplicateGrid');
end

function testGapAwareMonotonicity(T)
for Mode = ["gap_reversal","disjoint_bounds"]
    set_mode(Mode);
    [~,~,J] = scan(T,new_run(T),true,[5.6 5.8],2.8);
    if Mode=="gap_reversal", Expected = "reversal_within_MIP_uncertainty";
    else, Expected = "review_disjoint_bounds"; end
    verifyEqual(T,J.Monotonicity.Assessment,Expected);
end
end

function testRawSolverDiagnostics(T)
for Raw = ["INFEASIBLE","TIME_LIMIT","INF_OR_UNBD"]
    Sol = struct('problem',3,'info','synthetic', ...
        'solveroutput',struct('result',struct('status',char(Raw),'solcount',0)));
    D = build_multiple_snapshot_diagnostics(Sol);
    verifyEqual(T,D.solver_status,char(Raw));
    verifyFalse(T,D.has_incumbent);
    verifyTrue(T,isnan(D.mip_gap));
end
end

function Dir = new_run(T)
Dir = tempname(T.TestData.Output); mkdir(Dir);
copyfile(fullfile(T.TestData.Seed,'manifest.mat'),fullfile(Dir,'manifest.mat'));
end

function varargout = scan(T,Dir,Execute,I,SCR)
[varargout{1:nargout}] = run_multiple_snapshot_joint_sensitivity_scan( ...
    T.TestData.Root,I,SCR,struct('Run_Directory',Dir,'Execute',Execute));
end

function set_mode(Mode,Reset)
if nargin<2, Reset = true; end
State = getappdata(0,'joint_scan_test_state'); State.Mode = char(Mode);
if Reset, State.Calls = 0; end
setappdata(0,'joint_scan_test_state',State);
end

function N = calls()
State = getappdata(0,'joint_scan_test_state'); N = State.Calls;
end
