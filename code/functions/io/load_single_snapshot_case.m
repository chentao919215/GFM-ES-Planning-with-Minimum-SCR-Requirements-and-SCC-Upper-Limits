function [mpc, CONF, paths] = load_single_snapshot_case(project_root, param_file)
%% Build the single-snapshot MATPOWER case and optimization configuration.
params = read_json_file(param_file);

%% 1. MATPOWER case
mpc = params.mpc;

mpc.branch(:,3) = params.BranchScale.r*mpc.branch(:,3);
mpc.branch(:,4) = params.BranchScale.x*mpc.branch(:,4);
mpc.branch(:,5) = params.BranchScale.b*mpc.branch(:,5);

mpc.gencost(:,7) = 0;

%% 2. Optimization configuration
CONF = struct();

CONF.Bn = size(mpc.bus, 1);
CONF.Gn = size(mpc.gen, 1);
CONF.Ln = size(mpc.branch, 1);

CONF.Base_MVA = params.base_MVA;
CONF.Base_kV  = params.base_kV;
CONF.Base_kA  = params.base_kA;
CONF.Base_O   = params.base_O;

% 以下字段仅由单时刻模型使用；多时刻参数文件可以不再保留。
if isfield(params, 'LoadFactor')
    CONF.LoadFactor = params.LoadFactor;
end
if isfield(params, 'AnnualHours')
    CONF.AnnualHours = params.AnnualHours;
    if CONF.AnnualHours <= 0
        error('AnnualHours must be positive.');
    end
end

CONF.Xd_Gen = params.Xd_Gen;
CONF.GenCostBreakpoints = params.GenCostBreakpoints(:)';

if isempty(CONF.GenCostBreakpoints) || any(CONF.GenCostBreakpoints < 0) || ...
        any(CONF.GenCostBreakpoints > 1) || any(diff(CONF.GenCostBreakpoints) < 0)
    error('GenCostBreakpoints must be a nondecreasing vector in [0, 1].');
end

CONF.GFM_Candidates = params.GFM_Candidates(:)';

gfl_built_nodes = params.GFL_Built_Nodes(:);
CONF.u_GFL = zeros(CONF.Bn,1);
CONF.u_GFL(gfl_built_nodes) = 1;

gfl_params = params.GFL_WG;
CONF.PN_GFL_Node = expand_built_node_parameter( ...
    gfl_params.PN_MW, gfl_built_nodes, CONF.Bn, 'GFL_WG.PN_MW');
CONF.PN_GFL = max(CONF.PN_GFL_Node(CONF.u_GFL > 0.5));
CONF.PN_GFL_pu_Node = CONF.PN_GFL_Node/CONF.Base_MVA;

gfl_i_post_multiplier = expand_built_node_parameter( ...
    gfl_params.I_Post_Multiplier, gfl_built_nodes, CONF.Bn, ...
    'GFL_WG.I_Post_Multiplier');
CONF.I_post_GFL_Node = gfl_i_post_multiplier.*CONF.PN_GFL_Node/CONF.Base_MVA;
CONF.I_post = max(CONF.I_post_GFL_Node);

CONF.Require_Source_Online = logical(params.Require_Source_Online);

GFMModules = build_gfm_module_params(params, CONF);
CONF.GFM_Module_Count = GFMModules.Count;
CONF.GFM_Module_Bus = GFMModules.Bus;
CONF.GFM_Module_Order = GFMModules.Order;
CONF.GFM_Module_PN = GFMModules.PN_MW;
CONF.GFM_Module_PN_pu = GFMModules.PN_MW / CONF.Base_MVA;
CONF.GFM_Module_Cost_Conv = GFMModules.Cost_Conv_GFM;
CONF.GFM_Module_X_res = GFMModules.X_GFM_res;
CONF.GFM_Module_I_post = GFMModules.I_post;
CONF.GFM_Module_X_vir = GFMModules.X_GFM_vir;
CONF.GFM_Module_DeltaY = GFMModules.DeltaY;
CONF.GFM_Module_DeltaY_abs = abs(GFMModules.DeltaY);
CONF.GFM_Module_Loc_Mat = sparse(GFMModules.Bus, (1:GFMModules.Count)', ...
    1, CONF.Bn, GFMModules.Count);
