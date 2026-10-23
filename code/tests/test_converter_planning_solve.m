function Tests = test_converter_planning_solve
%% 使用用户已配置的求解器验证小规模MILP；不自动切换求解器。
Tests = functiontests(localfunctions);
end

function setupOnce(Test)
Root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(genpath(fullfile(Root,'code','functions')));
[Test.TestData.mpc,C] = build_converter_test_case();
Name = C.solver.name;
% 验证专用时限与精度，求解器固定为Gurobi。
assert(strcmp(Name,'gurobi'), 'The planning tests require Gurobi.');
C.solver.options.gurobi.TimeLimit = 30;
C.solver.options.gurobi.MIPGap = 1e-8;
C.solver.options.gurobi.LogFile = '';
C.solver.options.gurobi.OutputFlag = 0;
C.solver.options.yalmip.verbose = 0;
Test.TestData.CONF = C;
end

function testDispatchCostsAndCyclicEnergy(Test)
C = Test.TestData.CONF;
mpc = Test.TestData.mpc;
Model = build_multiple_snapshot_planning_model(mpc,C);
V = Model.Variables;
Constraints = [Model.Constraints, V.u_SG == 1, V.u_GFM_Module == 1, ...
    V.P_GFM_Ch(:,:,:,1) == 1, V.P_GFM_Ch(:,:,:,2:3) == 0, ...
    V.P_GFM_Dis(:,:,:,1) == 0, V.P_GFM_Dis(:,:,:,2) == 0.81, ...
    V.P_GFM_Dis(:,:,:,3) == 0];
Sol = optimize(Constraints,Model.Objective,build_multiple_snapshot_solver_options(C.solver,false));
require_solution(Test,Sol);
verifyGreaterThanOrEqual(Test,min(check(Constraints)),-1e-6);
Pg = value(V.P_SG); Pw = value(V.P_GFL); Pe = value(V.P_GFM);
Flow = value(V.P_Line); E = value(V.E_GFM);
verifyEqual(Test,E(:,:,:,3),25*ones(1,2,2),'AbsTol',1e-6);
verifyEqual(Test,E(:,:,:,1),32.2*ones(1,2,2),'AbsTol',1e-6);
verifyEqual(Test,value(V.u_SG_Start),zeros(2,2,3),'AbsTol',1e-6);
verifyEqual(Test,value(V.u_SG_Stop),zeros(2,2,3),'AbsTol',1e-6);
Expected_GEN = 0; Expected_Curt = 0;
for d = 1:2
    for k = 1:2
        for t = 1:3
            Injection = Model.NET.Generator_Location_Matrix*Pg(:,d,k,t) + ...
                Pw(:,d,k,t)+Pe(:,d,k,t)-C.P_Load_Profile(:,d,t);
            verifyEqual(Test,Injection, ...
                (Model.NET.Branch_Matrix_From-Model.NET.Branch_Matrix_To)*Flow(:,d,k,t),'AbsTol',1e-6);
            verifyEqual(Test,Flow(:,d,k,t),Model.NET.Line_B_Series.* ...
                (value(V.theta(Model.NET.Branch_From,d,k,t))- ...
                value(V.theta(Model.NET.Branch_To,d,k,t))),'AbsTol',1e-6);
            Weight = C.OperatingWeights_Hours(d,t)*C.WindScenarioProbabilities(d,k);
            for g = 1:2
                Tangency_P = C.Gen_Pmin(g)+(mpc.gen(g,9)-C.Gen_Pmin(g))*C.GenCostBreakpoints;
                a = mpc.gencost(g,5); b = mpc.gencost(g,6); c = mpc.gencost(g,7);
                Expected_GEN = Expected_GEN+Weight*max( ...
                    (2*a*Tangency_P+b)*Pg(g,d,k,t)+c-a*Tangency_P.^2);
            end
            Expected_Curt = Expected_Curt+Weight*C.GFL_Curtailment_Cost_per_MWh* ...
                sum(C.P_GFL_Available_Scenarios(:,d,k,t)-Pw(:,d,k,t));
        end
    end
end
verifyEqual(Test,value(Model.Cost.Cost_GEN),Expected_GEN,'AbsTol',1e-4);
verifyEqual(Test,value(Model.Cost.Cost_Curt),Expected_Curt,'AbsTol',1e-4);
verifyEqual(Test,value(Model.Cost.Cost_GFM_Fixed),250,'AbsTol',1e-8);
verifyEqual(Test,value(Model.Cost.Cost_Total_Annual),Expected_GEN+Expected_Curt+250,'AbsTol',1e-4);
SEC = Model.Security.Network;
SCC = calculate_converter_security_state(SEC,C,[1;1],[1;1]);
verifyEqual(Test,value(Model.Security.SCC)*C.Base_kA,repmat(SCC,1,2),'AbsTol',1e-6);
fprintf('Fixture annual objective: %.9f\n',value(Model.Cost.Cost_Total_Annual));
end

