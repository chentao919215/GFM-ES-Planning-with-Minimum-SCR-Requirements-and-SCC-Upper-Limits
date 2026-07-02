%% 生成多时刻GFM-ES配置算例的默认参数文件
% 本文件是给人阅读和维护的参数源文件；JSON文件是给程序读取的参数文件。
% 修改参数时，优先修改本脚本，然后运行本脚本重新生成参数文件:
% multiple_snapshot_default_params.json。

clear params;
param_dir   = fileparts(mfilename('fullpath'));
output_file = fullfile(param_dir, 'multiple_snapshot_default_params.json');

%% 0. 读取Matpower基准值
mpc             = case30;
params.mpc      = mpc;
params.base_MVA = mpc.baseMVA;
params.base_kV  = mpc.bus(1,10);
params.base_kA  = params.base_MVA/params.base_kV/sqrt(3);
params.base_O   = params.base_kV^2/params.base_MVA;

%% 1. 多时刻运行场景
% 采用若干确定性典型日，每个典型日包含12个连续2小时时段。
% TypicalDayWeights_Days表示各典型日代表的实际天数，合计应为365天。
% PeriodDurations_Hours表示各时段持续小时数，单个典型日内合计应为24小时。
params.MultipleSnapshot = struct();
params.MultipleSnapshot.TypicalDayCount         = 3;
params.MultipleSnapshot.PeriodCount             = 12;
params.MultipleSnapshot.TypicalDayWeights_Days  = [255,55,55];
% Factor的第一、二列分别为GFL-WG可用出力倍率和负荷倍率。
% 第一、二、三行分别对应普通典型日、低净负荷日和高净负荷日。
params.MultipleSnapshot.Factor                  = [1.0, 1.0;
                                                   1.1, 0.9;
                                                   0.9, 1.0];
params.MultipleSnapshot.PeriodDurations_Hours   = 2*ones(1,12);
params.MultipleSnapshot.LoadProfileSource       = 'MOST ex_load_profile';
params.MultipleSnapshot.WindProfileSource       = 'MOST ex_wind_profile_d';

%% 2. 线路参数修正
% r、x、b:MATPOWER branch表中的电阻、电抗和线路充电电纳。
params.BranchScale = struct();
params.BranchScale.r = 7/4;
params.BranchScale.x = 7/4;
params.BranchScale.b = 4/7;

%% 3. 同步机与变流器基础参数
% Xd_Gen:同步机暂态电抗。
% GenCostLoading:构造同步机固定成本项，现在5%出力时的成本为固定成本。
params.Xd_Gen = 0.04;
params.GenCostLoading = 0.05;

% Gen_Pmin_MW为同步机最小有功出力，当前沿用5%额定出力。
params.Gen_Pmin_MW = 0.05*mpc.gen(:,9);

% GenCostBreakpoints为归一化同步机出力的分段透视割切点。
params.GenCostBreakpoints = 0:0.1:1;

% UC参数按同步机额定功率和固定运行成本统一生成。
% 上、下爬坡速率均为0.2倍额定功率，最小开、停机时段数均为3。
% 单次启动、停机成本分别为固定运行成本c^(G)_g的2倍和0.5倍。
gen_fixed_cost = mpc.gencost(:,5).*((params.GenCostLoading*mpc.gen(:,9)).^2) + ...
    mpc.gencost(:,6).*(params.GenCostLoading*mpc.gen(:,9));
params.UC = struct();
params.UC.RampUp_Rate_MW_per_Hour   = 0.2*mpc.gen(:,9);
params.UC.RampDown_Rate_MW_per_Hour = 0.2*mpc.gen(:,9);
params.UC.MinUp_Periods              = 3*ones(size(mpc.gen,1),1);
params.UC.MinDown_Periods            = 3*ones(size(mpc.gen,1),1);
params.UC.Startup_Cost               = 2*gen_fixed_cost;
params.UC.Shutdown_Cost              = 0.5*gen_fixed_cost;

% GFL_WG用于显式记录已建GFL-WG场站参数。
% PN_MW可以为标量、与GFL_Built_Nodes等长的向量，或全节点向量。
% Curtailment_Cost_per_MWh为单位弃风惩罚成本，单位为$/MWh。
params.GFL_WG = struct();
params.GFL_WG.PN_MW = 60;
params.GFL_WG.I_Post_Multiplier = 3;
params.GFL_WG.Curtailment_Cost_per_MWh = 30;

%% 4. GFM-ES规划参数
% GFM_Candidates:允许投建GFM-ES的节点集合。
params.GFM_Candidates = [9, 15, 19];

