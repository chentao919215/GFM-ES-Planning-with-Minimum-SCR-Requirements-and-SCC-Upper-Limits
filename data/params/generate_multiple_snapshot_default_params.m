%% 生成多时段GFM-ES配置案例的默认参数文件
% 本脚本是供人阅读和维护的参数源文件；JSON文件由本脚本自动生成。
% 修改参数时，优先修改本脚本，然后重新运行本脚本生成JSON。

clear params;
Parameter_Directory   = fileparts(mfilename('fullpath'));
Output_File = fullfile(Parameter_Directory, 'multiple_snapshot_default_params.json');

%% 0. 读取MATPOWER基准案例
mpc = case30;

%% 1. Network
% 网络基准量、线路修正及同步机网络参数。
params.Network = struct();
params.Network.mpc = mpc;
params.Network.Base_MVA = mpc.baseMVA;
params.Network.Base_kV  = mpc.bus(1, 10);
params.Network.Base_kA  = params.Network.Base_MVA / ...
    params.Network.Base_kV / sqrt(3);
params.Network.Base_O   = params.Network.Base_kV^2 / ...
    params.Network.Base_MVA;
% Manuscript Section IV-A仅将线路串联电纳缩放为4/7；等价地将x乘7/4。
% 线路电阻与并联电纳保持原始case30数据，且不进入无损安全网络。
params.Network.Branch_Scale = struct( ...
    'r', 1, ...
    'x', 7/4, ...
    'b', 1);
% 所有SG次暂态电抗直接按系统基准给定，不再由机组容量基准换算。
params.Network.Xd_Gen = 0.10 * ones(size(mpc.gen, 1), 1);
params.Network.Gen_Cost_Breakpoints = 0:0.1:1;

%% 2. GFL_WG
% 已建GFL-WG场站及其LVRT、电流和弃风成本参数。
params.GFL_WG = struct();
params.GFL_WG.Built_Nodes = 11;
params.GFL_WG.PN_MW = 60;
params.GFL_WG.Curtailment_Cost_per_MWh = 30;
params.GFL_WG.K_Q = 1.5;
params.GFL_WG.I_N_Rated  = 1.0;
params.GFL_WG.V_LVRT_On  = 0.9;
params.GFL_WG.V_LVRT_Sat = 0.2;
params.GFL_WG.Delta_I_Rated = params.GFL_WG.K_Q * ...
    params.GFL_WG.I_N_Rated * (params.GFL_WG.V_LVRT_On - ...
    params.GFL_WG.V_LVRT_Sat);

%% 3. GFM_Modules
% 模块候选位置、模块额定参数、储能参数、电气参数和成本参数。
params.GFM_Modules = struct();

params.GFM_Modules.Configurations = struct();
params.GFM_Modules.Configurations.Max_Modules_Per_Candidate = 2;
params.GFM_Modules.Configurations.Enforce_Sequential_Build = true;
params.GFM_Modules.Configurations.N_Module_Max = 4;

params.GFM_Modules.Candidates = struct();
params.GFM_Modules.Candidates.Bus = [6, 10, 16];

params.GFM_Modules.Module = struct();
params.GFM_Modules.Module.Bus = [6, 6, 10, 10, 16 16];
params.GFM_Modules.Module.Module_Index = [1, 2, 1, 2, 1, 2];
params.GFM_Modules.Module.PN_MW = 30*ones(1,6);

params.GFM_Modules.Costs = struct();
% Manuscript Section IV-A：以下两项均为包含年化投资和固定运维的年固定成本。
params.GFM_Modules.Costs.Annual_Cost_Power_per_MW   = 12390*ones(1,6);
params.GFM_Modules.Costs.Annual_Cost_Energy_per_MWh = 37120*ones(1,6);

params.GFM_Modules.Storage = struct();
params.GFM_Modules.Storage.Rated_Energy_MWh = ...
    2*params.GFM_Modules.Module.PN_MW;
params.GFM_Modules.Storage.Charge_Efficiency = 0.9;
params.GFM_Modules.Storage.Discharge_Efficiency = 0.9;
params.GFM_Modules.Storage.SOC_Max = 0.9;
params.GFM_Modules.Storage.SOC_Initial = 0.5;
params.GFM_Modules.Storage.SOC_Min = 0.1;

