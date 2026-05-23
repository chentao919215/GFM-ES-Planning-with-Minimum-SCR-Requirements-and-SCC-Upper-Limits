function [mpc, CONF, paths] = load_single_snapshot_case(project_root, param_file)
%LOAD_SINGLE_SNAPSHOT_CASE 读取单时刻规划算例与默认参数。

if nargin < 1 || isempty(project_root)
    project_root = find_project_root(mfilename('fullpath'));
end

default_param_file = fullfile(project_root, 'data', 'params', 'single_snapshot_default_params.json');
if nargin < 2 || isempty(param_file)
    param_file = default_param_file;
end

if strcmp(param_file, default_param_file) && exist(param_file, 'file') ~= 2
    generator_file = fullfile(project_root, 'data', 'params', 'generate_single_snapshot_default_params.m');
    if exist(generator_file, 'file') == 2
        run(generator_file);
    end
end

params = read_json_file(param_file);

paths = struct();
paths.project_root = project_root;
paths.param_file   = param_file;
paths.results_dir  = fullfile(project_root, 'results');
ensure_directory(paths.results_dir);

mpc = case30;

CONF = struct();
CONF.Bn = size(mpc.bus, 1);
CONF.Gn = size(mpc.gen, 1);
CONF.Ln = size(mpc.branch, 1);

CONF.Base_MVA = mpc.baseMVA;
CONF.Base_kV  = mpc.bus(1,10);
CONF.Base_kA  = CONF.Base_MVA/(CONF.Base_kV*sqrt(3));
CONF.Base_O   = CONF.Base_kV^(2)/CONF.Base_MVA;

CONF.LoadFactor = params.LoadFactor;

mpc.branch(:,3) = params.BranchScale.r * mpc.branch(:,3);
mpc.branch(:,4) = params.BranchScale.x * mpc.branch(:,4);
mpc.branch(:,5) = params.BranchScale.b * mpc.branch(:,5);

CONF.Xd_Gen = params.Xd_Gen;
mpc.gencost(:,7) = mpc.gencost(:,5).*((params.GenCostLoading*mpc.gen(:,9)).^2) + ...
                   mpc.gencost(:,6).*(params.GenCostLoading*mpc.gen(:,9));

CONF.PN     = params.PN;
CONF.I_post = 3*CONF.PN/CONF.Base_MVA;

CONF.X_GFM_res = CONF.Xd_Gen;
CONF.X_GFM_vir = 1/CONF.I_post;

CONF.GFM_Candidates = params.GFM_Candidates(:)';
CONF.N_GFM_max      = params.N_GFM_max;

CONF.u_GFL = zeros(CONF.Bn,1);
CONF.u_GFL(params.GFL_Built_Nodes(:)) = 1;

CONF.Cost_Conv_GFM = params.Cost_Conv_GFM;

CONF.I_limit = params.I_limit_kA/CONF.Base_kA;
CONF.SCR_min = params.SCR_min;

CONF.Num_Calculation = params.Num_Calculation;
CONF.KZ      = params.KZ;
CONF.ERR_TOL = params.ERR_TOL_FACTOR*CONF.KZ;

if isfield(params, 'ZBoundMargin')
    CONF.ZBoundMargin = params.ZBoundMargin;
else
    CONF.ZBoundMargin = 0.05;
end

end