CONF.GFM_Module_Candidates = unique(GFMModules.Bus, 'stable')';
CONF.N_GFM_Module_Max = GFMModules.N_Module_Max;
CONF.GFM_MaxModulesPerCandidate = GFMModules.MaxModulesPerCandidate;
CONF.GFM_Module_Sequential = GFMModules.EnforceSequentialBuild;
CONF.GFM_Module_I_Post_Multiplier = GFMModules.I_Post_Multiplier;

CONF.I_limit_kA_Node = expand_system_node_parameter(params.I_limit_kA, CONF.Bn, 'I_limit_kA');
CONF.I_limit = CONF.I_limit_kA_Node/CONF.Base_kA;
CONF.SCR_min = params.SCR_min;

CONF.KZ = params.KZ;
CONF.ERR_TOL = params.ERR_TOL_FACTOR*CONF.KZ;
CONF.ZBoundMargin = params.ZBoundMargin;

%% 3. Paths
paths = struct();
paths.project_root = project_root;
paths.param_file = param_file;
paths.results_dir = fullfile(project_root, 'results');
ensure_directory(paths.results_dir);

end

function GFMModules = build_gfm_module_params(params, CONF)
%% Read the explicit modular GFM-ES parameter table.
module_params = params.GFM_Modules;
bus = module_params.Bus(:);

n_modules = numel(bus);
if n_modules == 0
    error('GFM_Modules.Bus must contain at least one module.');
end

if any(bus < 1 | bus > CONF.Bn | fix(bus) ~= bus)
    error('GFM_Modules.Bus contains an out-of-range or non-integer bus index.');
end

order = require_module_vector(module_params.ModuleIndex, n_modules, ...
    'GFM_Modules.ModuleIndex');
pn_mw = require_module_vector(module_params.PN_MW, n_modules, ...
    'GFM_Modules.PN_MW');
cost_conv = require_module_vector(module_params.Cost_Conv_GFM, n_modules, ...
    'GFM_Modules.Cost_Conv_GFM');
x_res = require_module_vector(module_params.X_GFM_res, n_modules, ...
    'GFM_Modules.X_GFM_res');
i_post_multiplier = require_module_vector(module_params.I_Post_Multiplier, ...
    n_modules, 'GFM_Modules.I_Post_Multiplier');
x_vir = require_module_vector(module_params.X_GFM_vir, n_modules, ...
    'GFM_Modules.X_GFM_vir');

GFMModules = struct();
GFMModules.Count = n_modules;
GFMModules.Bus = bus;
GFMModules.Order = order;
GFMModules.PN_MW = pn_mw;
GFMModules.Cost_Conv_GFM = cost_conv;
GFMModules.X_GFM_res = x_res;
GFMModules.I_Post_Multiplier = i_post_multiplier;
GFMModules.I_post = i_post_multiplier .* pn_mw / CONF.Base_MVA;
GFMModules.X_GFM_vir = x_vir;
GFMModules.DeltaY = 1 ./ (1i * (x_res + x_vir)) - 1 ./ (1i * x_res);
GFMModules.N_Module_Max = module_params.N_Module_Max;
GFMModules.MaxModulesPerCandidate = module_params.MaxModulesPerCandidate;
GFMModules.EnforceSequentialBuild = logical(module_params.EnforceSequentialBuild);

end

function values = require_module_vector(values, n_modules, field_name)
%% Require one explicit value per configured GFM-ES module.
values = values(:);

if numel(values) ~= n_modules
    error('%s length must equal the number of modules: %d.', field_name, n_modules);
end

end

function node_values = expand_built_node_parameter(values, built_nodes, n_nodes, field_name)
%% Expand explicitly configured built-site parameters to a full bus vector.
values = values(:);
node_values = zeros(n_nodes, 1);

if isscalar(values)
    node_values(built_nodes) = values;
elseif numel(values) == numel(built_nodes)
    node_values(built_nodes) = values;
elseif numel(values) == n_nodes
    node_values = values;
else
    error('%s length must be 1, the number of built GFL nodes (%d), or the number of buses (%d).', ...
        field_name, numel(built_nodes), n_nodes);
end

end

function node_values = expand_system_node_parameter(values, n_nodes, field_name)
%% Expand explicitly configured system-level node parameters to a bus vector.
values = values(:);

if isscalar(values)
    node_values = repmat(values, n_nodes, 1);
elseif numel(values) == n_nodes
    node_values = values;
else
    error('%s length must be 1 or the number of buses: %d.', field_name, n_nodes);
end

end
