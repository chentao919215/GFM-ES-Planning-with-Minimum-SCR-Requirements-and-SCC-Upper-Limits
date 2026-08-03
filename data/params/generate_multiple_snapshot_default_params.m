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
params.Network.Branch_Scale = struct( ...
    'r', 7/4, ...
    'x', 7/4, ...
    'b', 4/7);
params.Network.Xd_Gen = 0.04;
params.Network.Gen_Cost_Breakpoints = 0:0.1:1;

%% 2. GFL_WG
% 已建GFL-WG场站及其LVRT、电流和弃风成本参数。
params.GFL_WG = struct();
params.GFL_WG.Built_Nodes = [11, 18];
params.GFL_WG.PN_MW = 60;
params.GFL_WG.Curtailment_Cost_per_MWh = 30;
params.GFL_WG.K_Q = 1.5;
params.GFL_WG.I_N_Rated = 1.0;
params.GFL_WG.V_LVRT_On = 0.9;
params.GFL_WG.V_LVRT_Sat = 0.2;
params.GFL_WG.Delta_I_Rated = 1.05;

%% 3. GFM_Modules
% 模块候选位置、模块额定参数、储能参数、电气参数和成本参数。
params.GFM_Modules = struct();

params.GFM_Modules.Configurations = struct();
params.GFM_Modules.Configurations.Max_Modules_Per_Candidate = 2;
params.GFM_Modules.Configurations.Enforce_Sequential_Build = true;
params.GFM_Modules.Configurations.N_Module_Max = 4;

params.GFM_Modules.Candidates = struct();
params.GFM_Modules.Candidates.Bus = [9, 15, 19];

params.GFM_Modules.Module = struct();
params.GFM_Modules.Module.Bus = [9, 9, 15, 15, 19, 19];
params.GFM_Modules.Module.Module_Index = [1, 2, 1, 2, 1, 2];
params.GFM_Modules.Module.PN_MW = [30, 30, 30, 30, 30, 30];

params.GFM_Modules.Costs = struct();
params.GFM_Modules.Costs.Annual_Cost_Power_per_MW = ...
    [9600, 9600, 9600, 9600, 9600, 9600];
params.GFM_Modules.Costs.Annual_Cost_Energy_per_MWh = ...
    [37120, 37120, 37120, 37120, 37120, 37120];

params.GFM_Modules.Storage = struct();
params.GFM_Modules.Storage.Rated_Energy_MWh = ...
    2 * params.GFM_Modules.Module.PN_MW;
params.GFM_Modules.Storage.Charge_Efficiency = 0.9;
params.GFM_Modules.Storage.Discharge_Efficiency = 0.9;
params.GFM_Modules.Storage.SOC_Max = 0.9;
params.GFM_Modules.Storage.SOC_Initial = 0.5;
params.GFM_Modules.Storage.SOC_Min = 0.1;

params.GFM_Modules.Electrical = struct();
params.GFM_Modules.Electrical.I_Post_Multiplier = [3, 3, 3, 3, 3, 3];
% X_GFM_res先按设备基准输入，再换算为系统基准。
x_GFM_Res_Device = [0.04, 0.04, 0.04, 0.04, 0.04, 0.04];
params.GFM_Modules.Electrical.X_GFM_vir = ...
    (1 ./ params.GFM_Modules.Electrical.I_Post_Multiplier - ...
    x_GFM_Res_Device) .* params.Network.Base_MVA ./ ...
    params.GFM_Modules.Module.PN_MW;
params.GFM_Modules.Electrical.X_GFM_res = ...
    x_GFM_Res_Device .* params.Network.Base_MVA ./ ...
    params.GFM_Modules.Module.PN_MW;

%% 4. Security
% 短路电流上限、SCR下限及源在线约束。
params.Security = struct();
params.Security.I_limit_kA = 12.25;
params.Security.SCR_min = 3;
params.Security.Require_Source_Online = true;

%% 5. Multiple_Snapshot
% 典型日、时段、负荷曲线以及风电场景参数。
params.Multiple_Snapshot = struct();

params.Multiple_Snapshot.Time = struct();
params.Multiple_Snapshot.Time.Typical_Day_Count = 3;
params.Multiple_Snapshot.Time.Period_Count = 12;
params.Multiple_Snapshot.Time.Typical_Day_Weights_Days = [255, 55, 55];
params.Multiple_Snapshot.Time.Period_Durations_Hours = 2 * ones(1, 12);

params.Multiple_Snapshot.Profiles = struct();
% Factor每行对应一个典型日，每列分别对应GFL-WG出力和负荷。
params.Multiple_Snapshot.Profiles.Factor = [1.0, 1.0; ...
                                             1.1, 0.9; ...
                                             0.9, 1.0];

params.Multiple_Snapshot.Wind_Scenarios = struct();
params.Multiple_Snapshot.Wind_Scenarios.Count = 3;
params.Multiple_Snapshot.Wind_Scenarios.Names = {'low', 'base', 'high'};
params.Multiple_Snapshot.Wind_Scenarios.Probabilities = [0.25, 0.50, 0.25];
params.Multiple_Snapshot.Wind_Scenarios.Scale_Factors = [0.8, 1.0, 1.2];
params.Multiple_Snapshot.Wind_Scenarios.Generation_Mode = 'scale_base_profiles';

