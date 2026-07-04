function [mpc, CONF, paths] = load_multiple_snapshot_case(project_root, param_file)
%% 本函数功能是加载场景随机多时段算例并构造优化配置参数。
% 本函数独立读取静态网络、设备、安全约束、典型日和风电场景参数。

params = read_json_file(param_file);

%% 1. 构造MATPOWER算例
mpc = params.mpc;

% 按参数文件给定比例修正线路电阻、电抗和对地电纳。
mpc.branch(:,3) = params.BranchScale.r*mpc.branch(:,3);
mpc.branch(:,4) = params.BranchScale.x*mpc.branch(:,4);
mpc.branch(:,5) = params.BranchScale.b*mpc.branch(:,5);

% 按给定负载率更新同步机成本函数的常数项。
mpc.gencost(:,7) = mpc.gencost(:,5).*((params.GenCostLoading*mpc.gen(:,9)).^2) + ...
                   mpc.gencost(:,6).*(params.GenCostLoading*mpc.gen(:,9));

%% 2. 构造基础优化配置
CONF = struct();

CONF.Bn = size(mpc.bus,1);
CONF.Gn = size(mpc.gen,1);
CONF.Ln = size(mpc.branch,1);

CONF.Base_MVA = params.base_MVA;
CONF.Base_kV  = params.base_kV;
CONF.Base_kA  = params.base_kA;
CONF.Base_O   = params.base_O;

CONF.Xd_Gen = params.Xd_Gen;
CONF.GenCostBreakpoints = params.GenCostBreakpoints(:)';

%% 3. 读取GFL-WG参数
GFL_built_nodes = params.GFL_Built_Nodes(:);
CONF.u_GFL = zeros(CONF.Bn,1);
CONF.u_GFL(GFL_built_nodes) = 1;

GFL_params = params.GFL_WG;
% 单位弃风惩罚成本用于将逐时弃风功率折算为全年弃风成本。
CONF.GFL_Curtailment_Cost_per_MWh = GFL_params.Curtailment_Cost_per_MWh;
CONF.PN_GFL_Node = expand_built_node_parameter( ...
    GFL_params.PN_MW, GFL_built_nodes, CONF.Bn);
if any(~isfinite(CONF.PN_GFL_Node(GFL_built_nodes))) || ...
        any(CONF.PN_GFL_Node(GFL_built_nodes) <= 0)
    error('已建GFL-WG场站额定功率必须为有限正数。');
end
CONF.PN_GFL = max(CONF.PN_GFL_Node(CONF.u_GFL > 0.5));
CONF.PN_GFL_pu_Node = CONF.PN_GFL_Node/CONF.Base_MVA;

GFL_i_post_multiplier = expand_built_node_parameter( ...
    GFL_params.I_Post_Multiplier, GFL_built_nodes, CONF.Bn);
CONF.I_post_GFL_Node = GFL_i_post_multiplier.*CONF.PN_GFL_Node/CONF.Base_MVA; % 装备级标幺值->系统级标幺值。
CONF.I_post = max(CONF.I_post_GFL_Node);

CONF.Require_Source_Online = logical(params.Require_Source_Online);

%% 4. 读取模块化GFM-ES参数
GFMModules = build_gfm_module_params(params, CONF);
CONF.GFM_Module_Count = GFMModules.Count;
CONF.GFM_Module_Bus = GFMModules.Bus;
CONF.GFM_Module_Order = GFMModules.Order;
CONF.GFM_Module_PN = GFMModules.PN_MW;
CONF.GFM_Module_PN_pu = GFMModules.PN_MW/CONF.Base_MVA;
CONF.GFM_Module_Cost_Conv = GFMModules.Cost_Conv_GFM;
CONF.GFM_Module_Rated_Energy = GFMModules.Rated_Energy_MWh;
CONF.GFM_Module_X_res = GFMModules.X_GFM_res;
CONF.GFM_Module_I_post = GFMModules.I_post;
CONF.GFM_Module_X_vir = GFMModules.X_GFM_vir;
CONF.GFM_Module_DeltaY = GFMModules.DeltaY;
CONF.GFM_Module_DeltaY_abs = abs(GFMModules.DeltaY);
CONF.GFM_Module_Loc_Mat = sparse(GFMModules.Bus,(1:GFMModules.Count)', ...
    1,CONF.Bn,GFMModules.Count);
