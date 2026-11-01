%% 生成多时段GFM-ES配置案例的默认参数文件
% 本脚本是供阅读和维护的参数脚本。
% 修改参数时，直接修改本脚本即可，作为桥梁的JSON文件会在本脚本运行后自动生成。

clear params;
% 指定输出文件
Parameter_Directory = fileparts(mfilename('fullpath'));
addpath(fullfile(fileparts(fileparts(Parameter_Directory)), ...
    'code', 'functions', 'io'));
Output_File = fullfile(Parameter_Directory, 'multiple_snapshot_default_params.json');

%% 0. 读取MATPOWER基准案例
mpc = case30;

%% 1. 网络参数

params.Network = struct();
% 网络基准量
params.Network.mpc = mpc;
params.Network.Base_MVA = mpc.baseMVA;
params.Network.Base_kV = mpc.bus(1, 10);
params.Network.Base_kA = params.Network.Base_MVA /params.Network.Base_kV/sqrt(3);
params.Network.Base_O = params.Network.Base_kV^2/params.Network.Base_MVA;
% 线路修正参数
params.Network.Branch_Scale = struct('x', 7/4);

%% 2. 同步机参数

Generator_Buses = [1; 2; 22; 27; 23; 13];
if ~isequal(mpc.gen(:, 1), Generator_Buses)
    error('case30同步机顺序与默认SG、UC参数的机组顺序不一致。');
end

% SG与UC中的机组参数均按mpc.gen的行顺序给定。
params.SG = struct();
params.SG.Xd_Gen = 0.10*ones(size(mpc.gen, 1), 1); % 所有SG次暂态电抗直接按系统基准给定
params.SG.Gen_Cost_Breakpoints = 0:0.1:1;          % 分段透视割法参数
params.SG.Gen_Pmin_MW = [20; 20; 10; 11; 6; 8];

%% 3. 机组组合参数

% UC参数
params.UC = struct();
params.UC.Ramp_Up_Rate_MW_per_Hour = [20; 20; 10; 11; 6; 8];
params.UC.Ramp_Down_Rate_MW_per_Hour = [24; 24; 18; 20; 12; 14];
params.UC.Min_Up_Periods = [4; 4; 4; 4; 2; 4];
params.UC.Min_Down_Periods = [4; 4; 2; 2; 2; 2];
Gen_Cost_Full_Load = mpc.gencost(:, 5).*mpc.gen(:, 9).^2 + ...
    mpc.gencost(:, 6).*mpc.gen(:, 9) + mpc.gencost(:, 7);
params.UC.Startup_Cost = 0.5 *Gen_Cost_Full_Load;
params.UC.Shutdown_Cost = 0.05*Gen_Cost_Full_Load;

clear Gen_Cost_Full_Load Generator_Buses;

%% 4. 跟网型风电参数

params.GFL_WG = struct();

% 已建GFL-WG场站
params.GFL_WG.Built_Nodes = 11;
% GFL-WG额定功率
params.GFL_WG.PN_MW = 60;
% GFL-WG弃风成本参数
params.GFL_WG.Curtailment_Cost_per_MWh = 30;

% GFL-WG的LVRT参数
params.GFL_WG.LVRT.K_Q = 1.5;
params.GFL_WG.LVRT.I_N_Rated = 1.0;
params.GFL_WG.LVRT.V_LVRT_On = 0.9;
params.GFL_WG.LVRT.V_LVRT_Sat = 0.2;
params.GFL_WG.LVRT.Delta_I_Rated = params.GFL_WG.LVRT.K_Q*params.GFL_WG.LVRT.I_N_Rated*...
    (params.GFL_WG.LVRT.V_LVRT_On-params.GFL_WG.LVRT.V_LVRT_Sat);

%% 5. 构网型储能参数

params.GFM_ES = struct();

% GFM-ES的规划参数
params.GFM_ES.Planning = struct();
params.GFM_ES.Planning.Max_Units_Per_Bus = 2;
params.GFM_ES.Planning.Max_Installed_Units = 4;
params.GFM_ES.Planning.Enforce_Sequential_Build = true; % 同节点相同GFM-ES优先选取较小编号