% 由MOST示例曲线生成确定性逐时基准数据。
D = params.Multiple_Snapshot.Time.Typical_Day_Count;
T = params.Multiple_Snapshot.Time.Period_Count;
Typical_Day_Factor = params.Multiple_Snapshot.Profiles.Factor;
if ~isequal(size(Typical_Day_Factor), [D, 2])
    error(['Multiple_Snapshot.Profiles.Factor的维度应为', ...
        'Typical_Day_Count×2，即%d×2。'], D);
end
if any(~isfinite(Typical_Day_Factor(:))) || any(Typical_Day_Factor(:) <= 0)
    error('Multiple_Snapshot.Profiles.Factor中的缩放因子应为有限正数。');
end

MOST_Load_Profile = ex_load_profile;
MOST_Base_Case = loadcase('ex_case3b');
MOST_Load_Base_MW = total_load(MOST_Base_Case.bus, MOST_Base_Case.gen);
Load_Total_MW = MOST_Load_Profile.values(:, 1, 1);
Load_Factor = Load_Total_MW / MOST_Load_Base_MW;
for i = 1:size(Load_Factor, 1) / 2
    temp = Load_Factor(i);
    Load_Factor(i) = Load_Factor(end + 1 - i);
    Load_Factor(end + 1 - i) = temp;
end
Load_Node_Period = mpc.bus(:, 3) * Load_Factor.';
params.Multiple_Snapshot.Profiles.Load_Factor = Load_Factor;
params.Multiple_Snapshot.Profiles.Load_P_MW = ...
    reshape(Load_Node_Period, size(mpc.bus, 1), 1, T) .* ...
    reshape(Typical_Day_Factor(:, 2), 1, D, 1);

MOST_Wind_Profile = ex_wind_profile_d;
Wind_Available_Factor = MOST_Wind_Profile.values(:, 1, 1);
for i = 1:size(Wind_Available_Factor, 1) / 2
    temp = Wind_Available_Factor(i);
    Wind_Available_Factor(i) = Wind_Available_Factor(end + 1 - i);
    Wind_Available_Factor(end + 1 - i) = temp;
end
GFL_Rated_Node = zeros(size(mpc.bus, 1), 1);
GFL_Rated_Node(params.GFL_WG.Built_Nodes) = params.GFL_WG.PN_MW;
GFL_Node_Period = GFL_Rated_Node * Wind_Available_Factor.';
params.Multiple_Snapshot.Profiles.GFL_Available_P_MW = ...
    reshape(GFL_Node_Period, size(mpc.bus, 1), 1, T) .* ...
    reshape(Typical_Day_Factor(:, 1), 1, D, 1);

%% 6. UC
% 同步机最小出力、爬坡、最小开停机时间和启停成本。
params.UC = struct();
params.UC.Cost_Loading = 0.05;
params.UC.Gen_Pmin_MW = 0.2 * mpc.gen(:, 9);
Gen_Cost_At_5_Pct = mpc.gencost(:, 5) .* ...
    (params.UC.Cost_Loading * mpc.gen(:, 9)).^2 + ...
    mpc.gencost(:, 6) .* ...
    (params.UC.Cost_Loading * mpc.gen(:, 9));
params.UC.Ramp_Up_Rate_MW_per_Hour = 0.2 * mpc.gen(:, 9);
params.UC.Ramp_Down_Rate_MW_per_Hour = 0.2 * mpc.gen(:, 9);
params.UC.Min_Up_Periods = ones(size(mpc.gen, 1), 1);
params.UC.Min_Down_Periods = ones(size(mpc.gen, 1), 1);
params.UC.Startup_Cost = 1.0 * Gen_Cost_At_5_Pct;
params.UC.Shutdown_Cost = 0.25 * Gen_Cost_At_5_Pct;

%% 7. Solver
% 数值稳定性、Gurobi性能及两阶段求解参数。
params.Solver = struct();
params.Solver.KZ = 1e3;
params.Solver.Z_Bound_Margin = 0.005;
params.Solver.ERR_TOL_Factor = 1e-6;
params.Solver.Threads = 0;
params.Solver.MIP_Gap = 0.005;
params.Solver.Time_Limit = 600;
params.Solver.MIP_Focus = 1;
params.Solver.Heuristics = 0.2;
params.Solver.No_Rel_Heur_Work = 0;
params.Solver.Objective_Scale = 1e5;
params.Solver.Two_Stage = struct();
params.Solver.Two_Stage.Enabled = true;
params.Solver.Two_Stage.Stage_1 = struct( ...
    'Name', 'feasible-search', ...
    'Time_Limit', 300, ...
    'MIP_Gap', 0.3, ...
    'MIP_Focus', 1, ...
    'Heuristics', 0.2);
params.Solver.Two_Stage.Stage_2 = struct( ...
    'Name', 'optimality-proof', ...
    'Time_Limit', 1800, ...
    'MIP_Gap', 0.005, ...
    'MIP_Focus', 3, ...
    'Heuristics', 0.01, ...
    'Concurrent_MIP', 2);

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
clear D T ans fid Gen_Cost_At_5_Pct GFL_Node_Period GFL_Rated_Node i ...
    JSON_Text Load_Factor Load_Node_Period Load_Total_MW ...
    MOST_Base_Case MOST_Load_Base_MW MOST_Load_Profile MOST_Wind_Profile ...
    Output_File Parameter_Directory params temp Typical_Day_Factor ...
    Wind_Available_Factor x_GFM_Res_Device mpc
