function [mpc, CONF, paths] = load_multiple_snapshot_case(Project_Root, Parameter_File)
%% 本函数功能是加载场景随机多时段算例并构造优化配置参数。
% 本函数独立读取静态网络、设备、安全约束、典型日和风电场景参数。
% 第二输出按Network、GFL_WG、GFM_Modules、Security、Multiple_Snapshot、UC、Solver分组。

params = read_json_file(Parameter_File);

%% 1. 构造MATPOWER算例
Network_Parameters = params.Network;
mpc = Network_Parameters.mpc;

% 按参数文件给定比例修正线路电阻、电抗和对地电纳。
mpc.branch(:,3) = Network_Parameters.Branch_Scale.r*mpc.branch(:,3);
mpc.branch(:,4) = Network_Parameters.Branch_Scale.x*mpc.branch(:,4);
mpc.branch(:,5) = Network_Parameters.Branch_Scale.b*mpc.branch(:,5);

%% 2. 构造基础优化配置
CONF = struct();

CONF.Bn = size(mpc.bus,1);
CONF.Gn = size(mpc.gen,1);
CONF.Ln = size(mpc.branch,1);

CONF.Base_MVA = Network_Parameters.Base_MVA;
CONF.Base_kV  = Network_Parameters.Base_kV;
CONF.Base_kA  = Network_Parameters.Base_kA;
CONF.Base_O   = Network_Parameters.Base_O;

% 文档按同步机分别定义次暂态电抗；标量输入仍兼容为全机组统一值。
CONF.Xd_Gen = expand_generator_parameter( ...
    Network_Parameters.Xd_Gen, CONF.Gn, 'Xd_Gen');
if any(~isfinite(CONF.Xd_Gen)) || any(CONF.Xd_Gen <= 0)
    error('Xd_Gen必须为有限正数。');
end
CONF.GenCostBreakpoints = Network_Parameters.Gen_Cost_Breakpoints(:)';

%% 3. 读取GFL-WG参数
GFL_Parameters = params.GFL_WG;
GFL_Built_Nodes = GFL_Parameters.Built_Nodes(:);
CONF.u_GFL = zeros(CONF.Bn,1);
CONF.u_GFL(GFL_Built_Nodes) = 1;

% 单位弃风惩罚成本用于将逐时弃风功率折算为全年弃风成本。
CONF.GFL_Curtailment_Cost_per_MWh = GFL_Parameters.Curtailment_Cost_per_MWh;
CONF.PN_GFL_Node = expand_built_node_parameter( ...
    GFL_Parameters.PN_MW, GFL_Built_Nodes, CONF.Bn);
if any(~isfinite(CONF.PN_GFL_Node(GFL_Built_Nodes))) || ...
        any(CONF.PN_GFL_Node(GFL_Built_Nodes) <= 0)
    error('已建GFL-WG场站额定功率必须为有限正数。');
end
CONF.PN_GFL = max(CONF.PN_GFL_Node(CONF.u_GFL > 0.5));
CONF.PN_GFL_pu_Node = CONF.PN_GFL_Node/CONF.Base_MVA;

% Manuscript Section II-C的LVRT参数以各GFL-WG额定功率为基准，并同时保存
% 设备额定基准值与系统基准标幺值。
CONF.KQ_GFL_Node = expand_built_node_parameter( ...
    GFL_Parameters.K_Q, GFL_Built_Nodes, CONF.Bn);
I_GFL_N_Rated = expand_built_node_parameter( ...
    GFL_Parameters.I_N_Rated, ...
    GFL_Built_Nodes, CONF.Bn);
Delta_I_GFL_Rated = expand_built_node_parameter( ...
    GFL_Parameters.Delta_I_Rated, ...
    GFL_Built_Nodes, CONF.Bn);
CONF.V_LVRT_On_Node = expand_built_node_parameter( ...
    GFL_Parameters.V_LVRT_On, GFL_Built_Nodes, CONF.Bn);
CONF.V_LVRT_Sat_Node = expand_built_node_parameter( ...
    GFL_Parameters.V_LVRT_Sat, ...
    GFL_Built_Nodes, CONF.Bn);
CONF.I_GFL_N_Rated_Node = I_GFL_N_Rated;
CONF.Delta_I_GFL_Rated_Node = Delta_I_GFL_Rated;
CONF.I_GFL_N_pu_Node = I_GFL_N_Rated.*CONF.PN_GFL_Node/CONF.Base_MVA;
CONF.Delta_I_GFL_pu_Node = Delta_I_GFL_Rated.*CONF.PN_GFL_Node/CONF.Base_MVA;

% 故障节点饱和增量电流与LVRT饱和段共用Delta_I_GFL参数。
validate_gfl_lvrt_parameters(CONF, GFL_Built_Nodes);

% 安全阈值开关采用严格逻辑标量；旧版JSON缺少字段时保持完整模型默认值。
CONF.Enable_SCC = read_optional_logical_scalar( ...
    params.Security, 'Enable_SCC', true);
CONF.Enable_SCR = read_optional_logical_scalar( ...
    params.Security, 'Enable_SCR', true);
CONF.Require_Source_Online = logical(params.Security.Require_Source_Online);

%% 4. 读取模块化GFM-ES参数
GFM_Modules = build_gfm_module_params(params, CONF);
CONF.GFM_Module_Count = GFM_Modules.Count;
CONF.GFM_Module_Bus = GFM_Modules.Bus;
CONF.GFM_Module_Order = GFM_Modules.Order;
CONF.GFM_Module_PN = GFM_Modules.PN_MW;
CONF.GFM_Module_PN_pu = GFM_Modules.PN_MW/CONF.Base_MVA;
CONF.GFM_Module_Rated_Energy = GFM_Modules.Rated_Energy_MWh;
CONF.GFM_Module_X_Res = GFM_Modules.X_GFM_Res;
CONF.GFM_Module_I_post = GFM_Modules.I_Post;
CONF.GFM_Module_X_Vir = GFM_Modules.X_GFM_Vir;
CONF.GFM_Module_DeltaY = GFM_Modules.Delta_Y;
CONF.GFM_Module_DeltaY_abs = GFM_Modules.Delta_B;
CONF.GFM_Module_Loc_Mat = sparse(GFM_Modules.Bus,(1:GFM_Modules.Count)', ...
    1,CONF.Bn,GFM_Modules.Count);
