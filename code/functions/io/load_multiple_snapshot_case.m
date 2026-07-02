function [mpc, CONF, paths] = load_multiple_snapshot_case(project_root, param_file)
%% 本函数功能是加载确定性多时刻算例并构造优化配置参数。
% 本函数独立读取静态网络、设备、安全约束和多时刻运行参数。

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

day_weights  = multi.TypicalDayWeights_Days(:);
period_hours = multi.PeriodDurations_Hours(:);

CONF.TypicalDayCount = D;
CONF.PeriodCount     = T;
CONF.TypicalDayWeights_Days = day_weights;
CONF.PeriodDurations_Hours = period_hours;
CONF.OperatingWeights_Hours = day_weights*period_hours.';

%% 7. 读取逐时负荷与GFL-WG可用出力
CONF.P_Load_Profile = reshape(multi.Load_P_MW, CONF.Bn, D, T);
CONF.P_GFL_Available_Profile = reshape(multi.GFL_Available_P_MW, CONF.Bn, D, T);

% 同步机最小出力显式由多时刻参数文件给定。
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

function value = get_struct_field(input_struct, field_name, default_value)
%% 本函数功能是读取结构体可选字段。

if isfield(input_struct, field_name) && ~isempty(input_struct.(field_name))
    value = input_struct.(field_name);
else
    value = default_value;
end

end
