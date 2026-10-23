function CONF = normalize_multiple_snapshot_conf(CONF)
%% 将分组配置转换为求解器内部使用的扁平字段。
% 公开的CONF按模型主题分组；该函数只在函数内部建立求解视图，
% 不会改变调用方持有的分组结构。

if ~isfield(CONF,'ModelVersion')
    CONF.ModelVersion = '2026-10-23';
end

if ~isfield(CONF, 'Network')
    if isfield(CONF, 'solver')
        CONF.solver = normalize_solver_configuration(CONF.solver);
    end
    CONF.Enable_SCC = read_optional_logical_scalar(CONF, 'Enable_SCC', true);
    CONF.Enable_SCR = read_optional_logical_scalar(CONF, 'Enable_SCR', true);
    return;
end

N = CONF.Network;
GFL = CONF.GFL_WG;
GFM = CONF.GFM_Modules;
MODULE = GFM.Module;
ELECTRICAL = GFM.Electrical;
STORAGE = GFM.Storage;
CANDIDATES = GFM.Candidates;
COSTS = GFM.Costs;
CONFIGS = GFM.Configurations;
SEC = CONF.Security;
SOLVER = CONF.Solver;
MULTI = CONF.Multiple_Snapshot;
TIME = MULTI.Time;
PROFILES = MULTI.Profiles;
WIND = MULTI.Wind_Scenarios;
DEGRADATION = MULTI.Degradation;
UC = CONF.UC;

runtime = struct();
runtime.ModelVersion = CONF.ModelVersion;

runtime.Bn = N.Bn;
runtime.Gn = N.Gn;
runtime.Ln = N.Ln;
runtime.Base_MVA = N.Base_MVA;
runtime.Base_kV = N.Base_kV;
runtime.Base_kA = N.Base_kA;
runtime.Base_O = N.Base_O;
runtime.Xd_Gen = N.Xd_Gen;
runtime.GenCostBreakpoints = N.Gen_Cost_Breakpoints;

runtime.u_GFL = GFL.u_GFL;
runtime.GFL_Curtailment_Cost_per_MWh = ...
    GFL.Curtailment_Cost_per_MWh;
runtime.PN_GFL = GFL.PN_MW;
runtime.PN_GFL_pu_Node = GFL.PN_pu;
runtime.PN_GFL_Node = GFL.PN_pu*N.Base_MVA;
runtime.KQ_GFL_Node = GFL.K_Q;
runtime.I_GFL_N_Rated_Node = GFL.I_N_Rated;
runtime.Delta_I_GFL_Rated_Node = GFL.Delta_I_Rated;
runtime.I_GFL_N_pu_Node = GFL.I_N_pu;
runtime.Delta_I_GFL_pu_Node = GFL.Delta_I_pu;
runtime.V_LVRT_On_Node = GFL.V_LVRT_On;
runtime.V_LVRT_Sat_Node = GFL.V_LVRT_Sat;

runtime.GFM_Module_Count = MODULE.Count;
runtime.GFM_Module_Bus = MODULE.Bus;
runtime.GFM_Module_Order = MODULE.Module_Index;
runtime.GFM_Module_PN = MODULE.PN_MW;
runtime.GFM_Module_PN_pu = MODULE.PN_pu;
runtime.GFM_Module_Cost_Conv = COSTS.Cost_Conv_GFM;
runtime.GFM_Module_Rated_Energy = STORAGE.Rated_Energy_MWh;
runtime.GFM_Module_X_Res = ELECTRICAL.X_GFM_Res;
runtime.GFM_Module_I_post = ELECTRICAL.I_post;
runtime.GFM_Module_X_Vir = ELECTRICAL.X_GFM_Vir;
runtime.GFM_Module_DeltaY = ELECTRICAL.Delta_Y;
runtime.GFM_Module_DeltaY_abs = ELECTRICAL.Delta_Y_abs;
runtime.GFM_Module_Loc_Mat = MODULE.Loc_Mat;
runtime.GFM_Module_Candidates = CANDIDATES.Bus;
runtime.GFM_Module_Candidate_Index = CANDIDATES.Module_Index;
runtime.GFM_Candidate_Count = CANDIDATES.Count;
runtime.GFM_Candidate_Loc_Mat = CANDIDATES.Loc_Mat;
runtime.GFM_Candidate_Module_Mat = CANDIDATES.Module_Mat;
runtime.GFM_Candidate_Charge_Efficiency = STORAGE.Charge_Efficiency;
runtime.GFM_Candidate_Discharge_Efficiency = ...
    STORAGE.Discharge_Efficiency;
runtime.GFM_Candidate_Rated_Duration = STORAGE.Rated_Duration;
runtime.GFM_Candidate_SOC_Max = STORAGE.SOC_Max;
runtime.GFM_Candidate_SOC_Initial = STORAGE.SOC_Initial;
runtime.GFM_Candidate_SOC_Min = STORAGE.SOC_Min;
runtime.N_GFM_Module_Max = CONFIGS.N_Module_Max;
runtime.GFM_MaxModulesPerCandidate = CONFIGS.Max_Modules_Per_Candidate;
runtime.GFM_Module_Sequential = CONFIGS.Enforce_Sequential_Build;
runtime.GFM_Module_I_Post_Multiplier = ELECTRICAL.I_Post_Multiplier;
runtime.GFM_Config_Count = CONFIGS.Count;
runtime.GFM_Config_Module_Matrix = CONFIGS.Module_Matrix;
runtime.GFM_Config_Candidate_Matrix = CONFIGS.Candidate_Matrix;
runtime.GFM_Config_A_cne = CONFIGS.A_cne;
runtime.GFM_Config_Module_Count = CONFIGS.Module_Count;