% GFL_Built_Nodes:已建GFL节点集合。
params.GFL_Built_Nodes = [11, 18];

% GFM_Modules定义模块化GFM-ES参数表。
params.GFM_Modules = struct();
params.GFM_Modules.MaxModulesPerCandidate = 2;
params.GFM_Modules.N_Module_Max           = 4;
params.GFM_Modules.EnforceSequentialBuild = true;
params.GFM_Modules.Bus           = [9, 9, 15, 15, 19, 19];
params.GFM_Modules.ModuleIndex   = [1, 2, 1, 2, 1, 2];

% 额定功率与单位功率成本
params.GFM_Modules.PN_MW         = [30, 30, 30, 30, 30, 30];
params.GFM_Modules.Annual_Cost_Power_per_MW = ...
    [9600, 9600, 9600, 9600, 9600, 9600];

% 储能参数：当前采用保守默认值，后续可按实际设备参数替换。
% 每个模块额定储存能量为60 MWh，充电效率和放电效率均为0.9。
params.GFM_Modules.Rated_Energy_MWh = 2*params.GFM_Modules.PN_MW;
params.GFM_Modules.Annual_Cost_Energy_per_MWh = ...
    [37120, 37120, 37120, 37120, 37120, 37120];
% params.GFM_Modules.Annual_Cost_Energy_per_MWh = zeros(1,6);

% SOC上限、初始值和下限分别为0.9、0.5和0.1。
params.GFM_Modules.Charge_Efficiency    = 0.9;
params.GFM_Modules.Discharge_Efficiency = 0.9;
params.GFM_Modules.SOC_Max              = 0.9;
params.GFM_Modules.SOC_Initial          = 0.5;
params.GFM_Modules.SOC_Min              = 0.1;

% 投建GFM-ES的总成本
params.GFM_Modules.Cost_Conv_GFM = ...
    params.GFM_Modules.Annual_Cost_Power_per_MW .* params.GFM_Modules.PN_MW + ...
    params.GFM_Modules.Annual_Cost_Energy_per_MWh .* params.GFM_Modules.Rated_Energy_MWh;

% 故障电流倍数
params.GFM_Modules.I_Post_Multiplier = [3, 3, 3, 3, 3, 3];

% 运行与虚拟阻抗：设备级标幺值->系统级标幺值
params.GFM_Modules.X_GFM_res = [0.04, 0.04, 0.04, 0.04, 0.04, 0.04];
params.GFM_Modules.X_GFM_vir = (1./params.GFM_Modules.I_Post_Multiplier - ...
    params.GFM_Modules.X_GFM_res)*params.base_MVA./params.GFM_Modules.PN_MW;
params.GFM_Modules.X_GFM_res        = params.GFM_Modules.X_GFM_res*...
    params.base_MVA./params.GFM_Modules.PN_MW;

%% 5. 确定性逐时负荷与GFL-WG可用出力
% 逐时数据按[节点,典型日,时段]三维数组保存。
% 负荷采用MOST的12时段确定性系统负荷曲线相对其基准负荷的变化倍率。
% GFL-WG采用MOST的12时段确定性风电出力倍率，各已建场站共用同一条曲线。
D = params.MultipleSnapshot.TypicalDayCount;
T = params.MultipleSnapshot.PeriodCount;
typical_day_factor = params.MultipleSnapshot.Factor;

% 每个典型日均应分别给定GFL-WG可用出力倍率和负荷倍率。
if ~isequal(size(typical_day_factor), [D, 2])
    error('MultipleSnapshot.Factor的维度应为TypicalDayCount×2，即%d×2。',D);
end
if any(~isfinite(typical_day_factor(:))) || any(typical_day_factor(:) <= 0)
    error('MultipleSnapshot.Factor中的GFL-WG可用出力倍率和负荷倍率均应为有限正数。');
end

% ex_load_profile配套的MOST基准算例为ex_case3b。
% 各时段负荷倍率等于MOST逐时系统负荷除以MOST系统基准负荷。
MOST_load_profile = ex_load_profile;
MOST_base_case    = loadcase('ex_case3b');
MOST_load_base_MW = total_load(MOST_base_case.bus,MOST_base_case.gen);
load_total_MW     = MOST_load_profile.values(:,1,1);
load_factor       = load_total_MW/MOST_load_base_MW;
for i = 1:size(load_factor,1)/2
    temp = load_factor(i);
    load_factor(i) = load_factor(size(load_factor,1)+1-i);
    load_factor(size(load_factor,1)+1-i) = temp;