function testHourlyComponentSupportDoesNotRequireIntersectionSupport(Test)
C = Test.TestData.CONF;
C.TypicalDayCount = 1; C.PeriodCount = 2;
NET = build_multiple_snapshot_network(Test.TestData.mpc,C);
U = binvar(2,1,2,'full'); Union = binvar(2,1); Intersection = binvar(2,1);
Modules = binvar(2,1);
[Constraints,~] = add_converter_security_constraints(NET,C,U,Union,Intersection,Modules);
Constraints = [Constraints,U(:,1,1) == [1;0],U(:,1,2) == [0;1],Modules == [1;0]];
Sol = optimize(Constraints,0,build_multiple_snapshot_solver_options(C.solver,false));
require_solution(Test,Sol);
verifyEqual(Test,value(Union),[1;1],'AbsTol',1e-6);
verifyEqual(Test,value(Intersection),[0;0],'AbsTol',1e-6);
end

function testPublicSolveAndResultSchema(Test)
C = Test.TestData.CONF;
Paths.results_dir = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), ...
    'tmp','migration','test_results');
if ~isfolder(Paths.results_dir), mkdir(Paths.results_dir); end
[Result,File] = solve_one_stage(Test.TestData.mpc,C,Paths);
verifyTrue(Test,isfile(File));
verifyFalse(Test,isfield(Result,'lambda_c'));
verifyTrue(Test,isempty(Result.Z_SCC));
verifyEqual(Test,Result.Diagnostics.ModelVersion,'2026-10-23');
verifyTrue(Test,Result.SecurityValidation.Passed);
verifyLessThan(Test,Result.Diagnostics.SecurityPosthocRegression.SCC_MaxAbsDifference_kA,1e-6);
verifyLessThan(Test,Result.Diagnostics.SecurityPosthocRegression.Z_SCR_MaxAbsDifference_pu,1e-6);
% 新结果继续通过现有绘图数据入口；不要求新版SCC提供无用的电抗矩阵。
Params.Network.mpc = Test.TestData.mpc;
Params.Security = struct('Enable_SCC',true,'Enable_SCR',true,'SCR_min',C.SCR_min);
Params.GFM_Modules.Candidates.Bus = C.GFM_Module_Candidates;
Params.Multiple_Snapshot.Time = struct('Typical_Day_Count',2,'Period_Count',3, ...
    'Period_Durations_Hours',C.PeriodDurations_Hours, ...
    'Typical_Day_Weights_Days',C.TypicalDayWeights_Days);
Params.Multiple_Snapshot.Profiles = struct('Load_P_MW',C.P_Load_Profile, ...
    'GFL_Available_P_MW',C.P_GFL_Available_Profile);
Params.Multiple_Snapshot.Wind_Scenarios = struct('Count',2, ...
    'Probabilities',C.WindScenarioProbabilities);
Data = prepare_figure_data(Result,Params,File,'synthetic fixture',1);
verifyEqual(Test,Data.Module_Built,reshape(Result.u_GFM_Mod,[],1));
verifyEqual(Test,size(Data.Security.SCR_Limit),[2 2]);
end

function testCyclicUCAndIndependentDays(Test)
C = Test.TestData.CONF;
Model = build_multiple_snapshot_planning_model(Test.TestData.mpc,C);
V = Model.Variables;
Constraints = [Model.Constraints,V.u_GFM_Module == 1, ...
    V.u_SG(1,1,1:2) == 1,V.u_SG(1,1,3) == 0, ...
    V.u_SG(1,2,:) == 0,V.u_SG(2,:,:) == 1];
Sol = optimize(Constraints,Model.Objective,build_multiple_snapshot_solver_options(C.solver,false));
require_solution(Test,Sol);
verifyEqual(Test,reshape(value(V.u_SG_Start(1,1,:)),1,[]),[1 0 0],'AbsTol',1e-6);
verifyEqual(Test,reshape(value(V.u_SG_Stop(1,1,:)),1,[]),[0 0 1],'AbsTol',1e-6);
verifyEqual(Test,value(V.u_SG_Start(1,2,:)),zeros(1,1,3),'AbsTol',1e-6);
verifyEqual(Test,value(Model.Cost.Cost_UC),180*(20+5),'AbsTol',1e-6);
% 在相同循环边界下，将最小开机时间延长至3，强制的2时段开机不可行。
C.Gen_Min_Up_Periods(1) = 3;
Other = build_multiple_snapshot_planning_model(Test.TestData.mpc,C);
U = Other.Variables.u_SG;
Options = build_multiple_snapshot_solver_options(C.solver,false);
if strcmp(C.solver.name,'gurobi')
    Options.gurobi.DualReductions = 0; % 区分不可行与INF_OR_UNBD。
end
Sol = optimize([Other.Constraints,U(1,1,1:2) == 1,U(1,1,3) == 0], ...
    Other.Objective,Options);
verifyEqual(Test,Sol.problem,1);
end

function require_solution(Test,Sol)
% 缺少后端或许可证记为未执行；模型不可行/数值错误必须报告失败。
assumeFalse(Test,any(Sol.problem == [-3 -4 -5]), ...
    sprintf('Configured solver unavailable: %s',Sol.info));
assertEqual(Test,Sol.problem,0,Sol.info);
end