runtime.Safety_Retained_Nodes = SEC.Source_Nodes_Original;
runtime.Safety_Original_To_Reduced = zeros(N.Bn,1);
runtime.Safety_Original_To_Reduced(SEC.Source_Nodes_Original) = ...
    SEC.Source_Nodes_Reduced;
runtime.Safety_Node_Count = SEC.Source_Nodes_Count;
runtime.Safety_GFL_Original_Nodes = SEC.SCR_Nodes_Original;
runtime.Safety_GFL_Reduced_Indices = SEC.SCR_Nodes_Reduced;
runtime.Safety_GFL_Count = SEC.SCR_Nodes_Count;
runtime.SCC_Constraint_Original_Nodes = SEC.SCC_Nodes_Original;
runtime.I_limit_kA_Node = SEC.I_limit_kA;
runtime.I_limit = SEC.I_limit_pu;
runtime.SCR_min = SEC.SCR_min;
runtime.Enable_SCC = read_optional_logical_scalar(SEC, 'Enable_SCC', true);
runtime.Enable_SCR = read_optional_logical_scalar(SEC, 'Enable_SCR', true);
runtime.KZ = SOLVER.KZ;
runtime.ERR_TOL = SOLVER.ERR_TOL;
runtime.ZBoundMargin = SOLVER.Z_Bound_Margin;
runtime.Require_Source_Online = SEC.Require_Source_Online;

runtime.TypicalDayCount = TIME.Typical_Day_Count;
runtime.PeriodCount = TIME.Period_Count;
runtime.TypicalDayWeights_Days = TIME.Typical_Day_Weights_Days;
runtime.PeriodDurations_Hours = TIME.Period_Durations_Hours;
runtime.OperatingWeights_Hours = TIME.Operating_Weights_Hours;
runtime.P_Load_Profile = PROFILES.P_Load_Profile;
runtime.P_GFL_Available_Profile = PROFILES.P_GFL_Available_Profile;
runtime.WindScenarioCount = WIND.Count;
runtime.WindScenarioNames = WIND.Names;
runtime.WindScenarioProbabilities = WIND.Probabilities;
runtime.WindScenarioScaleFactors = WIND.Scale_Factors;
runtime.WindScenarioGenerationMode = WIND.Generation_Mode;
runtime.WindScenarioBaseIndex = WIND.Base_Index;
runtime.P_GFL_Available_Scenarios = WIND.P_GFL_Available_Scenarios;
runtime.DeterministicDegradation = DEGRADATION.Deterministic;

runtime.Gen_Pmin = UC.Gen_Pmin_MW;
runtime.Gen_Ramp_Up_MW_per_Hour = UC.Ramp_Up_Rate_MW_per_Hour;
runtime.Gen_Ramp_Down_MW_per_Hour = UC.Ramp_Down_Rate_MW_per_Hour;
runtime.Gen_Min_Up_Periods = UC.Min_Up_Periods;
runtime.Gen_Min_Down_Periods = UC.Min_Down_Periods;
runtime.Gen_Startup_Cost = UC.Startup_Cost;
runtime.Gen_Shutdown_Cost = UC.Shutdown_Cost;

runtime.solver = normalize_solver_configuration(CONF.solver);
runtime.ObjectiveScale = SOLVER.Objective_Scale;
if isfield(SOLVER, 'Solve_Stage')
    runtime.SolveStage = SOLVER.Solve_Stage;
end

if isfield(SOLVER, 'MIP_Start')
    runtime.MIPStart = SOLVER.MIP_Start;
end

CONF = runtime;

end

function Solver = normalize_solver_configuration(Solver)
%% Validate Gurobi selection while preserving its native option names.

if ~isstruct(Solver) || ~isfield(Solver, 'name') || ...
        ~isfield(Solver, 'options') || ~isstruct(Solver.options)
    error('MultipleSnapshotConfig:InvalidSolverConfiguration', ...
        'solver must define name and options fields.');
end

Solver_Name = Solver.name;
if isstring(Solver_Name) && isscalar(Solver_Name)
    Solver_Name = char(Solver_Name);
end
if ~ischar(Solver_Name) || ~isrow(Solver_Name)
    error('MultipleSnapshotConfig:InvalidSolverName', ...
        'solver.name must be Gurobi.');
end
Solver_Name = lower(strtrim(Solver_Name));
if ~strcmp(Solver_Name, 'gurobi')
    error('MultipleSnapshotConfig:InvalidSolverName', ...
        'Only Gurobi is supported as the MILP solver.');
end
if ~isfield(Solver.options, Solver_Name) || ...
        ~isstruct(Solver.options.(Solver_Name))
    error('MultipleSnapshotConfig:MissingSolverOptions', ...
        'solver.options must contain a native options struct for %s.', ...
        Solver_Name);
end
Solver.name = Solver_Name;

end
function Value = read_optional_logical_scalar(Input, Field_Name, Default_Value)
%% 统一旧版CONF兼容默认值与逻辑标量校验。

if ~isfield(Input,Field_Name)
    Value = Default_Value;
    return;
end
Value = Input.(Field_Name);
if ~islogical(Value) || ~isscalar(Value)
    error('MultipleSnapshotConfig:InvalidLogicalSwitch', ...
        '%s必须为标量逻辑值true或false。',Field_Name);
end

end
