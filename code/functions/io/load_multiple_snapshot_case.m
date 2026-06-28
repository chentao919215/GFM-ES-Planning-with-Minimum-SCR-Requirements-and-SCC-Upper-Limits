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
CONF.GFM_Module_X_res = GFMModules.X_GFM_res;
CONF.GFM_Module_I_post = GFMModules.I_post;
CONF.GFM_Module_X_vir = GFMModules.X_GFM_vir;
CONF.GFM_Module_DeltaY = GFMModules.DeltaY;
CONF.GFM_Module_DeltaY_abs = abs(GFMModules.DeltaY);
CONF.GFM_Module_Loc_Mat = sparse(GFMModules.Bus,(1:GFMModules.Count)', ...
    1,CONF.Bn,GFMModules.Count);
CONF.GFM_Module_Candidates = unique(GFMModules.Bus,'stable')';
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

%% 8. 计算文档口径下的GFM-ES模块年化投建成本
modules      = params.GFM_Modules;
power_cost   = modules.Annual_Cost_Power_per_MW(:);
energy_cost  = modules.Annual_Cost_Energy_per_MWh(:);
rated_energy = modules.Rated_Energy_MWh(:);

CONF.GFM_Module_Annual_Cost_Power  = power_cost.*CONF.GFM_Module_PN(:);
CONF.GFM_Module_Annual_Cost_Energy = energy_cost.*rated_energy;
CONF.GFM_Module_Rated_Energy = rated_energy;
CONF.GFM_Module_Cost_Conv    = CONF.GFM_Module_Annual_Cost_Power+CONF.GFM_Module_Annual_Cost_Energy;

%% 9. 整理算例路径
paths = struct();
paths.project_root = project_root;
paths.param_file = param_file;
paths.results_dir = fullfile(project_root,'results');
ensure_directory(paths.results_dir);

end

function GFMModules = build_gfm_module_params(params, CONF)
%% 读取模块化GFM-ES参数表。
module_params = params.GFM_Modules;
bus = module_params.Bus(:);

n_modules = numel(bus);
order = module_params.ModuleIndex(:);
pn_mw = module_params.PN_MW(:);
cost_conv = module_params.Cost_Conv_GFM(:);
x_res = module_params.X_GFM_res(:);
i_post_multiplier = module_params.I_Post_Multiplier(:);
x_vir = module_params.X_GFM_vir(:);

GFMModules = struct();
GFMModules.Count = n_modules;
GFMModules.Bus = bus;
GFMModules.Order = order;
GFMModules.PN_MW = pn_mw;
GFMModules.Cost_Conv_GFM = cost_conv;
GFMModules.X_GFM_res = x_res;
GFMModules.I_Post_Multiplier = i_post_multiplier;
GFMModules.I_post = i_post_multiplier.*pn_mw/CONF.Base_MVA;
GFMModules.X_GFM_vir = x_vir;
GFMModules.DeltaY = 1./(1i*(x_res+x_vir))-1./(1i*x_res);
GFMModules.N_Module_Max = module_params.N_Module_Max;
GFMModules.MaxModulesPerCandidate = module_params.MaxModulesPerCandidate;
GFMModules.EnforceSequentialBuild = logical(module_params.EnforceSequentialBuild);

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
