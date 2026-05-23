%% 生成单时刻 GFM-ES 配置算例的默认参数文件
% 本文件是给人阅读和维护的参数源文件；JSON 文件是给程序读取的参数文件。
% 修改参数时，优先修改本脚本，然后运行本脚本重新生成
% single_snapshot_default_params.json。

clear params;

param_dir = fileparts(mfilename('fullpath'));
if isempty(param_dir)
    param_dir = pwd;
end

output_file = fullfile(param_dir, 'single_snapshot_default_params.json');

%% 1. 单时刻运行场景
% LoadFactor 表示相对于 IEEE-30 原始负荷的比例。
params.LoadFactor = 1.0;

%% 2. 线路参数修正
% r、x、b 分别对应 MATPOWER branch 表中的电阻、电抗和线路充电电纳。
params.BranchScale = struct();
params.BranchScale.r = 2;
params.BranchScale.x = 2;
params.BranchScale.b = 0.5;

%% 3. 同步机与变流器基础参数
% Xd_Gen 为同步机暂态电抗；GenCostLoading 用于构造同步机固定成本项。
params.Xd_Gen = 0.04;
params.GenCostLoading = 0.05;

% PN 为 GFL/GFM 单站额定有功容量，单位为 MW。
params.PN = 60;

%% 4. GFM-ES 规划参数
% GFM_Candidates 为允许投建 GFM-ES 的节点集合。
params.GFM_Candidates = [9, 15, 20, 27];

% N_GFM_max 为本次规划中最多允许投建的 GFM-ES 数量。
params.N_GFM_max = 2;

% GFL_Built_Nodes 为已知已建 GFL 节点集合，采用 1 = 已建、0 = 未建的语义。
params.GFL_Built_Nodes = [11, 18];

% Cost_Conv_GFM 为单个 GFM-ES 的投建成本。
params.Cost_Conv_GFM = 8760*75;

%% 5. 安全约束参数
% I_limit_kA 为短路电流上限，单位为 kA。
params.I_limit_kA = 11.5;

% SCR_min 为经典短路比下限，SCR = S_ac / P_N。
params.SCR_min = 3;

%% 6. 求解器与数值参数
params.Num_Calculation = 1;
params.M_BIG_L = 1e4;
params.M_BIG_Z = 1e4;
params.KZ = 1e3;

% ERR_TOL_FACTOR 会在加载时乘以 KZ，得到阻抗矩阵约束的绝对容差。
params.ERR_TOL_FACTOR = 1e-6;

%% 7. 写出 JSON 文件
json_text = jsonencode(params, 'PrettyPrint', true);

fid = fopen(output_file, 'w', 'n', 'UTF-8');
if fid < 0
    error('Cannot open parameter output file: %s', output_file);
end
fprintf(fid, '%s\n', json_text);
fclose(fid);

fprintf('已生成参数文件：%s\n', output_file);