params.GFM_Modules.Electrical = struct();
params.GFM_Modules.Electrical.I_Post_Multiplier = 1.5*ones(1,6);
% X_GFM_Res先按设备基准输入，再换算为系统基准。
x_GFM_Res_Device = 0.05*ones(1,6);
params.GFM_Modules.Electrical.X_GFM_Vir = ...
    (1 ./ params.GFM_Modules.Electrical.I_Post_Multiplier - ...
    x_GFM_Res_Device) .* params.Network.Base_MVA ./ ...
    params.GFM_Modules.Module.PN_MW;
params.GFM_Modules.Electrical.X_GFM_Res = ...
    x_GFM_Res_Device .* params.Network.Base_MVA ./ ...
    params.GFM_Modules.Module.PN_MW;

%% 4. Security
% 短路电流上限、SCR下限及源在线约束。
params.Security = struct();
params.Security.Enable_SCC = true;
params.Security.Enable_SCR = true;
params.Security.I_limit_kA = 5.7; % kA
params.Security.SCR_min = 2.8;
params.Security.Require_Source_Online = true;

%% 5. Multiple_Snapshot
% 典型日、时段、负荷曲线以及风电场景参数。
params.Multiple_Snapshot = struct();

Data_Directory = fileparts(Parameter_Directory);
RTS_GMLC_Run_Directory = fullfile(Data_Directory, 'RTS-GMLC', ...
    'processed', 'rts_gmlc_v0.2.3_fixed_extreme_medoids', ...
    'run_20260822_162606');
RTS_GMLC_Result_File = fullfile(RTS_GMLC_Run_Directory, ...
    'rts_gmlc_typical_days_and_wind_scenarios_20260822_162606.mat');
if ~isfile(RTS_GMLC_Result_File)
    error('未找到指定的RTS-GMLC时序结果：%s', RTS_GMLC_Result_File);
end
load(RTS_GMLC_Result_File, 'Result');

Selected_D = 4;
Selected_K = 4;
D_Index = find([Result.Typical_Day_Sets.D] == Selected_D, 1);
if isempty(D_Index)
    error('指定的RTS-GMLC时序结果中不存在D=%d的典型日。', Selected_D);
end
Typical_Days = Result.Typical_Day_Sets(D_Index);
Scenario_Row = Result.Wind_Scenario_Sets(D_Index, :);
K_Index = find([Scenario_Row.K] == Selected_K, 1);
if isempty(K_Index)
    error('指定的RTS-GMLC时序结果中不存在D=%d、K=%d的风电场景。', ...
        Selected_D, Selected_K);
end
Wind_Scenarios = Scenario_Row(K_Index);
if ~Wind_Scenarios.Available
    error('指定的D=%d、K=%d风电场景不可用：%s', ...
        Selected_D, Selected_K, Wind_Scenarios.Unavailable_Reason);
end

D = Typical_Days.Total_Typical_Day_Count;
K = Wind_Scenarios.K;
T = Result.Dimensions.Period_Count;
Load_Factor = Typical_Days.System_Load_Normalized;
Wind_DA_Factor = Typical_Days.Wind_DA_System_Normalized;
Wind_Scenario_Factor = Wind_Scenarios.Wind_Scenario_Normalized;
Scenario_Probabilities = Wind_Scenarios.Probability;

if D ~= Selected_D || K ~= Selected_K || T ~= 24 || ...
        Result.Dimensions.Period_Duration_Hours ~= 1
    error('指定时序数据应满足D=4、K=4且每个典型日包含24个1 h时段。');
end
if ~isequal(size(Load_Factor), [D, T]) || ...
        ~isequal(size(Wind_DA_Factor), [D, T]) || ...
        ~isequal(size(Wind_Scenario_Factor), [D, K, T]) || ...
        ~isequal(size(Scenario_Probabilities), [D, K])
    error('指定RTS-GMLC典型日或风电场景数据的维度与D、K、T不一致。');
