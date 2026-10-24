function [Summary_Table, Summary_File, Joint] = ...
    run_multiple_snapshot_joint_sensitivity_scan(Project_Root, I_Values, SCR_Values, Options)
% Case 5 grid orchestration only; reuses the existing model and stage solvers.
% Execute=false prepares/validates inputs and exports the grid, without optimize.
% Rows=SCR_Values, columns=I_Values (input order, including unsorted grids).
if nargin < 4, Options = struct(); end
if ~isfield(Options,'Execute'), Options.Execute = false; end
if ~isfield(Options,'Retry_Unfinished'), Options.Retry_Unfinished = true; end
if ~isfield(Options,'Run_Directory')
    Options.Run_Directory = fullfile(Project_Root,'results', ...
        'multiple_snapshot_scc_scr_joint_sensitivity');
end
validateattributes(Options.Execute,{'logical'},{'scalar'});
validateattributes(Options.Retry_Unfinished,{'logical'},{'scalar'});
validateattributes(I_Values,{'numeric'},{'vector','nonempty','real','finite','positive'});
validateattributes(SCR_Values,{'numeric'},{'vector','nonempty','real','finite','positive'});
I_Values = I_Values(:).';
SCR_Values = SCR_Values(:);
assert(numel(unique(I_Values)) == numel(I_Values) && ...
    numel(unique(SCR_Values)) == numel(SCR_Values), 'JointScan:DuplicateGrid', ...
    'Grid axes must not contain duplicates.');
assert(any(abs(I_Values-5.6)<1e-12) && any(abs(SCR_Values-2.8)<1e-12), ...
    'JointScan:MissingBaseline','The grid must contain (5.6 kA, 2.8).');
Run_Directory = char(java.io.File(Options.Run_Directory).getCanonicalPath());
ensure_directory(Run_Directory);
[Manifest, Base, mpc, Base_CONF] = prepare_baseline(Project_Root,Run_Directory);
Case5_Audit = audit_case5_reference(Project_Root,Base_CONF,Run_Directory);
Summary_File = fullfile(Run_Directory,'joint_summary.mat');
Rows = repmat(empty_row(),numel(I_Values)*numel(SCR_Values),1);
for j = 1:numel(I_Values)
    for i = 1:numel(SCR_Values)
        k = sub2ind([numel(SCR_Values),numel(I_Values)],i,j);
        Rows(k).I_limit_kA = I_Values(j); Rows(k).CSCR = SCR_Values(i);
        Rows(k).SCR_Row = i; Rows(k).SCC_Column = j;
    end
end

for j = 1:numel(I_Values)
    for i = 1:numel(SCR_Values)
        k = sub2ind([numel(SCR_Values),numel(I_Values)],i,j);
        Params = Base;
        Params.Security.I_limit_kA = I_Values(j);
        Params.Security.SCR_min = SCR_Values(i);
        Label = ['SCC_',number_token(I_Values(j)),'_kA_CSCR_',number_token(SCR_Values(i))];
        Point_Dir = fullfile(Run_Directory,Label);
        ensure_directory(Point_Dir);
        Parameter_File = fullfile(Point_Dir,[Label,'_parameters.json']);
        if isfile(Parameter_File)
            assert(isequaln(jsondecode(fileread(Parameter_File)),Params), ...
                'JointScan:InputChanged','Point input differs: %s',Parameter_File);
        else
            write_json(Parameter_File,Params);
        end
        % Load through the original kA -> p.u. conversion for EVERY point.
        [Point_mpc,CONF] = load_multiple_snapshot_case(Project_Root,Parameter_File);
        assert(isequaln(Point_mpc,mpc),'JointScan:NetworkChanged','Network changed.');
        validate_point_conf(CONF,Base_CONF,I_Values(j),SCR_Values(i));
        Row = Rows(k);
        Row.I_limit_kA = I_Values(j);
        Row.CSCR = SCR_Values(i);
        Row.SCR_Row = i;
        Row.SCC_Column = j;
        Row.Target_MIP_Gap = CONF.Solver.Two_Stage.Stage_2.MIP_Gap;
        Row.Parameter_File = string(Parameter_File);
        Row.Point_File = string(fullfile(Point_Dir,[Label,'_point.mat']));
        [Cached,Reason] = read_checkpoint(Row,Params,CONF,Manifest);
        Row.Resume_Note = Reason;
        if ~isempty(Cached)
            Row = Cached.Row;
            Row.SCR_Row = i;
            Row.SCC_Column = j;
            Row.Resume_Note = "validated checkpoint";
        end
        Skip = ~isempty(Cached) && Row.Completed && (Row.Status == "target_met" || ...
            Row.Status == "proven_infeasible" || ...
            (~Options.Retry_Unfinished && Row.Status == "feasible_target_not_met"));
        if Options.Execute && ~Skip
            Row = execute_point(Row,Params,CONF,mpc,Manifest,Point_Dir,Label,Cached);
        end
        Rows(k) = Row;
        % Every finished point (and every dry-run point) updates all exports.
        [Summary_Table,Joint] = export_summary(Rows,I_Values,SCR_Values, ...
            Manifest,Summary_File,Options.Execute,Case5_Audit);
    end