CONF.GFM_Module_Candidates = GFM_Modules.Candidate_Bus(:)';
CONF.GFM_Module_Candidate_Index = GFM_Modules.Candidate_Index;
CONF.GFM_Candidate_Count = numel(GFM_Modules.Candidate_Bus);
CONF.GFM_Candidate_Loc_Mat = sparse(GFM_Modules.Candidate_Bus, ...
    (1:CONF.GFM_Candidate_Count)',1,CONF.Bn,CONF.GFM_Candidate_Count);
CONF.GFM_Candidate_Module_Mat = sparse(GFM_Modules.Candidate_Index, ...
    (1:GFM_Modules.Count)',1,CONF.GFM_Candidate_Count,GFM_Modules.Count);
CONF.GFM_Candidate_Charge_Efficiency = GFM_Modules.Candidate_Charge_Efficiency;
CONF.GFM_Candidate_Discharge_Efficiency = GFM_Modules.Candidate_Discharge_Efficiency;
CONF.GFM_Candidate_Rated_Duration = GFM_Modules.Candidate_Rated_Duration;
CONF.GFM_Candidate_SOC_Max = GFM_Modules.Candidate_SOC_Max;
CONF.GFM_Candidate_SOC_Initial = GFM_Modules.Candidate_SOC_Initial;
CONF.GFM_Candidate_SOC_Min = GFM_Modules.Candidate_SOC_Min;
CONF.N_GFM_Module_Max = GFM_Modules.N_Module_Max;
CONF.GFM_MaxModulesPerCandidate = GFM_Modules.Max_Modules_Per_Candidate;
CONF.GFM_Module_Sequential = GFM_Modules.Enforce_Sequential_Build;
CONF.GFM_Module_I_Post_Multiplier = GFM_Modules.I_Post_Multiplier;

% 构造Manuscript式(25)的配置方案集合及固定配置-模块状态映射。
GFM_Configuration = build_gfm_configuration_catalog(GFM_Modules);
CONF.GFM_Config_Count = GFM_Configuration.Count;
CONF.GFM_Config_Module_Matrix = GFM_Configuration.Module_Status;
CONF.GFM_Config_Candidate_Matrix = GFM_Configuration.Candidate_Status;
CONF.GFM_Config_A_cne = GFM_Configuration.A_CNE;
CONF.GFM_Config_Module_Count = GFM_Configuration.Module_Count;

% 安全网络统一保留全部同步机、GFM-ES候选节点和已建GFL-WG接入节点。
% Original_To_Reduced以0表示被Kron消元的原节点，其余值为降阶节点索引。
[Safety_Nodes, Original_To_Reduced] = build_safety_network_mapping( ...
    mpc.gen(:,1), GFM_Modules.Candidate_Bus, GFL_Built_Nodes, CONF.Bn);
CONF.Safety_Retained_Nodes = Safety_Nodes;
CONF.Safety_Original_To_Reduced = Original_To_Reduced;
CONF.Safety_Node_Count = numel(Safety_Nodes);
CONF.Safety_GFL_Original_Nodes = GFL_Built_Nodes;
CONF.Safety_GFL_Reduced_Indices = Original_To_Reduced(GFL_Built_Nodes);
CONF.Safety_GFL_Count = numel(GFL_Built_Nodes);

% SCC约束节点必须完整覆盖同步机、GFM-ES候选节点和已建GFL-WG接入节点。
SCC_Required_Nodes = unique([mpc.gen(:,1); GFM_Modules.Candidate_Bus(:); ...
    GFL_Built_Nodes],'sorted');
if ~isequal(Safety_Nodes,SCC_Required_Nodes)
    error('SCC安全网络保留节点未覆盖全部已建及候选有源设备接入节点。');
end
CONF.SCC_Constraint_Original_Nodes = Safety_Nodes;

%% 5. 读取短路电流与短路比安全参数
CONF.I_limit_kA_Node = expand_system_node_parameter( ...
    params.Security.I_limit_kA, CONF.Bn);

CONF.I_limit = CONF.I_limit_kA_Node/CONF.Base_kA;
CONF.SCR_min = params.Security.SCR_min;

CONF.KZ = params.Solver.KZ;
CONF.ERR_TOL = params.Solver.ERR_TOL_Factor*CONF.KZ;
CONF.ZBoundMargin = params.Solver.Z_Bound_Margin;

CONF.Solver = params.Solver;
CONF.solver = params.solver;
CONF.ObjectiveScale = CONF.Solver.Objective_Scale;

%% 6. 读取典型日与时段参数
multi = params.Multiple_Snapshot;
D     = multi.Time.Typical_Day_Count;
T     = multi.Time.Period_Count;

if ~isscalar(D) || ~isfinite(D) || D ~= round(D) || D < 1 || ...
        ~isscalar(T) || ~isfinite(T) || T ~= round(T) || T < 1
    error('TypicalDayCount和PeriodCount必须为正整数。');
end

Day_Weights  = multi.Time.Typical_Day_Weights_Days(:);
Period_Hours = multi.Time.Period_Durations_Hours(:);
if numel(Day_Weights) ~= D || any(~isfinite(Day_Weights)) || ...
        any(Day_Weights <= 0) || abs(sum(Day_Weights)-365) > 1e-8
    error('TypicalDayWeights_Days应包含%d个正数且合计为365天。',D);
end
if numel(Period_Hours) ~= T || any(~isfinite(Period_Hours)) || ...
        any(Period_Hours <= 0) || abs(sum(Period_Hours)-24) > 1e-8 || ...
        any(abs(Period_Hours-24/T) > 1e-10)
    error(['文档模型要求PeriodDurations_Hours包含%d个相等的正数，', ...
        '每个时段为%.12g小时且合计为24小时。'],T,24/T);
end

CONF.TypicalDayCount = D;
CONF.PeriodCount     = T;
CONF.TypicalDayWeights_Days = Day_Weights;
CONF.PeriodDurations_Hours = Period_Hours;
CONF.OperatingWeights_Hours = Day_Weights*Period_Hours.';

%% 7. 读取逐时负荷与GFL-WG场景可用出力
Expected_Profile_Count = CONF.Bn*D*T;
if numel(multi.Profiles.Load_P_MW) ~= Expected_Profile_Count || ...
        numel(multi.Profiles.GFL_Available_P_MW) ~= Expected_Profile_Count
    error('逐时负荷与GFL-WG可用出力均应包含%d个节点-典型日-时段数据。', ...
        Expected_Profile_Count);
end
CONF.P_Load_Profile = reshape( ...
    multi.Profiles.Load_P_MW, CONF.Bn, D, T);
CONF.P_GFL_Available_Profile = reshape( ...
    multi.Profiles.GFL_Available_P_MW, CONF.Bn, D, T);

% 额定功率用于SCC/SCR，逐时可用出力用于弃风上界，实际出力由优化变量给出。
if any(~isfinite(CONF.P_GFL_Available_Profile(:))) || ...
        any(CONF.P_GFL_Available_Profile(:) < 0)
    error('GFL-WG逐时可用出力必须为有限非负数。');
end
Non_GFL_Nodes = CONF.u_GFL < 0.5;
if any(CONF.P_GFL_Available_Profile(Non_GFL_Nodes,:,:) ~= 0,'all')
    error('非GFL-WG接入节点的逐时可用出力必须为零。');
end

% WindScenarios集中配置场景名称、概率和轨迹生成方式。
[Scenario_Names, scenario_probabilities, scenario_scale_factors, ...
    Scenario_Available, Scenario_Mode, Base_Scenario_Index] = ...
    build_wind_scenarios(multi, CONF.P_GFL_Available_Profile, ...
    CONF.u_GFL, D, T, CONF.Bn);

CONF.WindScenarioCount = numel(Scenario_Names);
CONF.WindScenarioNames = Scenario_Names;
CONF.WindScenarioProbabilities = scenario_probabilities;
CONF.WindScenarioScaleFactors = scenario_scale_factors;
CONF.WindScenarioGenerationMode = Scenario_Mode;
CONF.WindScenarioBaseIndex = Base_Scenario_Index;
CONF.P_GFL_Available_Scenarios = Scenario_Available;

% 输入级确定性退化标记：仅保留概率为1且轨迹等于原确定性轨迹的场景时为真。
Profile_Difference = Scenario_Available - ...
    reshape(CONF.P_GFL_Available_Profile, CONF.Bn, D, 1, T);
CONF.DeterministicDegradation = struct();
CONF.DeterministicDegradation.IsSingleProbabilityOneScenario = ...
    CONF.WindScenarioCount == 1 && ...
    max(abs(scenario_probabilities(:)-1)) <= 1e-12;
CONF.DeterministicDegradation.ProfileMatchesOriginal = ...
    CONF.WindScenarioCount == 1 && max(abs(Profile_Difference(:))) <= 1e-10;
CONF.DeterministicDegradation.InputEquivalent = ...
    CONF.DeterministicDegradation.IsSingleProbabilityOneScenario && ...
    CONF.DeterministicDegradation.ProfileMatchesOriginal;

% 同步机最小出力显式由多时段参数文件给定。
CONF.Gen_Pmin = params.UC.Gen_Pmin_MW(:);

%% 8. 读取同步机UC参数
% 爬坡速率单位为MW/h；最小开停机时间采用时段数表示。
UC = params.UC;
CONF.Gen_Ramp_Up_MW_per_Hour = expand_generator_parameter( ...
    UC.Ramp_Up_Rate_MW_per_Hour, CONF.Gn, 'Ramp_Up_Rate_MW_per_Hour');
CONF.Gen_Ramp_Down_MW_per_Hour = expand_generator_parameter( ...
    UC.Ramp_Down_Rate_MW_per_Hour, CONF.Gn, 'Ramp_Down_Rate_MW_per_Hour');
CONF.Gen_Min_Up_Periods = expand_generator_parameter( ...
    UC.Min_Up_Periods, CONF.Gn, 'Min_Up_Periods');
CONF.Gen_Min_Down_Periods = expand_generator_parameter( ...
    UC.Min_Down_Periods, CONF.Gn, 'Min_Down_Periods');
CONF.Gen_Startup_Cost = expand_generator_parameter( ...
    UC.Startup_Cost, CONF.Gn, 'Startup_Cost');
CONF.Gen_Shutdown_Cost = expand_generator_parameter( ...
    UC.Shutdown_Cost, CONF.Gn, 'Shutdown_Cost');

validate_uc_parameters(CONF, T);

%% 9. 计算Manuscript式(24)的GFM-ES模块年固定成本
% 功率与能量单位成本均已包含年化投资和固定运维，此处各计一次。
Power_Cost   = GFM_Modules.Annual_Cost_Power_per_MW;
Energy_Cost  = GFM_Modules.Annual_Cost_Energy_per_MWh;
Rated_Energy = GFM_Modules.Rated_Energy_MWh;

CONF.GFM_Module_Annual_Cost_Power  = Power_Cost.*CONF.GFM_Module_PN(:);
CONF.GFM_Module_Annual_Cost_Energy = Energy_Cost.*Rated_Energy;
CONF.GFM_Module_Cost_Conv    = CONF.GFM_Module_Annual_Cost_Power+CONF.GFM_Module_Annual_Cost_Energy;

%% 10. 按模型主题构造便于审阅的配置结构
CONF = build_public_multiple_snapshot_conf(CONF, params);

%% 11. 整理算例路径
paths = struct();
paths.project_root = Project_Root;
paths.param_file = Parameter_File;
paths.results_dir = fullfile(Project_Root,'results');
ensure_directory(paths.results_dir);

end

function CONF_Public = build_public_multiple_snapshot_conf(CONF, params)
%% 将求解所需的派生量按模型主题组织为公开配置结构。

CONF_Public = struct();

CONF_Public.Network = struct();
CONF_Public.Network.Bn = CONF.Bn;
CONF_Public.Network.Gn = CONF.Gn;
CONF_Public.Network.Ln = CONF.Ln;
CONF_Public.Network.Base_MVA = CONF.Base_MVA;
CONF_Public.Network.Base_kV = CONF.Base_kV;
CONF_Public.Network.Base_kA = CONF.Base_kA;
CONF_Public.Network.Base_O = CONF.Base_O;
CONF_Public.Network.Branch_Scale = params.Network.Branch_Scale;
CONF_Public.Network.Xd_Gen = CONF.Xd_Gen;
CONF_Public.Network.Gen_Cost_Breakpoints = CONF.GenCostBreakpoints;

CONF_Public.GFL_WG = struct();
CONF_Public.GFL_WG.Built_Nodes = params.GFL_WG.Built_Nodes(:);
CONF_Public.GFL_WG.u_GFL = CONF.u_GFL;
CONF_Public.GFL_WG.PN_MW = CONF.PN_GFL;
CONF_Public.GFL_WG.PN_pu = CONF.PN_GFL_pu_Node;
CONF_Public.GFL_WG.Curtailment_Cost_per_MWh = ...
    CONF.GFL_Curtailment_Cost_per_MWh;
CONF_Public.GFL_WG.K_Q = CONF.KQ_GFL_Node;
CONF_Public.GFL_WG.I_N_Rated = CONF.I_GFL_N_Rated_Node;
CONF_Public.GFL_WG.Delta_I_Rated = CONF.Delta_I_GFL_Rated_Node;
CONF_Public.GFL_WG.I_N_pu = CONF.I_GFL_N_pu_Node;
CONF_Public.GFL_WG.Delta_I_pu = CONF.Delta_I_GFL_pu_Node;
CONF_Public.GFL_WG.V_LVRT_On = CONF.V_LVRT_On_Node;
CONF_Public.GFL_WG.V_LVRT_Sat = CONF.V_LVRT_Sat_Node;

GFM_Parameters = params.GFM_Modules;
CONF_Public.GFM_Modules = struct();

% 模块基本信息与接入位置。
CONF_Public.GFM_Modules.Module = struct();
CONF_Public.GFM_Modules.Module.Count = CONF.GFM_Module_Count;
CONF_Public.GFM_Modules.Module.Bus = CONF.GFM_Module_Bus;
CONF_Public.GFM_Modules.Module.Module_Index = CONF.GFM_Module_Order;
CONF_Public.GFM_Modules.Module.PN_MW = CONF.GFM_Module_PN;
CONF_Public.GFM_Modules.Module.PN_pu = CONF.GFM_Module_PN_pu;
CONF_Public.GFM_Modules.Module.Loc_Mat = CONF.GFM_Module_Loc_Mat;

% 模块电气参数与短路电流参数。
CONF_Public.GFM_Modules.Electrical = struct();
CONF_Public.GFM_Modules.Electrical.I_Post_Multiplier = ...
    CONF.GFM_Module_I_Post_Multiplier;
CONF_Public.GFM_Modules.Electrical.I_post = CONF.GFM_Module_I_post;
CONF_Public.GFM_Modules.Electrical.X_GFM_Res = CONF.GFM_Module_X_Res;
CONF_Public.GFM_Modules.Electrical.X_GFM_Vir = CONF.GFM_Module_X_Vir;
CONF_Public.GFM_Modules.Electrical.Delta_Y = CONF.GFM_Module_DeltaY;
CONF_Public.GFM_Modules.Electrical.Delta_Y_abs = CONF.GFM_Module_DeltaY_abs;

% 模块额定能量向量，以及按候选节点排列的储能运行参数向量。
CONF_Public.GFM_Modules.Storage = struct();
CONF_Public.GFM_Modules.Storage.Rated_Energy_MWh = ...
    CONF.GFM_Module_Rated_Energy;
CONF_Public.GFM_Modules.Storage.Charge_Efficiency = ...
    CONF.GFM_Candidate_Charge_Efficiency;
CONF_Public.GFM_Modules.Storage.Discharge_Efficiency = ...
    CONF.GFM_Candidate_Discharge_Efficiency;
CONF_Public.GFM_Modules.Storage.Rated_Duration = ...
    CONF.GFM_Candidate_Rated_Duration;
CONF_Public.GFM_Modules.Storage.SOC_Max = CONF.GFM_Candidate_SOC_Max;
CONF_Public.GFM_Modules.Storage.SOC_Initial = ...
    CONF.GFM_Candidate_SOC_Initial;
CONF_Public.GFM_Modules.Storage.SOC_Min = CONF.GFM_Candidate_SOC_Min;

% 候选节点及候选节点与模块之间的映射关系。
CONF_Public.GFM_Modules.Candidates = struct();
CONF_Public.GFM_Modules.Candidates.Count = CONF.GFM_Candidate_Count;
CONF_Public.GFM_Modules.Candidates.Bus = CONF.GFM_Module_Candidates;
CONF_Public.GFM_Modules.Candidates.Module_Index = CONF.GFM_Module_Candidate_Index;
CONF_Public.GFM_Modules.Candidates.Loc_Mat = CONF.GFM_Candidate_Loc_Mat;
CONF_Public.GFM_Modules.Candidates.Module_Mat = CONF.GFM_Candidate_Module_Mat;

% 年固定成本及模块成本换算结果。
CONF_Public.GFM_Modules.Costs = struct();
CONF_Public.GFM_Modules.Costs.Annual_Cost_Power_per_MW = ...
    GFM_Parameters.Costs.Annual_Cost_Power_per_MW;
CONF_Public.GFM_Modules.Costs.Annual_Cost_Energy_per_MWh = ...
    GFM_Parameters.Costs.Annual_Cost_Energy_per_MWh;
CONF_Public.GFM_Modules.Costs.Annual_Cost_Power = ...
    CONF.GFM_Module_Annual_Cost_Power;
CONF_Public.GFM_Modules.Costs.Annual_Cost_Energy = ...
    CONF.GFM_Module_Annual_Cost_Energy;
CONF_Public.GFM_Modules.Costs.Cost_Conv_GFM = CONF.GFM_Module_Cost_Conv;

% 模块数量限制及固定配置方案目录。
CONF_Public.GFM_Modules.Configurations = struct();
CONF_Public.GFM_Modules.Configurations.Max_Modules_Per_Candidate = ...
    CONF.GFM_MaxModulesPerCandidate;
CONF_Public.GFM_Modules.Configurations.N_Module_Max = CONF.N_GFM_Module_Max;
CONF_Public.GFM_Modules.Configurations.Enforce_Sequential_Build = ...
    CONF.GFM_Module_Sequential;
CONF_Public.GFM_Modules.Configurations.Count = CONF.GFM_Config_Count;
CONF_Public.GFM_Modules.Configurations.Module_Matrix = ...
    CONF.GFM_Config_Module_Matrix;
CONF_Public.GFM_Modules.Configurations.Candidate_Matrix = ...
    CONF.GFM_Config_Candidate_Matrix;
CONF_Public.GFM_Modules.Configurations.A_cne = CONF.GFM_Config_A_cne;
CONF_Public.GFM_Modules.Configurations.Module_Count = ...
    CONF.GFM_Config_Module_Count;

CONF_Public.Security = struct();
% Source、SCR和SCC节点分别列出原节点、降阶节点及数量。
CONF_Public.Security.Source_Nodes_Original = CONF.Safety_Retained_Nodes;
CONF_Public.Security.Source_Nodes_Reduced = ...
    CONF.Safety_Original_To_Reduced(CONF.Safety_Retained_Nodes);
CONF_Public.Security.Source_Nodes_Count = CONF.Safety_Node_Count;
CONF_Public.Security.SCR_Nodes_Original = ...
    CONF.Safety_GFL_Original_Nodes;
CONF_Public.Security.SCR_Nodes_Reduced = ...
    CONF.Safety_GFL_Reduced_Indices;
CONF_Public.Security.SCR_Nodes_Count = CONF.Safety_GFL_Count;
CONF_Public.Security.SCC_Nodes_Original = ...
    CONF.SCC_Constraint_Original_Nodes;
CONF_Public.Security.SCC_Nodes_Reduced = ...
    CONF.Safety_Original_To_Reduced(CONF.SCC_Constraint_Original_Nodes);
CONF_Public.Security.SCC_Nodes_Count = ...
    numel(CONF.SCC_Constraint_Original_Nodes);
CONF_Public.Security.I_limit_kA = CONF.I_limit_kA_Node;
CONF_Public.Security.I_limit_pu = CONF.I_limit;
CONF_Public.Security.SCR_min = CONF.SCR_min;
CONF_Public.Security.Enable_SCC = CONF.Enable_SCC;
CONF_Public.Security.Enable_SCR = CONF.Enable_SCR;
CONF_Public.Security.Require_Source_Online = CONF.Require_Source_Online;

multi = params.Multiple_Snapshot;
CONF_Public.Multiple_Snapshot = struct();
CONF_Public.Multiple_Snapshot.Time = struct();
CONF_Public.Multiple_Snapshot.Time.Typical_Day_Count = CONF.TypicalDayCount;
CONF_Public.Multiple_Snapshot.Time.Period_Count = CONF.PeriodCount;
CONF_Public.Multiple_Snapshot.Time.Typical_Day_Weights_Days = ...
    CONF.TypicalDayWeights_Days;
CONF_Public.Multiple_Snapshot.Time.Period_Durations_Hours = ...
    CONF.PeriodDurations_Hours;
CONF_Public.Multiple_Snapshot.Time.Operating_Weights_Hours = ...
    CONF.OperatingWeights_Hours;
CONF_Public.Multiple_Snapshot.Profiles = struct();
CONF_Public.Multiple_Snapshot.Profiles.Factor = multi.Profiles.Factor;
CONF_Public.Multiple_Snapshot.Profiles.Load_Factor = ...
    multi.Profiles.Load_Factor;
CONF_Public.Multiple_Snapshot.Profiles.Load_P_MW = ...
    multi.Profiles.Load_P_MW;
CONF_Public.Multiple_Snapshot.Profiles.GFL_Available_P_MW = ...
    multi.Profiles.GFL_Available_P_MW;
CONF_Public.Multiple_Snapshot.Profiles.P_Load_Profile = CONF.P_Load_Profile;
CONF_Public.Multiple_Snapshot.Profiles.P_GFL_Available_Profile = ...
    CONF.P_GFL_Available_Profile;
CONF_Public.Multiple_Snapshot.Wind_Scenarios = struct();
CONF_Public.Multiple_Snapshot.Wind_Scenarios.Count = CONF.WindScenarioCount;
CONF_Public.Multiple_Snapshot.Wind_Scenarios.Names = CONF.WindScenarioNames;
CONF_Public.Multiple_Snapshot.Wind_Scenarios.Probabilities = ...
    CONF.WindScenarioProbabilities;
CONF_Public.Multiple_Snapshot.Wind_Scenarios.Scale_Factors = ...
    CONF.WindScenarioScaleFactors;
CONF_Public.Multiple_Snapshot.Wind_Scenarios.Generation_Mode = ...
    CONF.WindScenarioGenerationMode;
CONF_Public.Multiple_Snapshot.Wind_Scenarios.Base_Index = ...
    CONF.WindScenarioBaseIndex;
CONF_Public.Multiple_Snapshot.Wind_Scenarios.P_GFL_Available_Scenarios = ...
    CONF.P_GFL_Available_Scenarios;
CONF_Public.Multiple_Snapshot.Degradation = struct();
CONF_Public.Multiple_Snapshot.Degradation.Deterministic = struct();
CONF_Public.Multiple_Snapshot.Degradation.Deterministic.Is_Single_Probability_One_Scenario = ...
    CONF.DeterministicDegradation.IsSingleProbabilityOneScenario;
CONF_Public.Multiple_Snapshot.Degradation.Deterministic.Profile_Matches_Original = ...
    CONF.DeterministicDegradation.ProfileMatchesOriginal;
CONF_Public.Multiple_Snapshot.Degradation.Deterministic.Input_Equivalent = ...
    CONF.DeterministicDegradation.InputEquivalent;

CONF_Public.UC = struct();
CONF_Public.UC.Gen_Pmin_MW = CONF.Gen_Pmin;
CONF_Public.UC.Ramp_Up_Rate_MW_per_Hour = CONF.Gen_Ramp_Up_MW_per_Hour;
CONF_Public.UC.Ramp_Down_Rate_MW_per_Hour = CONF.Gen_Ramp_Down_MW_per_Hour;
CONF_Public.UC.Min_Up_Periods = CONF.Gen_Min_Up_Periods;
CONF_Public.UC.Min_Down_Periods = CONF.Gen_Min_Down_Periods;
CONF_Public.UC.Startup_Cost = CONF.Gen_Startup_Cost;
CONF_Public.UC.Shutdown_Cost = CONF.Gen_Shutdown_Cost;

CONF_Public.Solver = build_public_solver_conf( ...
    CONF.Solver, CONF.ObjectiveScale, CONF.KZ, CONF.ERR_TOL, ...
    CONF.ZBoundMargin);
CONF_Public.solver = CONF.solver;

end

function Solver_Public = build_public_solver_conf( ...
    solver, Objective_Scale, kz, ERR_TOL, Z_Bound_Margin)
%% 补充求解器派生参数。

Solver_Public = solver;

Solver_Public.Objective_Scale = Objective_Scale;
Solver_Public.KZ = kz;
Solver_Public.ERR_TOL = ERR_TOL;
Solver_Public.Z_Bound_Margin = Z_Bound_Margin;

end

function values = expand_generator_parameter(values, n_Generators, Field_Name)
%% 将同步机UC参数扩展为与同步机数量一致的列向量。

values = values(:);
if isscalar(values)
    values = repmat(values,n_Generators,1);
elseif numel(values) ~= n_Generators
    error('%s的长度应为1或同步机数量%d。',Field_Name,n_Generators);
end

end

function validate_uc_parameters(CONF, Period_Count)
%% 校验同步机UC参数是否满足文档模型的取值范围。

Ramp_Values = [CONF.Gen_Ramp_Up_MW_per_Hour; ...
    CONF.Gen_Ramp_Down_MW_per_Hour];
Cost_Values = [CONF.Gen_Startup_Cost; CONF.Gen_Shutdown_Cost];
Min_Periods = [CONF.Gen_Min_Up_Periods; CONF.Gen_Min_Down_Periods];

if any(~isfinite(Ramp_Values)) || any(Ramp_Values < 0)
    error('同步机上、下爬坡速率必须为有限非负数。');
end
if any(~isfinite(Cost_Values)) || any(Cost_Values < 0)
    error('同步机单次启动、停机成本必须为有限非负数。');
end
if any(~isfinite(Min_Periods)) || any(Min_Periods ~= round(Min_Periods)) || ...
        any(Min_Periods < 1) || any(Min_Periods > Period_Count)
    error('同步机最小开、停机时段数必须为1至PeriodCount之间的整数。');
end

end

function GFM_Modules = build_gfm_module_params(params, CONF)
%% 读取模块化GFM-ES参数表。
Module_Parameters = params.GFM_Modules;
MODULE = Module_Parameters.Module;
ELECTRICAL = Module_Parameters.Electrical;
STORAGE = Module_Parameters.Storage;
COSTS = Module_Parameters.Costs;
CONFIGS = Module_Parameters.Configurations;
bus = MODULE.Bus(:);

n_Modules = numel(bus);
order = expand_module_parameter(MODULE.Module_Index, n_Modules, 'Module_Index');
PN_MW = expand_module_parameter(MODULE.PN_MW, n_Modules, 'PN_MW');
x_Res = expand_module_parameter(ELECTRICAL.X_GFM_Res, n_Modules, 'X_GFM_Res');
I_Post_Multiplier = expand_module_parameter( ...
    ELECTRICAL.I_Post_Multiplier, n_Modules, 'I_Post_Multiplier');
x_Vir = expand_module_parameter(ELECTRICAL.X_GFM_Vir, n_Modules, 'X_GFM_Vir');
Rated_Energy = expand_module_parameter( ...
    STORAGE.Rated_Energy_MWh, n_Modules, 'Rated_Energy_MWh');
Power_Cost = expand_module_parameter( ...
    COSTS.Annual_Cost_Power_per_MW, n_Modules, ...
    'Annual_Cost_Power_per_MW');
Energy_Cost = expand_module_parameter( ...
    COSTS.Annual_Cost_Energy_per_MWh, n_Modules, ...
    'Annual_Cost_Energy_per_MWh');
Charge_Efficiency = expand_module_parameter( ...
    STORAGE.Charge_Efficiency, n_Modules, 'Charge_Efficiency');
Discharge_Efficiency = expand_module_parameter( ...
    STORAGE.Discharge_Efficiency, n_Modules, 'Discharge_Efficiency');
SOC_Max = expand_module_parameter(STORAGE.SOC_Max, n_Modules, 'SOC_Max');
SOC_Initial = expand_module_parameter( ...
    STORAGE.SOC_Initial, n_Modules, 'SOC_Initial');
SOC_Min = expand_module_parameter(STORAGE.SOC_Min, n_Modules, 'SOC_Min');

validate_gfm_storage_parameters(PN_MW, Rated_Energy, Charge_Efficiency, ...
    Discharge_Efficiency, SOC_Min, SOC_Initial, SOC_Max);
if any(~isfinite(x_Res)) || any(x_Res <= 0) || ...
        any(~isfinite(x_Vir)) || any(x_Vir < 0) || ...
        any(x_Res+x_Vir <= 0)
    error('GFM-ES运行电抗必须为正，虚拟电抗必须为非负。');
end
I_Post_From_Impedance = 1./(x_Res+x_Vir);
I_Post_From_Multiplier = I_Post_Multiplier.*PN_MW/CONF.Base_MVA;
I_Post_Tolerance = 1e-9*max(1,max(abs(I_Post_From_Multiplier)));
if any(~isfinite(I_Post_Multiplier)) || any(I_Post_Multiplier <= 0) || ...
        any(abs(I_Post_From_Impedance-I_Post_From_Multiplier) > I_Post_Tolerance)
    error(['GFM-ES故障后电流倍数与运行/虚拟电抗不一致：须满足', ...
        '1/(X_GFM_Res+X_GFM_Vir)=I_Post_Multiplier*PN_MW/Base_MVA。']);
end

Candidate_Bus = Module_Parameters.Candidates.Bus(:);
[~, Candidate_Index] = ismember(bus,Candidate_Bus);
if any(Candidate_Index == 0)
    error('GFM_Modules.Module.Bus必须全部属于GFM_Modules.Candidates.Bus。');
end
Candidate_Charge_Efficiency = collapse_candidate_parameter( ...
    Charge_Efficiency,Candidate_Index,numel(Candidate_Bus),'Charge_Efficiency');
Candidate_Discharge_Efficiency = collapse_candidate_parameter( ...
    Discharge_Efficiency,Candidate_Index,numel(Candidate_Bus),'Discharge_Efficiency');
Candidate_Rated_Duration = collapse_candidate_parameter( ...
    Rated_Energy./PN_MW,Candidate_Index,numel(Candidate_Bus),'Rated_Duration_Hours');
Candidate_SOC_Max = collapse_candidate_parameter( ...
    SOC_Max,Candidate_Index,numel(Candidate_Bus),'SOC_Max');
Candidate_SOC_Initial = collapse_candidate_parameter( ...
    SOC_Initial,Candidate_Index,numel(Candidate_Bus),'SOC_Initial');
Candidate_SOC_Min = collapse_candidate_parameter( ...
    SOC_Min,Candidate_Index,numel(Candidate_Bus),'SOC_Min');

GFM_Modules = struct();
GFM_Modules.Count = n_Modules;
GFM_Modules.Bus = bus;
GFM_Modules.Order = order;
GFM_Modules.PN_MW = PN_MW;
GFM_Modules.Rated_Energy_MWh = Rated_Energy;
GFM_Modules.Annual_Cost_Power_per_MW = Power_Cost;
GFM_Modules.Annual_Cost_Energy_per_MWh = Energy_Cost;
GFM_Modules.X_GFM_Res = x_Res;
GFM_Modules.I_Post_Multiplier = I_Post_Multiplier;
GFM_Modules.I_Post = I_Post_Multiplier.*PN_MW/CONF.Base_MVA;
GFM_Modules.X_GFM_Vir = x_Vir;
GFM_Modules.Delta_B = 1./x_Res-1./(x_Res+x_Vir);
GFM_Modules.Delta_Y = 1i*GFM_Modules.Delta_B;
GFM_Modules.Candidate_Bus = Candidate_Bus;
GFM_Modules.Candidate_Index = Candidate_Index;
GFM_Modules.Candidate_Charge_Efficiency = Candidate_Charge_Efficiency;
GFM_Modules.Candidate_Discharge_Efficiency = Candidate_Discharge_Efficiency;
GFM_Modules.Candidate_Rated_Duration = Candidate_Rated_Duration;
GFM_Modules.Candidate_SOC_Max = Candidate_SOC_Max;
GFM_Modules.Candidate_SOC_Initial = Candidate_SOC_Initial;
GFM_Modules.Candidate_SOC_Min = Candidate_SOC_Min;
GFM_Modules.N_Module_Max = CONFIGS.N_Module_Max;
GFM_Modules.Max_Modules_Per_Candidate = CONFIGS.Max_Modules_Per_Candidate;
GFM_Modules.Enforce_Sequential_Build = logical(CONFIGS.Enforce_Sequential_Build);

end

function values = expand_module_parameter(values, n_Modules, Field_Name)
%% 将模块参数扩展为与模块表等长的列向量。

values = values(:);
if isscalar(values)
    values = repmat(values,n_Modules,1);
elseif numel(values) ~= n_Modules
    error('GFM_Modules.%s的长度应为1或模块数量%d。',Field_Name,n_Modules);
end

end

function validate_gfm_storage_parameters(PN_MW, Rated_Energy, Charge_Efficiency, ...
    Discharge_Efficiency, SOC_Min, SOC_Initial, SOC_Max)
%% 校验GFM-ES储能参数是否满足文档模型的物理取值范围。

if any(PN_MW <= 0)
    error('GFM-ES模块额定功率必须为正数。');
end
if any(Rated_Energy <= 0)
    error('GFM-ES模块额定储存能量必须为正数。');
end
if any(Charge_Efficiency <= 0 | Charge_Efficiency > 1) || ...
        any(Discharge_Efficiency <= 0 | Discharge_Efficiency > 1)
    error('GFM-ES充电效率和放电效率必须位于区间(0,1]。');
end
if any(SOC_Min < 0 | SOC_Max > 1 | SOC_Min > SOC_Initial | ...
        SOC_Initial > SOC_Max)
    error('GFM-ES SOC参数必须满足0<=SOC_Min<=SOC_Initial<=SOC_Max<=1。');
end

end

function Candidate_Values = collapse_candidate_parameter(Module_Values, ...
    Candidate_Index, Candidate_Count, Field_Name)
%% 将模块参数整理为候选节点参数，并校验同一节点内模块参数相同。

Candidate_Values = zeros(Candidate_Count,1);
for k = 1:Candidate_Count
    Values_k = Module_Values(Candidate_Index == k);
    if any(abs(Values_k-Values_k(1)) > 1e-12)
        error('同一候选节点内各模块的GFM_Modules.%s必须相同。',Field_Name);
    end
    Candidate_Values(k) = Values_k(1);
end

end

function Node_Values = expand_built_node_parameter(values, Built_Nodes, n_Nodes)
%% 将已投建节点参数扩展为完整节点向量。
values = values(:);
Node_Values = zeros(n_Nodes,1);

if numel(values) == n_Nodes
    Node_Values = values;
else
    Node_Values(Built_Nodes) = values;
end

end

function Node_Values = expand_system_node_parameter(values, n_Nodes)
%% 将系统级参数扩展为完整节点向量。
values = values(:);
if isscalar(values)
    Node_Values = repmat(values,n_Nodes,1);
else
    Node_Values = values;
end

end

function [Retained_Nodes, Original_To_Reduced] = ...
build_safety_network_mapping(Generator_Nodes, GFM_Nodes, GFL_Nodes, n_Nodes)
%% 构造安全网络统一保留节点集合及原节点到降阶节点的映射。

All_Nodes = [Generator_Nodes(:); GFM_Nodes(:); GFL_Nodes(:)];
if any(~isfinite(All_Nodes)) || any(All_Nodes ~= round(All_Nodes)) || ...
        any(All_Nodes < 1) || any(All_Nodes > n_Nodes)
    error('安全网络有源设备接入节点必须为1至节点总数%d之间的整数。',n_Nodes);
end
if numel(unique(GFL_Nodes(:))) ~= numel(GFL_Nodes)
    error('GFL_Built_Nodes不应包含重复节点。');
end

Retained_Nodes = unique(All_Nodes,'sorted');
Original_To_Reduced = zeros(n_Nodes,1);
Original_To_Reduced(Retained_Nodes) = (1:numel(Retained_Nodes)).';

end

function validate_gfl_lvrt_parameters(CONF, GFL_Nodes)
%% 校验额定功率基准下的三段式LVRT参数。
GFL_Nodes = GFL_Nodes(:);
KQ = CONF.KQ_GFL_Node(GFL_Nodes);
I_N = CONF.I_GFL_N_Rated_Node(GFL_Nodes);
V_On = CONF.V_LVRT_On_Node(GFL_Nodes);
V_Sat = CONF.V_LVRT_Sat_Node(GFL_Nodes);
Delta_I = CONF.Delta_I_GFL_Rated_Node(GFL_Nodes);

if any(~isfinite(KQ)) || any(KQ <= 0) || ...
        any(~isfinite(I_N)) || any(I_N <= 0)
    error('GFL-WG的K_Q与I_GFL_N必须为有限正数。');
end
if any(~isfinite(V_On)) || any(~isfinite(V_Sat)) || ...
        any(V_Sat < 0 | V_Sat > V_On | V_On > 1)
    error('GFL-WG的LVRT阈值必须满足0<=V_sat<=V_on<=1。');
end
if any(~isfinite(Delta_I)) || any(Delta_I < 0) || ...
        any(Delta_I > KQ.*I_N.*V_On + 1e-10)
    error('GFL-WG的Delta_I_GFL不满足LVRT线性段可行上界。');
end
Expected_V_Sat = V_On - Delta_I./(KQ.*I_N);
if any(abs(V_Sat-Expected_V_Sat) > 1e-9)
    error(['GFL-WG的V_LVRT_sat必须等于', ...
        'V_LVRT_on-Delta_I_GFL/(K_Q*I_GFL_N)。']);
end
end

function Value = read_optional_logical_scalar(Input, Field_Name, Default_Value)
%% 读取可选逻辑开关，并拒绝数值0/1等非逻辑替代值。

if ~isfield(Input,Field_Name)
    Value = Default_Value;
    return;
end
Value = Input.(Field_Name);
if ~islogical(Value) || ~isscalar(Value)
    error('MultipleSnapshotConfig:InvalidLogicalSwitch', ...
        'Security.%s必须为标量逻辑值true或false。',Field_Name);
end

end

function [names, probabilities, Scale_Factors, Available_Scenarios, ...
    Generation_Mode, Base_Index] = build_wind_scenarios( ...
    multi, Base_Available, u_GFL, Day_Count, Period_Count, Node_Count)
%% 集中解析风电场景，并构造[节点,典型日,场景,时段]可用出力。

scenario = multi.Wind_Scenarios;
Probability_Input = scenario.Probabilities;
Scenario_Count = scenario.Count;
if ~isscalar(Scenario_Count) || ~isfinite(Scenario_Count) || ...
        Scenario_Count ~= round(Scenario_Count) || Scenario_Count < 1
    error('MultipleSnapshot.WindScenarios.Count必须为正整数。');
end

Names_Input = scenario.Names;
names = cellstr(string(Names_Input(:)));
names = names(:).';
if numel(names) ~= Scenario_Count || any(cellfun(@isempty,names)) || ...
        numel(unique(lower(string(names)))) ~= Scenario_Count
    error('WindScenarios.Names应包含%d个非空且互不重复的场景名称。',Scenario_Count);
end

probabilities = expand_day_scenario_parameter( ...
    Probability_Input, Day_Count, Scenario_Count, 'Probabilities');
if any(~isfinite(probabilities(:))) || any(probabilities(:) <= 0) || ...
        any(abs(sum(probabilities,2)-1) > 1e-12)
    error('各典型日的WindScenarios.Probabilities必须为正数且逐日合计为1。');
end

Generation_Mode = char(string(scenario.Generation_Mode));
switch lower(Generation_Mode)
    case 'scale_base_profiles'
        Scale_Factors = expand_day_scenario_parameter( ...
            scenario.Scale_Factors, ...
            Day_Count, Scenario_Count, 'Scale_Factors');
        if any(~isfinite(Scale_Factors(:))) || any(Scale_Factors(:) < 0)
            error('WindScenarios.ScaleFactors必须为有限非负数。');
        end
        Available_Scenarios = ...
            reshape(Base_Available,Node_Count,Day_Count,1,Period_Count).* ...
            reshape(Scale_Factors,1,Day_Count,Scenario_Count,1);
    case 'explicit'
        Explicit_Available = scenario.P_GFL_Available_Scenarios;
        Expected_Count = Node_Count*Day_Count*Scenario_Count*Period_Count;
        if numel(Explicit_Available) ~= Expected_Count
            error(['WindScenarios.GFL_Available_P_MW在explicit模式下应包含', ...
                '%d个节点-典型日-场景-时段数据。'],Expected_Count);
        end
        Available_Scenarios = reshape(Explicit_Available, ...
            Node_Count,Day_Count,Scenario_Count,Period_Count);
        Scale_Factors = NaN(Day_Count,Scenario_Count);
    otherwise
        error('不支持的WindScenarios.GenerationMode：%s。',Generation_Mode);
end

if any(~isfinite(Available_Scenarios(:))) || any(Available_Scenarios(:) < 0)
    error('各场景GFL-WG可用出力必须为有限非负数。');
end
Non_GFL_Nodes = u_GFL < 0.5;
if any(Available_Scenarios(Non_GFL_Nodes,:,:,:) ~= 0,'all')
    error('非GFL-WG接入节点的各场景可用出力必须为零。');
end

Base_Index = find(strcmpi(names,'base'),1);
if isempty(Base_Index) && all(isfinite(Scale_Factors(:)))
    Unit_Scale = find(all(abs(Scale_Factors-1) <= 1e-12,1));
    if isscalar(Unit_Scale)
        Base_Index = Unit_Scale;
    end
end
if isempty(Base_Index)
    Base_Index = NaN;
end

function values = expand_day_scenario_parameter(values, Day_Count, ...
    Scenario_Count, Field_Name)
%% 将场景参数扩展为[典型日,场景]矩阵。

if isvector(values) && numel(values) == Scenario_Count
    values = repmat(reshape(values,1,Scenario_Count),Day_Count,1);
elseif numel(values) == Day_Count*Scenario_Count
    values = reshape(values,Day_Count,Scenario_Count);
else
    error('WindScenarios.%s的维度应为1×%d或%d×%d。', ...
        Field_Name,Scenario_Count,Day_Count,Scenario_Count);
end

end

end