% GFM-ES的候选节点与电气参数
params.GFM_ES.Unit = struct();
params.GFM_ES.Unit.Bus = [6, 6; 10, 10; 16, 16];
params.GFM_ES.Unit.PN_MW = 30*ones(size(params.GFM_ES.Unit.Bus));
params.GFM_ES.Unit.Energy_MWh = 2*params.GFM_ES.Unit.PN_MW; % 2对应2h额定持续时间
params.GFM_ES.Unit.I_Post_Multiplier = 1.5*ones(size(params.GFM_ES.Unit.Bus));
x_GFM_Res_Device = 0.05*ones(size(params.GFM_ES.Unit.Bus));
params.GFM_ES.Unit.X_GFM = x_GFM_Res_Device.*...
    params.Network.Base_MVA./params.GFM_ES.Unit.PN_MW;
params.GFM_ES.Unit.X_GFM_Vir = (1./params.GFM_ES.Unit.I_Post_Multiplier-x_GFM_Res_Device).*...
    params.Network.Base_MVA./params.GFM_ES.Unit.PN_MW;

% GFM-ES的充放电效率与SOC参数
params.GFM_ES.Storage = struct();
params.GFM_ES.Storage.Charge_Efficiency = 0.9;
params.GFM_ES.Storage.Discharge_Efficiency = 0.9;
params.GFM_ES.Storage.SOC_Min = 0.1;
params.GFM_ES.Storage.SOC_Initial = 0.5;
params.GFM_ES.Storage.SOC_Max = 0.9;

% GFM-ES的年固定成本参数
params.GFM_ES.Costs = struct();
params.GFM_ES.Costs.Annual_Cost_Power_per_MW = 12390*ones(size(params.GFM_ES.Unit.Bus));
params.GFM_ES.Costs.Annual_Cost_Energy_per_MWh = 37120*ones(size(params.GFM_ES.Unit.Bus));

clear x_GFM_Res_Device;

%% 6. 安全约束参数

params.Security = struct();
% 配置风电场景曲线
params.Security.Consider_Wind_Uncertainty = 1; % 1:多场景曲线; 0:单场景曲线。
% SCR下限与SCC上限约束。
params.Security.Enable_SCR = true;
params.Security.SCR_min = 2.8;
params.Security.Enable_SCC = true;
params.Security.I_limit_kA = 5.6; % kA

%% 7. 多时段与风电场景参数

% 读取固定RTS-GMLC时序输入
Data_Directory = fileparts(Parameter_Directory);
RTS_GMLC_Result_File = fullfile(Data_Directory, 'RTS-GMLC', ...
    'processed', 'rts_gmlc_profiles.mat');
if ~isfile(RTS_GMLC_Result_File)
    error('未找到指定的RTS-GMLC时序结果：%s', RTS_GMLC_Result_File);
end
load(RTS_GMLC_Result_File, 'Result');
Typical_Days = Result.Typical_Day_Sets;
Wind_Scenarios = Result.Wind_Scenario_Sets;

if ~isscalar(Typical_Days) || ~isscalar(Wind_Scenarios) || ...
        Typical_Days.D ~= 4 || Wind_Scenarios.D ~= 4 || ...
        Wind_Scenarios.K ~= 4 || ~Wind_Scenarios.Available || ...
        Result.Dimensions.Period_Count ~= 24 || ...
        Result.Dimensions.Period_Duration_Hours ~= 1 || ...
        numel(Typical_Days.Weight_Days) ~= 4 || ...
        ~isequal(size(Typical_Days.System_Load_Normalized), [4, 24]) || ...
        ~isequal(size(Wind_Scenarios.Wind_Scenario_Normalized), [4, 4, 24]) || ...
        ~isequal(size(Wind_Scenarios.Probability), [4, 4])
    error('固定RTS-GMLC输入应为单组D=4、K=4，且每日包含24个1 h时段。');
end % 此处仅检查输入的结构是否正确。

% 对风电场景曲线进行预处理
D = Typical_Days.D;
T = Result.Dimensions.Period_Count;
N = size(mpc.bus, 1);
GFL_Rated_Node = zeros(N, 1);
GFL_Rated_Node(params.GFL_WG.Built_Nodes) = params.GFL_WG.PN_MW;
K = Wind_Scenarios.K;
Wind_Scenario_Factor = Wind_Scenarios.Wind_Scenario_Normalized;
Scenario_Probabilities = Wind_Scenarios.Probability;
switch params.Security.Consider_Wind_Uncertainty
    case 0
        % 确定性模式使用四个原始场景的概率加权平均轨迹。
        Wind_Scenario_Factor = sum(Wind_Scenario_Factor.*...
            reshape(Scenario_Probabilities, D, K, 1), 2);
        K = 1;
        Scenario_Probabilities = ones(D, 1);
    case 1
        % 保留四个原始风电场景及其概率。
    otherwise
        error('Security.Consider_Wind_Uncertainty必须为0或1。');