CONF.GFM_Module_Candidates = GFMModules.CandidateBus(:)';
CONF.GFM_Module_Candidate_Index = GFMModules.CandidateIndex;
CONF.GFM_Candidate_Count = numel(GFMModules.CandidateBus);
CONF.GFM_Candidate_Loc_Mat = sparse(GFMModules.CandidateBus, ...
    (1:CONF.GFM_Candidate_Count)',1,CONF.Bn,CONF.GFM_Candidate_Count);
CONF.GFM_Candidate_Module_Mat = sparse(GFMModules.CandidateIndex, ...
    (1:GFMModules.Count)',1,CONF.GFM_Candidate_Count,GFMModules.Count);
CONF.GFM_Candidate_Charge_Efficiency = GFMModules.CandidateChargeEfficiency;
CONF.GFM_Candidate_Discharge_Efficiency = GFMModules.CandidateDischargeEfficiency;
CONF.GFM_Candidate_Rated_Duration = GFMModules.CandidateRatedDuration;
CONF.GFM_Candidate_SOC_Max = GFMModules.CandidateSOCMax;
CONF.GFM_Candidate_SOC_Initial = GFMModules.CandidateSOCInitial;
CONF.GFM_Candidate_SOC_Min = GFMModules.CandidateSOCMin;
CONF.N_GFM_Module_Max = GFMModules.N_Module_Max;
CONF.GFM_MaxModulesPerCandidate = GFMModules.MaxModulesPerCandidate;
CONF.GFM_Module_Sequential = GFMModules.EnforceSequentialBuild;
CONF.GFM_Module_I_Post_Multiplier = GFMModules.I_Post_Multiplier;

% 安全网络统一保留全部同步机、GFM-ES候选节点和已建GFL-WG接入节点。
% Original_To_Reduced以0表示被Kron消元的原节点，其余值为降阶节点索引。
[safety_nodes, original_to_reduced] = build_safety_network_mapping( ...
    mpc.gen(:,1), GFMModules.CandidateBus, GFL_built_nodes, CONF.Bn);
CONF.Safety_Retained_Nodes = safety_nodes;
CONF.Safety_Original_To_Reduced = original_to_reduced;
CONF.Safety_Node_Count = numel(safety_nodes);
CONF.Safety_GFL_Original_Nodes = GFL_built_nodes;
CONF.Safety_GFL_Reduced_Indices = original_to_reduced(GFL_built_nodes);
CONF.Safety_GFL_Count = numel(GFL_built_nodes);

% SCC约束节点必须完整覆盖同步机、GFM-ES候选节点和已建GFL-WG接入节点。
scc_required_nodes = unique([mpc.gen(:,1); GFMModules.CandidateBus(:); ...
    GFL_built_nodes],'sorted');
if ~isequal(safety_nodes,scc_required_nodes)
    error('SCC安全网络保留节点未覆盖全部已建及候选有源设备接入节点。');
end
CONF.SCC_Constraint_Original_Nodes = safety_nodes;

%% 5. 读取短路电流与短路比安全参数
CONF.I_limit_kA_Node = expand_system_node_parameter(params.I_limit_kA, CONF.Bn);

CONF.I_limit = CONF.I_limit_kA_Node/CONF.Base_kA;
CONF.SCR_min = params.SCR_min;

CONF.KZ = params.KZ;
CONF.ERR_TOL = params.ERR_TOL_FACTOR*CONF.KZ;
CONF.ZBoundMargin = params.ZBoundMargin;

if isfield(params, 'Solver')
    CONF.Solver = params.Solver;
else
    CONF.Solver = struct();
end
CONF.ObjectiveScale = get_struct_field(CONF.Solver, 'ObjectiveScale', 1);
CONF.UseLatestMIPStart = logical(get_struct_field( ...
    CONF.Solver, 'UseLatestMIPStart', false));

%% 6. 读取典型日与时段参数
multi = params.MultipleSnapshot;
D     = multi.TypicalDayCount;
T     = multi.PeriodCount;

if ~isscalar(D) || ~isfinite(D) || D ~= round(D) || D < 1 || ...
        ~isscalar(T) || ~isfinite(T) || T ~= round(T) || T < 1
    error('TypicalDayCount和PeriodCount必须为正整数。');
end

day_weights  = multi.TypicalDayWeights_Days(:);
period_hours = multi.PeriodDurations_Hours(:);
if numel(day_weights) ~= D || any(~isfinite(day_weights)) || ...
        any(day_weights <= 0) || abs(sum(day_weights)-365) > 1e-8
    error('TypicalDayWeights_Days应包含%d个正数且合计为365天。',D);
end
if numel(period_hours) ~= T || any(~isfinite(period_hours)) || ...
        any(period_hours <= 0) || abs(sum(period_hours)-24) > 1e-8
    error('PeriodDurations_Hours应包含%d个正数且合计为24小时。',T);
end

CONF.TypicalDayCount = D;
CONF.PeriodCount     = T;
CONF.TypicalDayWeights_Days = day_weights;
CONF.PeriodDurations_Hours = period_hours;
CONF.OperatingWeights_Hours = day_weights*period_hours.';

%% 7. 读取逐时负荷与GFL-WG场景可用出力
expected_profile_count = CONF.Bn*D*T;
if numel(multi.Load_P_MW) ~= expected_profile_count || ...
        numel(multi.GFL_Available_P_MW) ~= expected_profile_count
    error('逐时负荷与GFL-WG可用出力均应包含%d个节点-典型日-时段数据。', ...
        expected_profile_count);
end
CONF.P_Load_Profile = reshape(multi.Load_P_MW, CONF.Bn, D, T);
CONF.P_GFL_Available_Profile = reshape(multi.GFL_Available_P_MW, CONF.Bn, D, T);

% 额定功率用于SCC/SCR，逐时可用出力用于弃风上界，实际出力由优化变量给出。
if any(~isfinite(CONF.P_GFL_Available_Profile(:))) || ...
        any(CONF.P_GFL_Available_Profile(:) < 0)
    error('GFL-WG逐时可用出力必须为有限非负数。');
end
non_gfl_nodes = CONF.u_GFL < 0.5;
if any(CONF.P_GFL_Available_Profile(non_gfl_nodes,:,:) ~= 0,'all')
    error('非GFL-WG接入节点的逐时可用出力必须为零。');
end

% WindScenarios集中配置场景名称、概率和轨迹生成方式。未配置时退化为
% 单一基准场景，以兼容原确定性参数文件。
[scenario_names, scenario_probabilities, scenario_scale_factors, ...
    scenario_available, scenario_mode, base_scenario_index] = ...
    build_wind_scenarios(multi, CONF.P_GFL_Available_Profile, ...
    CONF.u_GFL, D, T, CONF.Bn);

CONF.WindScenarioCount = numel(scenario_names);
CONF.WindScenarioNames = scenario_names;
CONF.WindScenarioProbabilities = scenario_probabilities;
CONF.WindScenarioScaleFactors = scenario_scale_factors;
CONF.WindScenarioGenerationMode = scenario_mode;
CONF.WindScenarioBaseIndex = base_scenario_index;
CONF.P_GFL_Available_Scenarios = scenario_available;

% 输入级确定性退化标记：仅保留概率为1且轨迹等于原确定性轨迹的场景时为真。
profile_difference = scenario_available - ...
    reshape(CONF.P_GFL_Available_Profile, CONF.Bn, D, 1, T);
CONF.DeterministicDegradation = struct();
CONF.DeterministicDegradation.IsSingleProbabilityOneScenario = ...
    CONF.WindScenarioCount == 1 && ...
    max(abs(scenario_probabilities(:)-1)) <= 1e-12;
CONF.DeterministicDegradation.ProfileMatchesOriginal = ...
    CONF.WindScenarioCount == 1 && max(abs(profile_difference(:))) <= 1e-10;
CONF.DeterministicDegradation.InputEquivalent = ...
    CONF.DeterministicDegradation.IsSingleProbabilityOneScenario && ...
    CONF.DeterministicDegradation.ProfileMatchesOriginal;

% 同步机最小出力显式由多时段参数文件给定。
CONF.Gen_Pmin = params.Gen_Pmin_MW(:);

%% 8. 读取同步机UC参数
% 爬坡速率单位为MW/h；最小开停机时间采用时段数表示。
UC = params.UC;
CONF.Gen_Ramp_Up_MW_per_Hour = expand_generator_parameter( ...
    UC.RampUp_Rate_MW_per_Hour, CONF.Gn, 'RampUp_Rate_MW_per_Hour');
CONF.Gen_Ramp_Down_MW_per_Hour = expand_generator_parameter( ...
    UC.RampDown_Rate_MW_per_Hour, CONF.Gn, 'RampDown_Rate_MW_per_Hour');
CONF.Gen_Min_Up_Periods = expand_generator_parameter( ...
    UC.MinUp_Periods, CONF.Gn, 'MinUp_Periods');
CONF.Gen_Min_Down_Periods = expand_generator_parameter( ...
    UC.MinDown_Periods, CONF.Gn, 'MinDown_Periods');
CONF.Gen_Startup_Cost = expand_generator_parameter( ...
    UC.Startup_Cost, CONF.Gn, 'Startup_Cost');
CONF.Gen_Shutdown_Cost = expand_generator_parameter( ...
    UC.Shutdown_Cost, CONF.Gn, 'Shutdown_Cost');

validate_uc_parameters(CONF, T);

%% 9. 计算文档口径下的GFM-ES模块年化投建成本
power_cost   = GFMModules.Annual_Cost_Power_per_MW;
energy_cost  = GFMModules.Annual_Cost_Energy_per_MWh;
rated_energy = GFMModules.Rated_Energy_MWh;

CONF.GFM_Module_Annual_Cost_Power  = power_cost.*CONF.GFM_Module_PN(:);
CONF.GFM_Module_Annual_Cost_Energy = energy_cost.*rated_energy;
CONF.GFM_Module_Rated_Energy = rated_energy;
CONF.GFM_Module_Cost_Conv    = CONF.GFM_Module_Annual_Cost_Power+CONF.GFM_Module_Annual_Cost_Energy;

%% 10. 整理算例路径
paths = struct();
paths.project_root = project_root;
paths.param_file = param_file;
paths.results_dir = fullfile(project_root,'results');
ensure_directory(paths.results_dir);

end

function values = expand_generator_parameter(values, n_generators, field_name)
%% 将同步机UC参数扩展为与同步机数量一致的列向量。

values = values(:);
if isscalar(values)
    values = repmat(values,n_generators,1);
elseif numel(values) ~= n_generators
    error('UC.%s的长度应为1或同步机数量%d。',field_name,n_generators);
end

end

function validate_uc_parameters(CONF, period_count)
%% 校验同步机UC参数是否满足文档模型的取值范围。

ramp_values = [CONF.Gen_Ramp_Up_MW_per_Hour; ...
    CONF.Gen_Ramp_Down_MW_per_Hour];
cost_values = [CONF.Gen_Startup_Cost; CONF.Gen_Shutdown_Cost];
min_periods = [CONF.Gen_Min_Up_Periods; CONF.Gen_Min_Down_Periods];

if any(~isfinite(ramp_values)) || any(ramp_values < 0)
    error('同步机上、下爬坡速率必须为有限非负数。');
end
if any(~isfinite(cost_values)) || any(cost_values < 0)
    error('同步机单次启动、停机成本必须为有限非负数。');
end
if any(~isfinite(min_periods)) || any(min_periods ~= round(min_periods)) || ...
        any(min_periods < 1) || any(min_periods > period_count)
    error('同步机最小开、停机时段数必须为1至PeriodCount之间的整数。');
end

end

function GFMModules = build_gfm_module_params(params, CONF)
%% 读取模块化GFM-ES参数表。
module_params = params.GFM_Modules;
bus = module_params.Bus(:);

n_modules = numel(bus);
order = expand_module_parameter(module_params.ModuleIndex, n_modules, 'ModuleIndex');
pn_mw = expand_module_parameter(module_params.PN_MW, n_modules, 'PN_MW');
cost_conv = expand_module_parameter(module_params.Cost_Conv_GFM, n_modules, 'Cost_Conv_GFM');
x_res = expand_module_parameter(module_params.X_GFM_res, n_modules, 'X_GFM_res');
i_post_multiplier = expand_module_parameter( ...
    module_params.I_Post_Multiplier, n_modules, 'I_Post_Multiplier');
x_vir = expand_module_parameter(module_params.X_GFM_vir, n_modules, 'X_GFM_vir');
rated_energy = expand_module_parameter( ...
    module_params.Rated_Energy_MWh, n_modules, 'Rated_Energy_MWh');
power_cost = expand_module_parameter( ...
    module_params.Annual_Cost_Power_per_MW, n_modules, ...
    'Annual_Cost_Power_per_MW');
energy_cost = expand_module_parameter( ...
    module_params.Annual_Cost_Energy_per_MWh, n_modules, ...
    'Annual_Cost_Energy_per_MWh');
charge_efficiency = expand_module_parameter( ...
    module_params.Charge_Efficiency, n_modules, 'Charge_Efficiency');
discharge_efficiency = expand_module_parameter( ...
    module_params.Discharge_Efficiency, n_modules, 'Discharge_Efficiency');
soc_max = expand_module_parameter(module_params.SOC_Max, n_modules, 'SOC_Max');
soc_initial = expand_module_parameter( ...
    module_params.SOC_Initial, n_modules, 'SOC_Initial');
soc_min = expand_module_parameter(module_params.SOC_Min, n_modules, 'SOC_Min');

validate_gfm_storage_parameters(pn_mw, rated_energy, charge_efficiency, ...
    discharge_efficiency, soc_min, soc_initial, soc_max);

candidate_bus = unique(bus,'stable');
[~, candidate_index] = ismember(bus,candidate_bus);
candidate_charge_efficiency = collapse_candidate_parameter( ...
    charge_efficiency,candidate_index,numel(candidate_bus),'Charge_Efficiency');
candidate_discharge_efficiency = collapse_candidate_parameter( ...
    discharge_efficiency,candidate_index,numel(candidate_bus),'Discharge_Efficiency');
candidate_rated_duration = collapse_candidate_parameter( ...
    rated_energy./pn_mw,candidate_index,numel(candidate_bus),'Rated_Duration_Hours');
candidate_soc_max = collapse_candidate_parameter( ...
    soc_max,candidate_index,numel(candidate_bus),'SOC_Max');
candidate_soc_initial = collapse_candidate_parameter( ...
    soc_initial,candidate_index,numel(candidate_bus),'SOC_Initial');
candidate_soc_min = collapse_candidate_parameter( ...
    soc_min,candidate_index,numel(candidate_bus),'SOC_Min');

GFMModules = struct();
GFMModules.Count = n_modules;
GFMModules.Bus = bus;
GFMModules.Order = order;
GFMModules.PN_MW = pn_mw;
GFMModules.Cost_Conv_GFM = cost_conv;
GFMModules.Rated_Energy_MWh = rated_energy;
GFMModules.Annual_Cost_Power_per_MW = power_cost;
GFMModules.Annual_Cost_Energy_per_MWh = energy_cost;
GFMModules.X_GFM_res = x_res;
GFMModules.I_Post_Multiplier = i_post_multiplier;
GFMModules.I_post = i_post_multiplier.*pn_mw/CONF.Base_MVA;
GFMModules.X_GFM_vir = x_vir;
GFMModules.DeltaY = 1./(1i*(x_res+x_vir))-1./(1i*x_res);
GFMModules.CandidateBus = candidate_bus;
GFMModules.CandidateIndex = candidate_index;
GFMModules.CandidateChargeEfficiency = candidate_charge_efficiency;
GFMModules.CandidateDischargeEfficiency = candidate_discharge_efficiency;
GFMModules.CandidateRatedDuration = candidate_rated_duration;
GFMModules.CandidateSOCMax = candidate_soc_max;
GFMModules.CandidateSOCInitial = candidate_soc_initial;
GFMModules.CandidateSOCMin = candidate_soc_min;
GFMModules.N_Module_Max = module_params.N_Module_Max;
GFMModules.MaxModulesPerCandidate = module_params.MaxModulesPerCandidate;
GFMModules.EnforceSequentialBuild = logical(module_params.EnforceSequentialBuild);

end

function values = expand_module_parameter(values, n_modules, field_name)
%% 将模块参数扩展为与模块表等长的列向量。

values = values(:);
if isscalar(values)
    values = repmat(values,n_modules,1);
elseif numel(values) ~= n_modules
    error('GFM_Modules.%s的长度应为1或模块数量%d。',field_name,n_modules);
end

end

function validate_gfm_storage_parameters(pn_mw, rated_energy, charge_efficiency, ...
    discharge_efficiency, soc_min, soc_initial, soc_max)
%% 校验GFM-ES储能参数是否满足文档模型的物理取值范围。

if any(pn_mw <= 0)
    error('GFM-ES模块额定功率必须为正数。');
end
if any(rated_energy <= 0)
    error('GFM-ES模块额定储存能量必须为正数。');
end
if any(charge_efficiency <= 0 | charge_efficiency > 1) || ...
        any(discharge_efficiency <= 0 | discharge_efficiency > 1)
    error('GFM-ES充电效率和放电效率必须位于区间(0,1]。');
end
if any(soc_min < 0 | soc_max > 1 | soc_min > soc_initial | ...
        soc_initial > soc_max)
    error('GFM-ES SOC参数必须满足0<=SOC_Min<=SOC_Initial<=SOC_Max<=1。');
end

end

function candidate_values = collapse_candidate_parameter(module_values, ...
    candidate_index, candidate_count, field_name)
%% 将模块参数整理为候选节点参数，并校验同一节点内模块参数相同。

candidate_values = zeros(candidate_count,1);
for k = 1:candidate_count
    values_k = module_values(candidate_index == k);
    if any(abs(values_k-values_k(1)) > 1e-12)
        error('同一候选节点内各模块的GFM_Modules.%s必须相同。',field_name);
    end
    candidate_values(k) = values_k(1);
end

end

function node_values = expand_built_node_parameter(values, built_nodes, n_nodes)
%% 将已投建节点参数扩展为完整节点向量。
values = values(:);
node_values = zeros(n_nodes,1);

if numel(values) == n_nodes
    node_values = values;
else
    node_values(built_nodes) = values;
end

end

function node_values = expand_system_node_parameter(values, n_nodes)
%% 将系统级参数扩展为完整节点向量。
values = values(:);
if isscalar(values)
    node_values = repmat(values,n_nodes,1);
else
    node_values = values;
end

end

function [retained_nodes, original_to_reduced] = ...
    build_safety_network_mapping(generator_nodes, gfm_nodes, gfl_nodes, n_nodes)
%% 构造安全网络统一保留节点集合及原节点到降阶节点的映射。

all_nodes = [generator_nodes(:); gfm_nodes(:); gfl_nodes(:)];
if any(~isfinite(all_nodes)) || any(all_nodes ~= round(all_nodes)) || ...
        any(all_nodes < 1) || any(all_nodes > n_nodes)
    error('安全网络有源设备接入节点必须为1至节点总数%d之间的整数。',n_nodes);
end
if numel(unique(gfl_nodes(:))) ~= numel(gfl_nodes)
    error('GFL_Built_Nodes不应包含重复节点。');
end

retained_nodes = unique(all_nodes,'sorted');
original_to_reduced = zeros(n_nodes,1);
original_to_reduced(retained_nodes) = (1:numel(retained_nodes)).';

end

function value = get_struct_field(input_struct, field_name, default_value)
%% 本函数功能是读取结构体可选字段。

if isfield(input_struct, field_name) && ~isempty(input_struct.(field_name))
    value = input_struct.(field_name);
else
    value = default_value;
end

end

function [names, probabilities, scale_factors, available_scenarios, ...
    generation_mode, base_index] = build_wind_scenarios( ...
    multi, base_available, u_gfl, day_count, period_count, node_count)
%% 集中解析风电场景，并构造[节点,典型日,场景,时段]可用出力。

if ~isfield(multi, 'WindScenarios') || isempty(multi.WindScenarios)
    scenario = struct('Count',1, 'Names',{{'base'}}, ...
        'Probabilities',1, 'ScaleFactors',1, ...
        'GenerationMode','scale_base_profiles');
else
    scenario = multi.WindScenarios;
end

probability_input = get_struct_field(scenario, 'Probabilities', 1);
scenario_count = get_struct_field(scenario, 'Count', numel(probability_input));
if ~isscalar(scenario_count) || ~isfinite(scenario_count) || ...
        scenario_count ~= round(scenario_count) || scenario_count < 1
    error('MultipleSnapshot.WindScenarios.Count必须为正整数。');
end

names_input = get_struct_field(scenario, 'Names', ...
    arrayfun(@(k) sprintf('scenario_%d',k), 1:scenario_count, ...
    'UniformOutput',false));
names = cellstr(string(names_input(:)));
names = names(:).';
if numel(names) ~= scenario_count || any(cellfun(@isempty,names)) || ...
        numel(unique(lower(string(names)))) ~= scenario_count
    error('WindScenarios.Names应包含%d个非空且互不重复的场景名称。',scenario_count);
end

probabilities = expand_day_scenario_parameter( ...
    probability_input, day_count, scenario_count, 'Probabilities');
if any(~isfinite(probabilities(:))) || any(probabilities(:) <= 0) || ...
        any(abs(sum(probabilities,2)-1) > 1e-12)
    error('各典型日的WindScenarios.Probabilities必须为正数且逐日合计为1。');
end

generation_mode = char(string(get_struct_field( ...
    scenario, 'GenerationMode', 'scale_base_profiles')));
switch lower(generation_mode)
    case 'scale_base_profiles'
        scale_factors = expand_day_scenario_parameter( ...
            get_struct_field(scenario, 'ScaleFactors', ones(1,scenario_count)), ...
            day_count, scenario_count, 'ScaleFactors');
        if any(~isfinite(scale_factors(:))) || any(scale_factors(:) < 0)
            error('WindScenarios.ScaleFactors必须为有限非负数。');
        end
        available_scenarios = ...
            reshape(base_available,node_count,day_count,1,period_count).* ...
            reshape(scale_factors,1,day_count,scenario_count,1);
    case 'explicit'
        explicit_available = get_struct_field( ...
            scenario, 'GFL_Available_P_MW', []);
        expected_count = node_count*day_count*scenario_count*period_count;
        if numel(explicit_available) ~= expected_count
            error(['WindScenarios.GFL_Available_P_MW在explicit模式下应包含', ...
                '%d个节点-典型日-场景-时段数据。'],expected_count);
        end
        available_scenarios = reshape(explicit_available, ...
            node_count,day_count,scenario_count,period_count);
        scale_factors = NaN(day_count,scenario_count);
    otherwise
        error('不支持的WindScenarios.GenerationMode：%s。',generation_mode);
end

if any(~isfinite(available_scenarios(:))) || any(available_scenarios(:) < 0)
    error('各场景GFL-WG可用出力必须为有限非负数。');
end
non_gfl_nodes = u_gfl < 0.5;
if any(available_scenarios(non_gfl_nodes,:,:,:) ~= 0,'all')
    error('非GFL-WG接入节点的各场景可用出力必须为零。');
end

base_index = find(strcmpi(names,'base'),1);
if isempty(base_index) && all(isfinite(scale_factors(:)))
    unit_scale = find(all(abs(scale_factors-1) <= 1e-12,1));
    if isscalar(unit_scale)
        base_index = unit_scale;
    end
end
if isempty(base_index)
    base_index = NaN;
end

function values = expand_day_scenario_parameter(values, day_count, ...
    scenario_count, field_name)
%% 将场景参数扩展为[典型日,场景]矩阵。

if isvector(values) && numel(values) == scenario_count
    values = repmat(reshape(values,1,scenario_count),day_count,1);
elseif numel(values) == day_count*scenario_count
    values = reshape(values,day_count,scenario_count);
else
    error('WindScenarios.%s的维度应为1×%d或%d×%d。', ...
        field_name,scenario_count,day_count,scenario_count);
end

end

end