end
clear temp
load_node_period  = mpc.bus(:,3)*load_factor.';
params.MultipleSnapshot.LoadFactor = load_factor;
% Factor第二列用于逐典型日缩放负荷，得到[节点,典型日,时段]三维数据。
params.MultipleSnapshot.Load_P_MW = ...
    reshape(load_node_period, size(mpc.bus,1), 1, T).* ...
    reshape(typical_day_factor(:,2), 1, D, 1);

% ex_wind_profile_d中的values为风电机组额定功率的确定性可用出力倍率。
MOST_wind_profile     = ex_wind_profile_d;
wind_available_factor = MOST_wind_profile.values(:,1,1);
for i = 1:size(wind_available_factor,1)/2
    temp = wind_available_factor(i);
    wind_available_factor(i) = wind_available_factor(size(wind_available_factor,1)+1-i);
    wind_available_factor(size(wind_available_factor,1)+1-i) = temp;
end
clear temp
GFL_rated_node        = zeros(size(mpc.bus,1),1);
GFL_rated_node(params.GFL_Built_Nodes) = params.GFL_WG.PN_MW;
GFL_node_period = GFL_rated_node*wind_available_factor.';
% Factor第一列用于逐典型日缩放GFL-WG可用出力，保持各场站日内曲线形状不变。
params.MultipleSnapshot.GFL_Available_P_MW = ...
    reshape(GFL_node_period, size(mpc.bus,1), 1, T).* ...
    reshape(typical_day_factor(:,1), 1, D, 1);

%% 6. 安全约束参数
% I_limit_kA:短路电流上限，单位为kA，可以为标量或全节点向量。
params.I_limit_kA = 12.25;

% SCR_min:经典短路比下限，无量纲。
params.SCR_min = 3;

% Require_Source_Online:是否要求每个时刻至少一个同步机或GFM-ES模块投运/投建。
params.Require_Source_Online = false;

%% 7. 求解器与数值参数
% KZ:放大阻抗元素，改善数值稳健性。
params.KZ = 1e3;

% ZBoundMargin:枚举离散投运组合估计Z元素上下界时保留的安全裕度。
params.ZBoundMargin = 0.005;

% ERR_TOL_FACTOR:会乘以KZ得到阻抗矩阵约束的绝对容差。
params.ERR_TOL_FACTOR = 1e-6;

%% 8. 求解性能参数
% 日常开发采用0.5%%相对间隙和10分钟时限；最终论文算例可单独收紧。
params.Solver = struct();
params.Solver.Threads = 14;
params.Solver.MIPGap = 0.005;
params.Solver.TimeLimit = 600;
params.Solver.MIPFocus = 1;
params.Solver.Heuristics = 0.2;
params.Solver.NoRelHeurWork = 0;
% 将年成本目标缩放到约10的数量级，不改变最优解与原始成本输出。
params.Solver.ObjectiveScale = 1e5;
% 仅在算例维度与模块顺序完全兼容时读取最近一次成功结果的整数解。
params.Solver.UseLatestMIPStart = false;

% 两阶段求解：第一阶段优先寻找高质量可行解，第二阶段利用该解强化下界并证明最优性。
% 第二阶段允许0.5%的相对最优性间隙，并采用两路并发MIP搜索降低搜索路径偶然性。
% 若达到3600秒时限仍有更大间隙，程序会保存当前最优可行解及其最优性间隙。
params.Solver.TwoStage = struct();
params.Solver.TwoStage.Enabled = true;
params.Solver.TwoStage.Stage1 = struct( ...
    'Name', 'feasible-search', ...
    'TimeLimit', 1800, ...
    'MIPGap', 0.005, ...
    'MIPFocus', 1, ...
    'Heuristics', 0.2);
params.Solver.TwoStage.Stage2 = struct( ...
    'Name', 'optimality-proof', ...
    'TimeLimit', 7200, ...
    'MIPGap', 0.005, ...
    'MIPFocus', 3, ...
    'Heuristics', 0.01, ...
    'ConcurrentMIP', 2);

%% 9. 写出JSON文件
json_text = jsonencode(params, 'PrettyPrint', true);

fid = fopen(output_file, 'w', 'n', 'UTF-8');
if fid < 0
    error('Cannot open parameter output file: %s', output_file);
end
fprintf(fid, '%s\n', json_text);
fclose(fid);

fprintf('已生成参数文件：%s\n', output_file);

%% 10. 清除本脚本生成的变量
clear D T ans fid gen_fixed_cost GFL_node_period GFL_rated_node json_text load_node_period ...
    load_factor load_total_MW MOST_base_case MOST_load_base_MW ...
    MOST_load_profile MOST_wind_profile output_file param_dir params ...
    typical_day_factor wind_available_factor