end

% 多时段参数
params.Multiple_Snapshot = struct();
params.Multiple_Snapshot.Typical_Day_Count = D;
params.Multiple_Snapshot.Typical_Day_Weights_Days = ...
    reshape(Typical_Days.Weight_Days, 1, D);
params.Multiple_Snapshot.Period_Count = T;
params.Multiple_Snapshot.Period_Durations_Hours = ...
    Result.Dimensions.Period_Duration_Hours*ones(1, T);

% 节点负荷曲线
params.Multiple_Snapshot.Load_P_MW = reshape(mpc.bus(:, 3), N, 1, 1).*...
    reshape(Typical_Days.System_Load_Normalized, 1, D, T); % 按IEEE-30原始节点负荷映射逐时曲线

% 风电场景曲线
params.Multiple_Snapshot.Wind = struct();
params.Multiple_Snapshot.Wind.Count = K;
params.Multiple_Snapshot.Wind.Probabilities = Scenario_Probabilities;
params.Multiple_Snapshot.Wind.P_GFL_Available_Scenarios = ...
    reshape(GFL_Rated_Node, N, 1, 1, 1).* ...
    reshape(Wind_Scenario_Factor, 1, D, K, T);

clear D Data_Directory GFL_Rated_Node K N Parameter_Directory Result ...
    RTS_GMLC_Result_File Scenario_Probabilities T ...
    Typical_Days Wind_Scenario_Factor Wind_Scenarios mpc;

%% 8. 求解设置

params.Solver = struct();
% 是否启用两阶段求解
params.Solver.Two_Stage_Enabled = true;
% 数值参数
params.Solver.KZ = 1e3;
params.Solver.Z_Bound_Margin = 0.005;
params.Solver.ERR_TOL_Factor = 1e-6;
params.Solver.Objective_Scale = 1e5;
params.Solver.MIP_Gap = 0.005; % 最终相对MIP间隙

% 求解器与通用选项，Gurobi选项沿用其原生参数名
params.Solver.Name = 'gurobi';
params.Solver.Options = struct();
params.Solver.Options.YALMIP = struct('verbose', 2, 'savesolveroutput', 1);
params.Solver.Options.Gurobi = struct();
params.Solver.Options.Gurobi.Threads = 0;
params.Solver.Options.Gurobi.NoRelHeurWork = 0;
params.Solver.Options.Gurobi.DisplayInterval = 1;
params.Solver.Options.Gurobi.OutputFlag = 1;
params.Solver.Options.Gurobi.LogToConsole = 1;
params.Solver.Options.Gurobi.LogFile = fullfile('results', 'gurobi_run.log');

% 整数热启动所需的YALMIP选项
params.Solver.Options.MIP_Start.YALMIP = struct('usex0', 1, 'warmstart', 1);

% 单阶段求解参数
params.Solver.One_Stage = struct('TimeLimit', 600, 'MIPGap', ...
    params.Solver.MIP_Gap, 'MIPFocus', 1, 'Heuristics', 0.2);

% 两阶段求解参数(先搜索可行解，再收紧间隙)
params.Solver.Two_Stage = struct();
params.Solver.Two_Stage.Stage_1 = struct('Name', 'feasible-search', ...
    'TimeLimit', 300, 'MIPGap', 0.3, 'MIPFocus', 1, 'Heuristics', 0.2);
params.Solver.Two_Stage.Stage_2 = struct('Name', 'optimality-proof', ...
    'TimeLimit', 900, 'MIPGap', params.Solver.MIP_Gap, 'MIPFocus', 3, ...
    'Heuristics', 0.01, 'ConcurrentMIP', 2);

%% 9. 写出JSON文件
write_json_file(Output_File, params);
fprintf('已生成参数文件：%s\n', Output_File);

clear Output_File ans;