end
if any(~isfinite(Load_Factor(:))) || any(Load_Factor(:) < 0) || ...
        any(~isfinite(Wind_DA_Factor(:))) || any(Wind_DA_Factor(:) < 0) || ...
        any(~isfinite(Wind_Scenario_Factor(:))) || ...
        any(Wind_Scenario_Factor(:) < 0)
    error('指定RTS-GMLC负荷与风电时序应为有限非负数。');
end
if any(~isfinite(Scenario_Probabilities(:))) || ...
        any(Scenario_Probabilities(:) <= 0) || ...
        any(abs(sum(Scenario_Probabilities, 2) - 1) > 1e-12)
    error('指定RTS-GMLC风电场景概率应为正数且逐典型日合计为1。');
end
if any(Typical_Days.Weight_Days <= 0) || ...
        sum(Typical_Days.Weight_Days) ~= 365
    error('指定RTS-GMLC典型日权重应为正数且合计为365天。');
end

params.Multiple_Snapshot.Time = struct();
params.Multiple_Snapshot.Time.Typical_Day_Count = D;
params.Multiple_Snapshot.Time.Period_Count = T;
params.Multiple_Snapshot.Time.Typical_Day_Weights_Days = ...
    reshape(Typical_Days.Weight_Days, 1, D);
params.Multiple_Snapshot.Time.Period_Durations_Hours = ...
    Result.Dimensions.Period_Duration_Hours * ones(1, T);

params.Multiple_Snapshot.Profiles = struct();
% 指定时序不再使用典型日标量缩放，保留空字段以满足现有公开参数接口。
params.Multiple_Snapshot.Profiles.Factor = [];
params.Multiple_Snapshot.Profiles.Load_Factor = Load_Factor;
params.Multiple_Snapshot.Profiles.Load_P_MW = ...
    reshape(mpc.bus(:, 3), size(mpc.bus, 1), 1, 1) .* ...
    reshape(Load_Factor, 1, D, T);

GFL_Rated_Node = zeros(size(mpc.bus, 1), 1);
GFL_Rated_Node(params.GFL_WG.Built_Nodes) = params.GFL_WG.PN_MW;
% 确定性基准接口采用典型日的日前风电曲线。
params.Multiple_Snapshot.Profiles.GFL_Available_P_MW = ...
    reshape(GFL_Rated_Node, size(mpc.bus, 1), 1, 1) .* ...
    reshape(Wind_DA_Factor, 1, D, T);

params.Multiple_Snapshot.Wind_Scenarios = struct();
params.Multiple_Snapshot.Wind_Scenarios.Count = K;
params.Multiple_Snapshot.Wind_Scenarios.Names = ...
    arrayfun(@(k) sprintf('scenario_%d', k), 1:K, ...
    'UniformOutput', false);
params.Multiple_Snapshot.Wind_Scenarios.Probabilities = ...
    Scenario_Probabilities;
params.Multiple_Snapshot.Wind_Scenarios.Generation_Mode = 'explicit';
params.Multiple_Snapshot.Wind_Scenarios.P_GFL_Available_Scenarios = ...
    reshape(GFL_Rated_Node, size(mpc.bus, 1), 1, 1, 1) .* ...
    reshape(Wind_Scenario_Factor, 1, D, K, T);

%% 6. UC
% 同步机最小出力、爬坡、最小开停机时间和启停成本。
params.UC = struct();
UC_Generator_Buses = [1; 2; 22; 27; 23; 13];
if ~isequal(mpc.gen(:, 1), UC_Generator_Buses)
    error('case30同步机顺序与算例表2不一致。');
end
params.UC.Gen_Pmin_MW = [20; 20; 10; 11; 6; 8];
params.UC.Ramp_Up_Rate_MW_per_Hour = [20; 20; 10; 11; 6; 8];
params.UC.Ramp_Down_Rate_MW_per_Hour = [24; 24; 18; 20; 12; 14];
params.UC.Min_Up_Periods = [4; 4; 4; 4; 2; 4];
params.UC.Min_Down_Periods = [4; 4; 2; 2; 2; 2];
Gen_Cost_Full_Load = mpc.gencost(:, 5) .* mpc.gen(:, 9).^2 + ...
    mpc.gencost(:, 6) .* mpc.gen(:, 9) + mpc.gencost(:, 7);
