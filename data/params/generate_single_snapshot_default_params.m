%% 生成单时刻GFM-ES配置算例的默认参数文件
% 本文件是给人阅读和维护的参数源文件；JSON文件是给程序读取的参数文件。
% 修改参数时，优先修改本脚本，然后运行本脚本重新生成参数文件:
% single_snapshot_default_params.json。

clear params;
param_dir   = fileparts(mfilename('fullpath'));
output_file = fullfile(param_dir, 'single_snapshot_default_params.json');

%% 0. 读取Matpower基准值
mpc          = case30;
params.mpc      = mpc;
params.base_MVA = mpc.baseMVA;
params.base_kV  = mpc.bus(1,10);
params.base_kA  = params.base_MVA/params.base_kV/sqrt(3);
params.base_O   = params.base_kV^2/params.base_MVA;

%% 1. 单时刻运行场景
% LoadFactor:表示相对于IEEE-30原始负荷的比例。
params.LoadFactor = 1.0;

%% 2. 线路参数修正
% r、x、b:MATPOWER branch表中的电阻、电抗和线路充电电纳。
params.BranchScale = struct();
params.BranchScale.r = 2;
params.BranchScale.x = 2;
params.BranchScale.b = 0.5;

%% 3. 同步机与变流器基础参数
% Xd_Gen:同步机暂态电抗。
% GenCostLoading:构造同步机固定成本项，现在5%出力时的成本为固定成本。
params.Xd_Gen = 0.04;
params.GenCostLoading = 0.05;
% AnnualHours annualizes the representative single-snapshot operating cost.
params.AnnualHours = 8760;
% GenCostBreakpoints are normalized SG output breakpoints for perspective cuts.
params.GenCostBreakpoints = 0:0.1:1;

% PN为旧版节点级模型使用的GFL/GFM单站额定有功容量，单位为MW。
% 后续模块化模型优先使用params.GFM_Modules中的模块级容量。
params.PN = 60;

% GFL_WG用于显式记录已建GFL-WG场站参数。
% PN_MW可以为标量、与GFL_Built_Nodes等长的向量，或全节点向量。
% 目前各已建GFL-WG采用相同额定容量和限流倍数。
params.GFL_WG = struct();
params.GFL_WG.PN_MW = 60;
params.GFL_WG.I_Post_Multiplier = 3;

%% 4. GFM-ES规划参数
% GFM_Candidates:允许投建GFM-ES的节点集合。
params.GFM_Candidates = [9, 15, 20, 27];

% GFL_Built_Nodes:已建GFL节点集合。
params.GFL_Built_Nodes = [11, 18];

% Cost_Conv_GFM为旧版节点级GFM-ES的年化投建成本。
params.Cost_Conv_GFM = 657000;

% X_GFM_res和X_GFM_vir为旧版节点级GFM-ES默认电抗参数。
% 模块化模型优先使用params.GFM_Modules中的模块级参数。
params.X_GFM_res = 0.02;
params.X_GFM_vir = 1/3 - params.X_GFM_res;

% GFM_Modules定义模块化GFM-ES参数表。
params.GFM_Modules = struct();
params.GFM_Modules.MaxModulesPerCandidate = 2;
params.GFM_Modules.N_Module_Max           = 4;
params.GFM_Modules.EnforceSequentialBuild = true;
params.GFM_Modules.Bus           = [9, 9, 15, 15, 20, 20, 27, 27];
params.GFM_Modules.ModuleIndex   = [1, 2, 1, 2, 1, 2, 1, 2];
params.GFM_Modules.PN_MW         = [30, 30, 30, 30, 30, 30, 30, 30];
params.GFM_Modules.Cost_Conv_GFM = [328500, 328500, 328500, 328500, 328500, 328500, 328500, 328500];
params.GFM_Modules.X_GFM_res     = [0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02]*...
    params.base_MVA./params.GFM_Modules.PN_MW; % 设备级标幺值->系统级标幺值。
params.GFM_Modules.I_Post_Multiplier = [3, 3, 3, 3, 3, 3, 3, 3];
params.GFM_Modules.X_GFM_vir = (1./params.GFM_Modules.I_Post_Multiplier - 0.02)*...
    params.base_MVA./params.GFM_Modules.PN_MW; % 设备级标幺值->系统级标幺值。

%% 5. 安全约束参数
% I_limit_kA:短路电流上限，单位为kA，可以为标量或全节点向量。
params.I_limit_kA = 11.5;

% SCR_min:经典短路比下限，无量纲。
params.SCR_min = 3;

% Require_Source_Online:是否要求至少一个同步机或GFM-ES模块投运/投建。
% 模块化GFM-ES模型默认采用后者，以允许同步机全停但GFM-ES成网支撑的工况。
params.Require_Source_Online = true;

%% 6. 求解器与数值参数
% KZ:放大阻抗元素，改善数值稳健性。
params.KZ = 1e3;

% ZBoundMargin:枚举离散投运组合估计Z元素上下界时保留的安全裕度。
params.ZBoundMargin = 0.05;

% ERR_TOL_FACTOR:会乘以KZ得到阻抗矩阵约束的绝对容差。
params.ERR_TOL_FACTOR = 1e-6;

%% 7. 写出JSON文件
json_text = jsonencode(params, 'PrettyPrint', true);

fid = fopen(output_file, 'w', 'n', 'UTF-8');
if fid < 0
    error('Cannot open parameter output file: %s', output_file);
end
fprintf(fid, '%s\n', json_text);
fclose(fid);

fprintf('已生成参数文件：%s\n', output_file);

%% 8. 清除本脚本生成的变量
clear ans fid json_text output_file param_dir params