end
fprintf('Joint scan: %d combinations, Execute=%d\nSummary: %s\n', ...
    numel(Rows),Options.Execute,Summary_File);
end

function [Manifest,Base,mpc,CONF] = prepare_baseline(Root,Run_Dir)
Manifest_File = fullfile(Run_Dir,'manifest.mat');
Sources = source_signatures(Root);
if isfile(Manifest_File)
    Data = load(Manifest_File,'Manifest');
    Manifest = Data.Manifest;
    assert(Manifest.Schema_Version == 1 && isequaln(Manifest.Sources,Sources), ...
        'JointScan:ChangedSources', ...
        'Sources differ from this run. Use a new Run_Directory.');
    assert(strcmp(file_hash(Manifest.Baseline_File),Manifest.Baseline_SHA256), ...
        'JointScan:ChangedBaseline','Frozen Case 5 input changed.');
else
    Baseline_File = fullfile(Run_Dir,'case5_baseline_parameters.json');
    generate_case5(Root,Baseline_File);
    Manifest = struct('Schema_Version',1,'Sources',Sources, ...
        'Baseline_File',Baseline_File,'Baseline_SHA256',file_hash(Baseline_File), ...
        'Created',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
    atomic_save(Manifest_File,struct('Manifest',Manifest));
end
Base = jsondecode(fileread(Manifest.Baseline_File));
assert(Base.Security.Consider_Wind_Uncertainty == 1 && ...
    Base.Security.Enable_SCC && Base.Security.Enable_SCR && ...
    abs(Base.Security.I_limit_kA-5.6)<1e-12 && abs(Base.Security.SCR_min-2.8)<1e-12 && ...
    Base.Multiple_Snapshot.Time.Typical_Day_Count == 4 && ...
    Base.Multiple_Snapshot.Wind_Scenarios.Count == 4 && ...
    Base.Solver.Two_Stage.Enabled && ...
    abs(Base.Solver.Two_Stage.Stage_2.MIP_Gap-Base.Solver.MIP_Gap)<1e-12, ...
    'JointScan:NotCase5','Expected stochastic Case 5, D=4, K=4, two stages.');
[mpc,CONF] = load_multiple_snapshot_case(Root,Manifest.Baseline_File);
assert(strcmp(CONF.ModelVersion,'2026-10-23'), ...
    'JointScan:ModelVersion','This scan targets the current Case 5 model.');
validate_point_conf(CONF,CONF,5.6,2.8);
end

function generate_case5(Root,File)
% Isolated function workspace: optional generator settings cannot leak to callers.
Parameter_Generation_Options = struct('Output_File',File,'Case_5',true); %#ok<NASGU>
run(fullfile(Root,'data','params','generate_multiple_snapshot_default_params.m'));
end

function Audit = audit_case5_reference(Root,CONF,Run_Dir)
% Read-only comparison with the original Case 5, when present in this project.
Stage = (1:2).'; Available = false(2,1); Matched = false(2,1);
Reference_File = strings(2,1); Different_Fields = strings(2,1);
for n = 1:2
    Reference_File(n) = string(fullfile(Root,'results_useful','from_laptop', ...
        'IV-B',sprintf('Case_5_Stage_%d.mat',n)));
    Available(n) = isfile(Reference_File(n));
    if ~Available(n), Different_Fields(n) = "reference_unavailable"; continue; end
    Data = load(Reference_File(n),'Result');
    Actual = normalize_multiple_snapshot_conf(Data.Result.CONF);
    Expected = normalize_multiple_snapshot_conf(apply_multiple_snapshot_solver_stage( ...
        CONF,CONF.Solver.Two_Stage.(sprintf('Stage_%d',n))));
    if isfield(Actual,'MIPStart'), Actual = rmfield(Actual,'MIPStart'); end
    Actual.solver.options.gurobi.LogFile = '';
    Expected.solver.options.gurobi.LogFile = '';
    Fields = union(fieldnames(Actual),fieldnames(Expected));
    Different = strings(0,1);
    for k = 1:numel(Fields)
        f = Fields{k};
        if ~isfield(Actual,f) || ~isfield(Expected,f) || ~isequaln(Actual.(f),Expected.(f))
            Different(end+1,1) = string(f); %#ok<AGROW>
        end
    end
    Matched(n) = isempty(Different);
    if ~isempty(Different), Different_Fields(n) = join(Different,', '); end
end
Audit = table(Stage,Available,Matched,Reference_File,Different_Fields);
atomic_save(fullfile(Run_Dir,'case5_reference_validation.mat'),struct('Audit',Audit));
writetable(Audit,fullfile(Run_Dir,'case5_reference_validation.csv'));
assert(all(Matched(Available)),'JointScan:Case5Mismatch', ...
    'Baseline differs from the original Case 5. Inspect case5_reference_validation.csv.');
end

function validate_point_conf(CONF,Base,I,SCR)
Runtime = normalize_multiple_snapshot_conf(CONF);
assert(Runtime.Enable_SCC && Runtime.Enable_SCR && ...
    Runtime.Consider_Wind_Uncertainty == 1 && Runtime.TypicalDayCount == 4 && ...
    Runtime.WindScenarioCount == 4 && ...
    all(abs(Runtime.I_limit_kA_Node-I)<1e-12) && ...
    all(abs(Runtime.I_limit*Runtime.Base_kA-I)<1e-12) && ...
    abs(Runtime.SCR_min-SCR)<1e-12, ...
    'JointScan:ThresholdMismatch','Loaded/runtime security settings mismatch.');
Expected_Base_kA = Runtime.Base_MVA/(sqrt(3)*Runtime.Base_kV);
assert(abs(Runtime.Base_kA-Expected_Base_kA)<1e-12, ...
    'JointScan:CurrentBase','Inconsistent system current base (kA).');
% Equality of ALL other inputs, including UC, storage, probabilities and solver.
A = CONF; B = Base;
A.Security = rmfield(A.Security,{'I_limit_kA','I_limit_pu','SCR_min'});
B.Security = rmfield(B.Security,{'I_limit_kA','I_limit_pu','SCR_min'});
assert(isequaln(A,B),'JointScan:NonScanInputChanged','Non-scan inputs changed.');
end

function Row = execute_point(Row,Params,CONF,mpc,Manifest,Point_Dir,Label,Cached)
Clock = tic;
Attempt = tempname(Point_Dir);
ensure_directory(Attempt);
Row.Attempt_Directory = string(Attempt);
Row.Error_Identifier = "";
Row.Error_Message = "";
Row.Status = "running";
Row.Completed = false;
Stage = 1;
Stage1 = [];
try
    % Reuse valid stage 1 when retrying an interrupted/unfinished stage 2.
    if ~isempty(Cached) && ~isempty(Cached.Stage1) && ...
            Cached.Stage1.Diagnostics.has_incumbent && ...
            classify(Cached.Stage1.Diagnostics,Row.Target_MIP_Gap)~="solver_or_model_error"
        Stage1 = Cached.Stage1;
        Row = reset_solution(Row);
        Row.Stage_1_Result_File = Cached.Row.Stage_1_Result_File;
        Row.Stage_1_Solve_Time_s = Stage1.solve_time;
    end
    if isempty(Stage1)
        Row = reset_solution(Row);
        [Stage1,File] = run_stage(mpc,CONF,1,Attempt,Label,[],"");
        Row.Stage_1_Result_File = string(File);
        Row.Stage_1_Solve_Time_s = Stage1.solve_time;
    end
    validate_stage_result(Stage1,CONF,1);
    Row.Stage_1_Status = classify(Stage1.Diagnostics,Row.Target_MIP_Gap);
    if Stage1.Diagnostics.has_incumbent
        Row = summarize(Row,Stage1,Row.Stage_1_Result_File,"stage_1",CONF);
        Row.Status = "running";
        save_checkpoint(Row,Params,Manifest);
        if Row.Stage_1_Status == "solver_or_model_error"
            Row.Status = "solver_or_model_error";
        elseif Row.Final_MIP_Gap <= Row.Target_MIP_Gap
            Row.Status = "target_met";
        else
            Stage = 2;
            [Stage2,File] = run_stage(mpc,CONF,2,Attempt,Label,Stage1,Row.Stage_1_Result_File);
            Row.Stage_2_Result_File = string(File);
            Row.Stage_2_Solve_Time_s = Stage2.solve_time;
            validate_stage_result(Stage2,CONF,2);
            Row.Stage_2_Status = classify(Stage2.Diagnostics,Row.Target_MIP_Gap);
            if Stage2.Diagnostics.has_incumbent
                Row = summarize(Row,Stage2,File,"stage_2",CONF);
                Row.Status = classify(Stage2.Diagnostics,Row.Target_MIP_Gap);
            elseif Row.Stage_2_Status == "proven_infeasible"
                error('JointScan:ContradictoryStages', ...
                    'Stage 2 reports infeasible despite the stage-1 incumbent.');
            elseif Row.Stage_2_Status == "solver_or_model_error"
                Row.Status = "solver_or_model_error";
            else
                % Retain the real stage-1 incumbent and its own gap.
                Row.Status = "feasible_target_not_met";
            end
        end
    else
        Row.Status = Row.Stage_1_Status;
        Row.Solver_Problem = Stage1.Diagnostics.problem;
        Row.Solver_Status = string(Stage1.Diagnostics.solver_status);
        Row.Solver_Info = string(Stage1.Diagnostics.info);
        Row.Final_Result_File = Row.Stage_1_Result_File;
        Row.Final_Stage = "stage_1";
    end
catch ME
    Row.Status = "solver_or_model_error";
    Row.Error_Identifier = string(ME.identifier);
    Row.Error_Message = string(ME.message);
    if Stage == 1, Row.Stage_1_Status = "solver_or_model_error";
    else, Row.Stage_2_Status = "solver_or_model_error"; end
    fprintf(2,'%s: %s\n',Label,ME.message);
end
Row.Runtime_s = toc(Clock);
Times = [Row.Stage_1_Solve_Time_s,Row.Stage_2_Solve_Time_s];
Row.Total_Solve_Time_s = sum(Times,'omitnan');
Row.Completed = true;
save_checkpoint(Row,Params,Manifest);
% Attempt record is immutable; the point record is the atomic resume pointer.
atomic_save(fullfile(Attempt,[Label,'_record.mat']), ...
    struct('Record',struct('Row',Row,'Params',Params,'Manifest',Manifest)));
end

function [Result,File] = run_stage(mpc,CONF,Stage,Attempt,Label,Stage1,Stage1_File)
if Stage == 1, Config = CONF.Solver.Two_Stage.Stage_1;
else, Config = CONF.Solver.Two_Stage.Stage_2; end
Stage_CONF = apply_multiple_snapshot_solver_stage(CONF,Config);
Directory = fullfile(Attempt,sprintf('stage_%d',Stage));
ensure_directory(Directory);
% Only the log destination changes; all numerical solver settings stay intact.
Stage_CONF.solver.options.gurobi.LogFile = fullfile(Directory,[Label,'.log']);
if Stage == 2
    Stage_CONF.Solver.MIP_Start = ...
        build_multiple_snapshot_mip_start_from_result(Stage1,Stage_CONF);
    Stage_CONF.Solver.MIP_Start.Source_File = char(Stage1_File);
end
[Result,Original_File] = solve_one_stage(mpc,Stage_CONF, ...
    struct('results_dir',Directory),true);
File = fullfile(Directory,sprintf('%s_stage_%d.mat',Label,Stage));
movefile(Original_File,File);
end

function Status = classify(D,Target)
Raw = upper(string(D.solver_status));
if D.has_incumbent
    if isfinite(D.mip_gap) && D.mip_gap <= Target
        Status = "target_met";
    else
        Status = "feasible_target_not_met";
    end
elseif Raw == "INFEASIBLE" || (D.problem == 1 && Raw ~= "INF_OR_UNBD")
    Status = "proven_infeasible";
elseif any(Raw == ["TIME_LIMIT","NODE_LIMIT","ITERATION_LIMIT","SOLUTION_LIMIT", ...
        "WORK_LIMIT","MEM_LIMIT","INTERRUPTED","USER_OBJ_LIMIT"]) || D.problem == 3
    Status = "stopped_no_incumbent";
elseif Raw == "INF_OR_UNBD" || D.problem == 12 || D.problem == 0
    Status = "no_incumbent_unknown";
else
    Status = "solver_or_model_error";
end
% Numeric/model/license errors must remain visible even with an incumbent.
Known = ["OPTIMAL","INFEASIBLE","INF_OR_UNBD","TIME_LIMIT","NODE_LIMIT", ...
    "ITERATION_LIMIT","SOLUTION_LIMIT","WORK_LIMIT","MEM_LIMIT", ...
    "INTERRUPTED","USER_OBJ_LIMIT","SUBOPTIMAL"];
if any(Raw == ["NUMERIC","UNBOUNDED"]) || ...
        (~any(D.problem == [0,1,3,12,16]) && ~any(Raw == Known))
    Status = "solver_or_model_error";
end
end

function Row = summarize(Row,R,File,Stage,CONF)
validate_stage_result(R,CONF,str2double(extractAfter(Stage,"stage_")));
C = normalize_multiple_snapshot_conf(CONF);
[~,Candidate] = ismember(C.GFM_Module_Bus,C.GFM_Module_Candidates);
Index = sub2ind(size(R.u_GFM_Mod),Candidate(:),C.GFM_Module_Order(:));
Built = round(R.u_GFM_Mod(Index));
Counts = C.GFM_Candidate_Module_Mat*Built;
Row.Is_Feasible = true;
Row.Result_Validation_Passed = true;
Row.Final_Result_File = string(File);
Row.Final_Stage = Stage;
Row.Solver_Problem = R.Diagnostics.problem;
Row.Solver_Status = string(R.Diagnostics.solver_status);
Row.Solver_Info = string(R.Diagnostics.info);
Row.Final_MIP_Gap = R.Diagnostics.mip_gap;
Row.Objective_Best_Bound = R.Diagnostics.best_bound;
Row.Total_Annual_Cost = R.Cost.Total;
Row.GFM_ES_Fixed_Cost = R.Cost.CON;
Row.SG_Generation_Cost = R.Cost.GEN;
Row.SG_UC_Cost = R.Cost.UC;
Row.Wind_Curtailment_Cost = R.Cost.Curt;
Row.Cost_Sum_Residual = R.Cost.Total-sum([R.Cost.CON,R.Cost.GEN,R.Cost.UC,R.Cost.Curt]);
Row.GFM_Module_Count = sum(Built);
Row.GFM_Power_MW = sum(Built.*C.GFM_Module_PN(:));
Row.GFM_Energy_MWh = sum(Built.*C.GFM_Module_Rated_Energy(:));
Row.GFM_Installed_Buses = string(mat2str(C.GFM_Module_Candidates(Counts>0)));
Row.GFM_Candidate_Buses = string(mat2str(C.GFM_Module_Candidates(:).'));
Row.GFM_Modules_Per_Bus = string(mat2str(Counts(:).'));
Row.GFM_Configuration = string(mat2str(Built(:).'));
end

function validate_stage_result(R,CONF,Stage)
assert(isstruct(R) && all(isfield(R,{'CONF','Diagnostics','solve_time'})), ...
    'JointScan:IncompleteResult','Incomplete stage result.');
Expected = apply_multiple_snapshot_solver_stage(CONF, ...
    CONF.Solver.Two_Stage.(sprintf('Stage_%d',Stage)));
Expected = normalize_multiple_snapshot_conf(Expected);
A = R.CONF;
if isfield(A,'MIPStart'), A = rmfield(A,'MIPStart'); end
% Result.CONF is the normalized internal view, not the grouped public CONF.
A.solver.options.gurobi.LogFile = '';
Expected.solver.options.gurobi.LogFile = '';
assert(isequaln(A,Expected),'JointScan:ResultInputMismatch', ...
    'Saved CONF differs from current point/stage inputs.');
D = R.Diagnostics;
assert(all(isfield(D,{'problem','info','has_incumbent','mip_gap', ...
    'best_bound','objective','solver_status'})) && ...
    isscalar(D.has_incumbent) && isscalar(D.problem) && ...
    isscalar(R.solve_time) && isfinite(R.solve_time) && R.solve_time >= 0, ...
    'JointScan:BadDiagnostics','Invalid/incomplete diagnostics.');
assert(~(D.has_incumbent && upper(string(D.solver_status))=="INFEASIBLE"), ...
    'JointScan:ContradictoryDiagnostics','Infeasible status with an incumbent.');
if ~D.has_incumbent, return; end
assert(all(isfield(R,{'Cost','u_GFM_Mod','SecurityValidation','SCC_1','SCR', ...
    'SCC_TimeResolved','SCR_TimeResolved'})), ...
    'JointScan:IncompleteIncumbent','Incomplete feasible result.');
C = Expected;
assert(isequal(size(R.u_GFM_Mod), ...
    [C.GFM_Candidate_Count,C.GFM_MaxModulesPerCandidate]), ...
    'JointScan:ModuleDimensions','Unexpected module-decision dimensions.');
Binary_Fields = {'u_GFM_Mod','u_G','u_G_Start','u_G_Stop','u_GFM_Ch'};
Binary_Shapes = {[C.GFM_Candidate_Count,C.GFM_MaxModulesPerCandidate], ...
    [C.Gn,C.TypicalDayCount,C.PeriodCount], ...
    [C.Gn,C.TypicalDayCount,C.PeriodCount], ...
    [C.Gn,C.TypicalDayCount,C.PeriodCount], ...
    [C.GFM_Candidate_Count,C.TypicalDayCount,C.WindScenarioCount,C.PeriodCount]};
for n = 1:numel(Binary_Fields)
    assert(size_matches(R.(Binary_Fields{n}),Binary_Shapes{n}), ...
        'JointScan:DecisionDimensions','Invalid dimensions: %s',Binary_Fields{n});
end
for f = Binary_Fields
    V = R.(f{1});
    assert(~isempty(V) && all(isfinite(V(:))) && ...
        all(abs(V(:)-round(V(:)))<=1e-4) && all(V(:)>=-1e-4 & V(:)<=1+1e-4), ...
        'JointScan:InvalidIntegerSolution','Invalid integer decision %s.',f{1});
end
Continuous_Fields = {'P_G','P_GFL','P_GFL_Curt','P_GFM_Dis','P_GFM_Ch','E_GFM'};
for n = 1:numel(Continuous_Fields)
    if n == 1, N = C.Gn; elseif n<=3, N = C.Bn; else, N = C.GFM_Candidate_Count; end
    assert(size_matches(R.(Continuous_Fields{n}), ...
        [N,C.TypicalDayCount,C.WindScenarioCount,C.PeriodCount]), ...
        'JointScan:OperationDimensions','Invalid dimensions: %s',Continuous_Fields{n});
end
for f = Continuous_Fields
    V = R.(f{1});
    assert(~isempty(V) && all(isfinite(V(:))), ...
        'JointScan:InvalidOperation','Incomplete operation %s.',f{1});
end
Parts = [R.Cost.CON,R.Cost.GEN,R.Cost.UC,R.Cost.Curt];
Tol = max(1e-4,1e-8*abs(R.Cost.Total));
assert(numel(Parts)==4 && all(isfinite([Parts,R.Cost.Total])) && ...
    abs(sum(Parts)-R.Cost.Total)<=Tol && isfinite(D.objective) && ...
    abs(D.objective-R.Cost.Total)<=Tol, ...
    'JointScan:CostMismatch','Annual cost components/objective do not agree.');
SCC = R.SCC_1(C.SCC_Constraint_Original_Nodes,:);
SCR = R.SCR(C.Safety_GFL_Original_Nodes,:);
assert(size_matches(R.SCC_1,[C.Bn,C.TypicalDayCount]) && ...
    size_matches(R.SCR,[C.Bn,C.TypicalDayCount]) && ...
    size_matches(R.SCC_TimeResolved,[C.PeriodCount,C.TypicalDayCount, ...
    numel(C.SCC_Constraint_Original_Nodes)]) && ...
    size_matches(R.SCR_TimeResolved,[C.PeriodCount,C.TypicalDayCount, ...
    numel(C.Safety_GFL_Original_Nodes)]), ...
    'JointScan:SecurityDimensions','Incomplete security arrays.');
SCC_Tol = R.SecurityValidation.SCC.Tolerance;
SCR_Tol = R.SecurityValidation.SCR.Tolerance;
assert(R.SecurityValidation.Passed && ...
    all(isfinite(SCC(:))) && all(isfinite(SCR(:))) && ...
    all(isfinite(R.SCC_TimeResolved(:))) && all(isfinite(R.SCR_TimeResolved(:))) && ...
    ~isempty(R.SCC_TimeResolved) && ~isempty(R.SCR_TimeResolved) && ...
    max([SCC(:);R.SCC_TimeResolved(:)]) <= C.I_limit_kA_Node(1)+SCC_Tol && ...
    min([SCR(:);R.SCR_TimeResolved(:)]) >= C.SCR_min-SCR_Tol, ...
    'JointScan:SecurityValidation','Security results fail the current thresholds.');
end

function [Cached,Reason] = read_checkpoint(Row,Params,CONF,Manifest)
Cached = [];
Reason = "no checkpoint";
if ~isfile(Row.Point_File), return; end
try
    Data = load(Row.Point_File,'Record');
    Record = Data.Record;
    assert(isequaln(Record.Params,Params) && isequaln(Record.Manifest,Manifest), ...
        'JointScan:CheckpointInputMismatch','Checkpoint parameters/sources differ.');
    assert(Record.Row.I_limit_kA == Row.I_limit_kA && Record.Row.CSCR == Row.CSCR);
    Stage1 = []; Stage2 = [];
    for Stage = 1:2
        Path = Record.Row.(sprintf('Stage_%d_Result_File',Stage));
        if strlength(Path)==0, continue; end
        assert(strcmp(file_hash(Path),Record.Stage_Result_SHA256(Stage)), ...
            'JointScan:ChangedResult','Saved stage artifact changed.');
        Data = load(Path,'Result');
        validate_stage_result(Data.Result,CONF,Stage);
        if Stage == 1, Stage1 = Data.Result; else, Stage2 = Data.Result; end
    end
    assert(~isempty(Stage1),'JointScan:MissingStage1','Missing stage-1 artifact.');
    if Record.Row.Is_Feasible
        if Record.Row.Final_Stage=="stage_1", Expected_File = Record.Row.Stage_1_Result_File;
        else, Expected_File = Record.Row.Stage_2_Result_File; end
        assert(strlength(Expected_File)>0 && Record.Row.Final_Result_File==Expected_File, ...
            'JointScan:FinalArtifactMismatch','Final result does not match its stage.');
        Data = load(Record.Row.Final_Result_File,'Result');
        Fresh = summarize(Row,Data.Result,Record.Row.Final_Result_File, ...
            Record.Row.Final_Stage,CONF);
        Fields = {'Total_Annual_Cost','GFM_Module_Count','GFM_Configuration', ...
            'Final_MIP_Gap','GFM_Power_MW','GFM_Energy_MWh'};
        for f = Fields
            assert(isequaln(Fresh.(f{1}),Record.Row.(f{1})), ...
                'JointScan:CheckpointSummaryMismatch','Checkpoint summary differs.');
        end
    end
    if Record.Row.Status == "target_met"
        assert(Record.Row.Completed && Record.Row.Is_Feasible && ...
            Record.Row.Final_MIP_Gap<=Row.Target_MIP_Gap);
    elseif Record.Row.Status == "proven_infeasible"
        assert(Record.Row.Completed && ~Record.Row.Is_Feasible && ...
            classify(Stage1.Diagnostics,Row.Target_MIP_Gap)=="proven_infeasible");
    end
    Cached = struct('Row',Record.Row,'Stage1',Stage1,'Stage2',Stage2);
    Reason = "validated checkpoint";
catch ME
    Reason = "checkpoint rejected: " + string(ME.message);
    fprintf(2,'%s\n',Reason);
end
end

function save_checkpoint(Row,Params,Manifest)
Record = struct('Row',Row,'Params',Params,'Manifest',Manifest);
Record.Stage_Result_SHA256 = strings(1,2);
for Stage = 1:2
    File = Row.(sprintf('Stage_%d_Result_File',Stage));
    if strlength(File)>0 && isfile(File)
        Record.Stage_Result_SHA256(Stage) = string(file_hash(File));
    end
end
atomic_save(char(Row.Point_File),struct('Record',Record));
end

function Row = reset_solution(Row)
Fresh = empty_row();
Keep = {'I_limit_kA','CSCR','SCR_Row','SCC_Column','Target_MIP_Gap', ...
    'Parameter_File','Point_File','Attempt_Directory','Resume_Note'};
for f = Keep, Fresh.(f{1}) = Row.(f{1}); end
Row = Fresh;
Row.Status = "running";
end

function [Table,Joint] = export_summary(Rows,I,SCR,Manifest,File,Executed,Case5_Audit)
Table = struct2table(Rows);
Shape = [numel(SCR),numel(I)];
Joint = struct('I_Limit_Values_kA',I,'CSCR_Values',SCR, ...
    'Row_Axis','CSCR','Column_Axis','SCC upper limit (kA)', ...
    'Manifest',Manifest,'Execute',Executed,'Summary_Table',Table, ...
    'Case5_Reference_Audit',Case5_Audit);
Fields = {'Total_Annual_Cost','GFM_Module_Count','GFM_Configuration','Status', ...
    'Final_MIP_Gap','Is_Feasible','Objective_Best_Bound','GFM_Power_MW','GFM_Energy_MWh'};
Names = {'Cost_Matrix','Module_Count_Matrix','Configuration_Matrix','Status_Matrix', ...
    'MIP_Gap_Matrix','Feasible_Matrix','Best_Bound_Matrix','Power_MW_Matrix','Energy_MWh_Matrix'};
for n = 1:numel(Fields)
    Joint.(Names{n}) = reshape(Table.(Fields{n}),Shape);
end
Joint.Grid_Complete = all(Table.Completed);
Joint.Grid_Count = height(Table);
Joint.Monotonicity = monotonicity(Table);
atomic_save(File,struct('Joint',Joint,'Summary_Table',Table));
Directory = fileparts(File);
writetable(Table,fullfile(Directory,'joint_summary.csv'));
for n = 1:numel(Names)
    Matrix_Table = array2table(Joint.(Names{n}), ...
        'VariableNames',cellstr("SCC_"+string(I)+"_kA"));
    Matrix_Table = addvars(Matrix_Table,SCR,'Before',1,'NewVariableNames','CSCR');
    writetable(Matrix_Table,fullfile(Directory,[Names{n},'.csv']));
end
writetable(Joint.Monotonicity,fullfile(Directory,'monotonicity_checks.csv'));
end

function Checks = monotonicity(T)
% For minimization: reliable lower bound at loose point <= optimum at tight point
% <= tight incumbent. Overlapping intervals explain apparent reversals by MIP gap.
Loose = zeros(0,1); Tight = Loose; Drop = Loose; Bound_Excess = Loose;
Assessment = strings(0,1);
Valid = find(T.Status=="target_met" & T.Result_Validation_Passed & ...
    isfinite(T.Objective_Best_Bound) & isfinite(T.Total_Annual_Cost));
for a = Valid(:).'
    for b = Valid(:).'
        if a==b, continue; end
        Is_Tighter = T.I_limit_kA(b)<=T.I_limit_kA(a) && T.CSCR(b)>=T.CSCR(a) && ...
            (T.I_limit_kA(b)<T.I_limit_kA(a) || T.CSCR(b)>T.CSCR(a));
        if ~Is_Tighter, continue; end
        Loose(end+1,1) = a; Tight(end+1,1) = b; %#ok<AGROW>
        Drop(end+1,1) = T.Total_Annual_Cost(a)-T.Total_Annual_Cost(b); %#ok<AGROW>
        Bound_Excess(end+1,1) = T.Objective_Best_Bound(a)-T.Total_Annual_Cost(b); %#ok<AGROW>
        Tol = max(1e-4,1e-8*max(abs(T.Total_Annual_Cost([a,b]))));
        if Bound_Excess(end)>Tol
            Assessment(end+1,1) = "review_disjoint_bounds"; %#ok<AGROW>
        elseif Drop(end)>Tol
            Assessment(end+1,1) = "reversal_within_MIP_uncertainty"; %#ok<AGROW>
        else
            Assessment(end+1,1) = "consistent"; %#ok<AGROW>
        end
    end
end

Checks = table(Loose,Tight,Drop,Bound_Excess,Assessment);
end

function Yes = size_matches(Value,Expected)
Actual = size(Value);
Actual(end+1:numel(Expected)) = 1;
Yes = isequal(Actual,Expected);
end

function Sources = source_signatures(Root)
Files = dir(fullfile(Root,'code','functions','**','*.m'));
Paths = arrayfun(@(x) fullfile(x.folder,x.name),Files,'UniformOutput',false);
Paths{end+1} = fullfile(Root,'data','params','generate_multiple_snapshot_default_params.m');
Paths{end+1} = which('case30');
% Include the resolved stage entry point (also separates synthetic test runs).
Paths{end+1} = which('solve_one_stage');
Paths{end+1} = fullfile(Root,'data','RTS-GMLC','processed', ...
    'rts_gmlc_v0.2.3_fixed_extreme_medoids','run_20260822_162606', ...
    'rts_gmlc_typical_days_and_wind_scenarios_20260822_162606.mat');
Paths = unique(Paths);
Sources = struct('Path',Paths(:),'SHA256',repmat({''},numel(Paths),1));
for n = 1:numel(Paths), Sources(n).SHA256 = file_hash(Paths{n}); end
end

function Hash = file_hash(Path)
fid = fopen(Path,'rb');
assert(fid>=0,'JointScan:MissingSource','Cannot read source: %s',Path);
Cleanup = onCleanup(@() fclose(fid));
Digest = java.security.MessageDigest.getInstance('SHA-256');
Digest.update(fread(fid,Inf,'*uint8'));
Hash = lower(reshape(dec2hex(typecast(Digest.digest(),'uint8'),2).',1,[]));
end

function write_json(File,Params)
fid = fopen(File,'w','n','UTF-8');
assert(fid>=0,'JointScan:WriteFailed','Cannot write %s',File);
Cleanup = onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(Params,'PrettyPrint',true));
end

function atomic_save(File,Payload)
Temporary = [tempname(fileparts(File)),'.mat'];
save(Temporary,'-struct','Payload','-v7.3');
movefile(Temporary,File,'f');
end

function Token = number_token(Number)
% JSON uses round-trip decimal tokens, avoiding one-decimal rounding collisions.
Token = strrep(strrep(jsonencode(Number),'.','p'),'-','m');
end

function Row = empty_row()
Row = struct('I_limit_kA',NaN,'CSCR',NaN,'SCR_Row',NaN,'SCC_Column',NaN, ...
    'Status',"pending",'Completed',false,'Is_Feasible',false, ...
    'Result_Validation_Passed',false,'Target_MIP_Gap',NaN,'Final_MIP_Gap',NaN, ...
    'Solver_Problem',NaN,'Solver_Status',"",'Solver_Info',"", ...
    'Total_Annual_Cost',NaN,'Objective_Best_Bound',NaN, ...
    'GFM_ES_Fixed_Cost',NaN,'SG_Generation_Cost',NaN,'SG_UC_Cost',NaN, ...
    'Wind_Curtailment_Cost',NaN,'Cost_Sum_Residual',NaN, ...
    'GFM_Module_Count',NaN,'GFM_Power_MW',NaN,'GFM_Energy_MWh',NaN, ...
    'GFM_Installed_Buses',"",'GFM_Candidate_Buses',"", ...
    'GFM_Modules_Per_Bus',"",'GFM_Configuration',"",'Runtime_s',NaN, ...
    'Stage_1_Solve_Time_s',NaN,'Stage_2_Solve_Time_s',NaN,'Total_Solve_Time_s',NaN, ...
    'Stage_1_Status',"",'Stage_2_Status',"",'Final_Stage',"", ...
    'Parameter_File',"",'Point_File',"",'Stage_1_Result_File',"", ...
    'Stage_2_Result_File',"",'Final_Result_File',"",'Attempt_Directory',"", ...
    'Resume_Note',"",'Error_Identifier',"",'Error_Message',"");
end
