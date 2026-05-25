function [mpc, CONF, paths] = load_single_snapshot_case(project_root, param_file)
%% 本函数功能是根据参数文件生成单时刻规划算例数据。
params = read_json_file(param_file);

%% 1. 生成MATPOWER算例结构体:mpc
mpc = case30; % 此处修改基准算例。

% 修改线路参数
mpc.branch(:,3) = params.BranchScale.r*mpc.branch(:,3);
mpc.branch(:,4) = params.BranchScale.x*mpc.branch(:,4);
mpc.branch(:,5) = params.BranchScale.b*mpc.branch(:,5);

% 修改机组成本
mpc.gencost(:,7) = mpc.gencost(:,5).*((params.GenCostLoading*mpc.gen(:,9)).^2) + ...
                   mpc.gencost(:,6).*(params.GenCostLoading*mpc.gen(:,9));

%% 2. 生成优化配置结构体:CONF
CONF = struct();

% 算例规模参数
CONF.Bn = size(mpc.bus, 1);
CONF.Gn = size(mpc.gen, 1);
CONF.Ln = size(mpc.branch, 1);

% 基准值计算
CONF.Base_MVA = mpc.baseMVA;
CONF.Base_kV  = mpc.bus(1,10);
CONF.Base_kA  = CONF.Base_MVA/(CONF.Base_kV*sqrt(3));
CONF.Base_O   = CONF.Base_kV^(2)/CONF.Base_MVA;

% 负荷系数
CONF.LoadFactor = params.LoadFactor;

% 同步机次暂态电抗
CONF.Xd_Gen     = params.Xd_Gen;

% 变流器相关参数
CONF.PN     = params.PN;
CONF.I_post = 3*CONF.PN/CONF.Base_MVA;

CONF.X_GFM_res = CONF.Xd_Gen;
CONF.X_GFM_vir = 1/CONF.I_post;

CONF.GFM_Candidates = params.GFM_Candidates(:)';
CONF.N_GFM_max      = params.N_GFM_max;

CONF.u_GFL = zeros(CONF.Bn,1);
CONF.u_GFL(params.GFL_Built_Nodes(:)) = 1;

CONF.Cost_Conv_GFM = params.Cost_Conv_GFM;

% 规划阈值参数
CONF.I_limit = params.I_limit_kA/CONF.Base_kA;
CONF.SCR_min = params.SCR_min;

% 规划求解参数
CONF.KZ      = params.KZ;
CONF.ERR_TOL = params.ERR_TOL_FACTOR*CONF.KZ;
CONF.ZBoundMargin = params.ZBoundMargin;

%% 3. 生成路径结构体:paths
paths = struct();
paths.project_root = project_root;
paths.param_file   = param_file;
paths.results_dir  = fullfile(project_root, 'results');
ensure_directory(paths.results_dir);

end