params.UC.Startup_Cost = 0.5 * Gen_Cost_Full_Load;
params.UC.Shutdown_Cost = 0.05 * Gen_Cost_Full_Load;

%% 7. Solver
% 数值稳定性、求解性能及两阶段求解参数。
params.Solver = struct();
params.Solver.KZ = 1e3;
params.Solver.Z_Bound_Margin = 0.005;
params.Solver.ERR_TOL_Factor = 1e-6;
params.Solver.MIP_Gap = 0.005; % 两阶段流程的共同目标间隙，仅用于流程判断
params.Solver.Objective_Scale = 1e5;
params.Solver.Two_Stage = struct();
params.Solver.Two_Stage.Enabled = true;
params.Solver.Two_Stage.Stage_1 = struct('Name', 'feasible-search', ...
    'Time_Limit', 300, 'MIP_Gap', 0.3);
params.Solver.Two_Stage.Stage_2 = struct('Name', 'optimality-proof', ...
    'Time_Limit', 1800, 'MIP_Gap', 0.005);

% 求解器固定为Gurobi，按其原生参数配置求解选项。
params.solver = struct();
params.solver.name = 'gurobi';
params.solver.options = struct();
params.solver.options.yalmip = struct('verbose', 2, 'savesolveroutput', 1);

% Gurobi专属选项。
params.solver.options.gurobi = struct();
params.solver.options.gurobi.Threads = 0;
params.solver.options.gurobi.MIPGap = 0.005;
params.solver.options.gurobi.TimeLimit = 600;
params.solver.options.gurobi.MIPFocus = 1;
params.solver.options.gurobi.Heuristics = 0.2;
params.solver.options.gurobi.NoRelHeurWork = 0;
params.solver.options.gurobi.DisplayInterval = 1;
params.solver.options.gurobi.OutputFlag = 1;
params.solver.options.gurobi.LogToConsole = 1;
params.solver.options.gurobi.LogFile = fullfile('results', 'gurobi_run.log');

% 仅在提供MIP start时启用对应的YALMIP初始解选项。
params.solver.options.mip_start = struct();
params.solver.options.mip_start.yalmip = struct('usex0', 1, 'warmstart', 1);

% 长时间后台运行时使用的Gurobi静默输出选项。
params.solver.options.quiet = struct();
params.solver.options.quiet.yalmip = struct('verbose', 0);
params.solver.options.quiet.gurobi = struct( ...
    'OutputFlag', 0, 'LogToConsole', 0, 'LogFile', '');
% 两阶段覆盖使用Gurobi原生参数。
params.Solver.Two_Stage.Stage_1.Options = struct();
params.Solver.Two_Stage.Stage_1.Options.gurobi = struct( ...
    'TimeLimit', 300, 'MIPGap', 0.3, 'MIPFocus', 1, 'Heuristics', 0.2);
params.Solver.Two_Stage.Stage_2.Options = struct();
params.Solver.Two_Stage.Stage_2.Options.gurobi = struct( ...
    'TimeLimit', 1800, 'MIPGap', 0.005, 'MIPFocus', 3, ...
    'Heuristics', 0.01, 'ConcurrentMIP', 2);

%% 8. 写出JSON文件
JSON_Text = jsonencode(params, 'PrettyPrint', true);
fid = fopen(Output_File, 'w', 'n', 'UTF-8');
if fid < 0
    error('Cannot open parameter output file: %s', Output_File);
end
fprintf(fid, '%s\n', JSON_Text);
fclose(fid);
fprintf('已生成参数文件：%s\n', Output_File);

%% 9. 清除本脚本生成的临时变量
clear D D_Index Data_Directory K K_Index Selected_D Selected_K T ans fid ...
    Gen_Cost_Full_Load GFL_Rated_Node JSON_Text Load_Factor ...
    Output_File Parameter_Directory params Result RTS_GMLC_Result_File ...
    RTS_GMLC_Run_Directory Scenario_Probabilities Scenario_Row ...
    Typical_Days UC_Generator_Buses Wind_DA_Factor ...
    Wind_Scenario_Factor Wind_Scenarios x_GFM_Res_Device mpc
