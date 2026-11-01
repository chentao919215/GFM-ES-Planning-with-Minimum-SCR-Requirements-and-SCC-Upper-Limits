function [mpc, CONF] = prepare_multiple_snapshot_case(Parameter_File)
%% 根据已确定的参数，准备多时段规划算例。
% 输入：Parameter_File为参数JSON路径。
% 输出：mpc为修正后的MATPOWER算例，CONF为模型直接使用的扁平配置。
% 各节与参数脚本顺序一致，集中完成单位换算、派生量和关联矩阵计算。
% 输入应已满足模型假设。

%% 0. 读取参数与初始化输出
params = jsondecode(fileread(Parameter_File));
CONF = struct();

%% 1. 网络参数
Network = params.Network;
mpc = Network.mpc;
mpc.branch(:, 4) = Network.Branch_Scale.x*mpc.branch(:, 4);

N = size(mpc.bus, 1);
G = size(mpc.gen, 1);
L = size(mpc.branch, 1);
CONF.Bn = N;
CONF.Gn = G;
CONF.Ln = L;
CONF.Generator_Buses = mpc.gen(:, 1);
CONF.Branch_From = mpc.branch(:, 1);
CONF.Branch_To = mpc.branch(:, 2);
CONF.Line_Limit_MW = mpc.branch(:, 6);
CONF.Base_MVA = Network.Base_MVA;
CONF.Base_kV = Network.Base_kV;
CONF.Base_kA = Network.Base_kA;
CONF.Base_O = Network.Base_O;

%% 2. 同步机参数
SG = params.SG;
CONF.Xd_Gen = expand_column_parameter(SG.Xd_Gen, G);
CONF.GenCostBreakpoints = SG.Gen_Cost_Breakpoints(:)';
CONF.Gen_Pmin = expand_column_parameter(SG.Gen_Pmin_MW, G);

%% 3. 机组组合参数
UC = params.UC;
CONF.Gen_Ramp_Up_MW_per_Hour = expand_column_parameter(UC.Ramp_Up_Rate_MW_per_Hour, G);
CONF.Gen_Ramp_Down_MW_per_Hour = expand_column_parameter(UC.Ramp_Down_Rate_MW_per_Hour, G);
CONF.Gen_Min_Up_Periods = expand_column_parameter(UC.Min_Up_Periods, G);
CONF.Gen_Min_Down_Periods = expand_column_parameter(UC.Min_Down_Periods, G);
CONF.Gen_Startup_Cost = expand_column_parameter(UC.Startup_Cost, G);
CONF.Gen_Shutdown_Cost = expand_column_parameter(UC.Shutdown_Cost, G);

%% 4. 跟网型风电参数
% 同节点GFL-WG合并为一组节点参数，后续换算沿用该节点顺序。
GFL = aggregate_gfl_node_parameters(params.GFL_WG, N);
GFL_Nodes = GFL.Built_Nodes(:);
CONF.u_GFL = zeros(N, 1);
CONF.u_GFL(GFL_Nodes) = 1;

% 功率按系统节点展开，MW除以系统基准MVA得到标幺值。
PN_GFL_Node = expand_node_parameter(GFL.PN_MW, GFL_Nodes, N);
CONF.PN_GFL_pu_Node = PN_GFL_Node/CONF.Base_MVA;
CONF.GFL_Curtailment_Cost_per_MWh = GFL.Curtailment_Cost_per_MWh;

% LVRT电流同时保存设备额定基准与系统基准值；非GFL节点各项为0。
LVRT = GFL.LVRT;
CONF.KQ_GFL_Node = expand_node_parameter(LVRT.K_Q, GFL_Nodes, N);
I_GFL_N_Rated_Node = expand_node_parameter(LVRT.I_N_Rated, GFL_Nodes, N);
CONF.V_LVRT_On_Node = expand_node_parameter(LVRT.V_LVRT_On, GFL_Nodes, N);
CONF.V_LVRT_Sat_Node = expand_node_parameter(LVRT.V_LVRT_Sat, GFL_Nodes, N);
Delta_I_GFL_Rated_Node = expand_node_parameter(LVRT.Delta_I_Rated, GFL_Nodes, N);
CONF.I_GFL_N_pu_Node = I_GFL_N_Rated_Node.*PN_GFL_Node/CONF.Base_MVA;
CONF.Delta_I_GFL_pu_Node = Delta_I_GFL_Rated_Node.*PN_GFL_Node/CONF.Base_MVA;

%% 5. 构网型储能参数
GFM = params.GFM_ES;

% 规划参数：规划数量限制与同节点设备的顺序投建设置。
Planning = GFM.Planning;
CONF.GFM_Max_Units_Per_Bus = Planning.Max_Units_Per_Bus;
CONF.GFM_Max_Installed_Units = Planning.Max_Installed_Units;
CONF.GFM_Enforce_Sequential_Build = logical(Planning.Enforce_Sequential_Build);

% 设备参数：候选表逐行展开，先列同一节点的设备，再列下一节点。
Unit = GFM.Unit;
Candidate_Bus = Unit.Bus(:, 1);
Unit_Bus = reshape(Unit.Bus.', [], 1);
Unit_Order = repmat((1:size(Unit.Bus, 2)).', size(Unit.Bus, 1), 1);
Unit_Count = numel(Unit_Bus);
Candidate_Count = numel(Candidate_Bus);
[~, Candidate_Index] = ismember(Unit_Bus, Candidate_Bus);
CONF.GFM_Unit_Count = Unit_Count;
CONF.GFM_Unit_Bus = Unit_Bus;
CONF.GFM_Unit_Order = Unit_Order;
CONF.GFM_Candidate_Buses = Candidate_Bus(:)';
CONF.GFM_Unit_Candidate_Index = Candidate_Index;
CONF.GFM_Candidate_Count = Candidate_Count;

% 矩阵维度依次为[系统节点,设备]、[系统节点,候选节点]和[候选节点,设备]。
CONF.GFM_Unit_Loc_Mat = sparse(Unit_Bus, (1:Unit_Count)', 1, N, Unit_Count);
CONF.GFM_Candidate_Loc_Mat = sparse(Candidate_Bus, (1:Candidate_Count)', ...
    1, N, Candidate_Count);
CONF.GFM_Candidate_Unit_Mat = sparse(Candidate_Index, (1:Unit_Count)', ...
    1, Candidate_Count, Unit_Count);

% 功率、能量及电气参数沿用上述设备编号，标量应用于所有设备。
% Unit.X_GFM和Unit.X_GFM_Vir已是系统基准标幺值，此处仅按设备展开。
CONF.GFM_Unit_PN_MW = expand_unit_parameter(Unit.PN_MW, Unit_Count);
CONF.GFM_Unit_Energy_MWh = expand_unit_parameter(Unit.Energy_MWh, Unit_Count);
GFM_Unit_I_Post_Multiplier = expand_unit_parameter(Unit.I_Post_Multiplier, Unit_Count);
CONF.GFM_Unit_X_Res = expand_unit_parameter(Unit.X_GFM, Unit_Count);
CONF.GFM_Unit_X_Vir = expand_unit_parameter(Unit.X_GFM_Vir, Unit_Count);

% 故障电流与虚拟阻抗电纳修正均采用系统基准。
CONF.GFM_Unit_I_post = GFM_Unit_I_Post_Multiplier.* ...
    CONF.GFM_Unit_PN_MW/CONF.Base_MVA;
CONF.GFM_Unit_DeltaY_abs = 1./CONF.GFM_Unit_X_Res - ...
    1./(CONF.GFM_Unit_X_Res+CONF.GFM_Unit_X_Vir);
CONF.GFM_Unit_DeltaY = 1i*CONF.GFM_Unit_DeltaY_abs;

% 储能运行参数：同候选节点设备共用效率与SOC参数，取该节点第一套设备的值。
Storage = GFM.Storage;
First_Unit = first_unit_per_candidate(Candidate_Index, Candidate_Count);
Charge_Efficiency = expand_unit_parameter(Storage.Charge_Efficiency, Unit_Count);
Discharge_Efficiency = expand_unit_parameter(Storage.Discharge_Efficiency, Unit_Count);
SOC_Min = expand_unit_parameter(Storage.SOC_Min, Unit_Count);
SOC_Initial = expand_unit_parameter(Storage.SOC_Initial, Unit_Count);
SOC_Max = expand_unit_parameter(Storage.SOC_Max, Unit_Count);
CONF.GFM_Candidate_Charge_Efficiency = Charge_Efficiency(First_Unit);
CONF.GFM_Candidate_Discharge_Efficiency = Discharge_Efficiency(First_Unit);
CONF.GFM_Candidate_SOC_Min = SOC_Min(First_Unit);
CONF.GFM_Candidate_SOC_Initial = SOC_Initial(First_Unit);
CONF.GFM_Candidate_SOC_Max = SOC_Max(First_Unit);

% 成本参数：年固定成本系数已含年化投资与固定运维，功率、能量成本各计一次。
Costs = GFM.Costs;
Power_Cost = expand_unit_parameter(Costs.Annual_Cost_Power_per_MW, Unit_Count);
Energy_Cost = expand_unit_parameter(Costs.Annual_Cost_Energy_per_MWh, Unit_Count);
CONF.GFM_Unit_Annual_Cost = Power_Cost.*CONF.GFM_Unit_PN_MW + ...
    Energy_Cost.*CONF.GFM_Unit_Energy_MWh;

%% 6. 安全约束参数
Security = params.Security;
CONF.Consider_Wind_Uncertainty = Security.Consider_Wind_Uncertainty;
CONF.Enable_SCR = Security.Enable_SCR;
CONF.SCR_min = Security.SCR_min;
CONF.Enable_SCC = Security.Enable_SCC;
CONF.I_limit_kA_Node = expand_column_parameter(Security.I_limit_kA, N);
CONF.I_limit = CONF.I_limit_kA_Node/CONF.Base_kA;
CONF.SecurityFormulation = 'aggregated';

% 安全网络保留所有SG、候选GFM-ES及GFL-WG节点。
% 原节点到降阶节点的映射为N×1列向量，0表示被消元的节点。
Safety_Nodes = unique([mpc.gen(:, 1); Candidate_Bus; GFL_Nodes]);
Original_To_Reduced = zeros(N, 1);
Original_To_Reduced(Safety_Nodes) = (1:numel(Safety_Nodes)).';
CONF.Safety_Retained_Nodes = Safety_Nodes;
CONF.Safety_Original_To_Reduced = Original_To_Reduced;
CONF.Safety_GFL_Original_Nodes = GFL_Nodes;
CONF.Safety_GFL_Reduced_Indices = Original_To_Reduced(GFL_Nodes);
CONF.Safety_GFL_Count = numel(GFL_Nodes);
CONF.SCC_Constraint_Original_Nodes = Safety_Nodes;

%% 7. 多时段与风电场景参数
Snapshot = params.Multiple_Snapshot;
Wind = Snapshot.Wind;
D = Snapshot.Typical_Day_Count;
T = Snapshot.Period_Count;
K = Wind.Count;
CONF.TypicalDayCount = D;
CONF.TypicalDayWeights_Days = Snapshot.Typical_Day_Weights_Days(:);
CONF.PeriodCount = T;
CONF.PeriodDurations_Hours = Snapshot.Period_Durations_Hours(:);
% 运行权重维度为[D,T]，单位为h/年；负荷维度为[节点,典型日,时段]。
CONF.OperatingWeights_Hours = CONF.TypicalDayWeights_Days*CONF.PeriodDurations_Hours.';
CONF.P_Load_Profile = reshape(Snapshot.Load_P_MW, N, D, T);

CONF.WindScenarioCount = K;
Probability = Wind.Probabilities;
if isvector(Probability) && numel(Probability) == K
    CONF.WindScenarioProbabilities = repmat(reshape(Probability, 1, K), D, 1);
else
    CONF.WindScenarioProbabilities = reshape(Probability, D, K);
end
% 风电维度为[节点,典型日,场景,时段]，功率曲线保持MW。
CONF.P_GFL_Available_Scenarios = reshape(Wind.P_GFL_Available_Scenarios, N, D, K, T);

%% 8. 求解设置
Solver = params.Solver;
CONF.KZ = Solver.KZ;
CONF.ERR_TOL = Solver.ERR_TOL_Factor*CONF.KZ;
[CONF.Solver, CONF.solver] = prepare_multiple_snapshot_solver_parameters(params);
CONF.ObjectiveScale = CONF.Solver.Objective_Scale;
end

function Values = expand_column_parameter(Input, Count)
% 将标量或逐元件参数整理为列向量。
Values = Input(:);
if isscalar(Values)
    Values = repmat(Values, Count, 1);
end
end

function Values = expand_unit_parameter(Input, Count)
% 候选设备表按行展开后，再将标量扩展到所有设备。
Values = expand_column_parameter(reshape(Input.', [], 1), Count);
end

function Values = expand_node_parameter(Input, Nodes, Node_Count)
% 已建节点参数映射到全系统；其余节点为0。
Input = Input(:);
Values = zeros(Node_Count, 1);
if numel(Input) == Node_Count
    Values = Input;
else
    Values(Nodes) = Input;
end
end

function First_Unit = first_unit_per_candidate(Candidate_Index, Candidate_Count)
% 返回每个候选节点的第一套设备编号，顺序与候选节点一致。
First_Unit = zeros(Candidate_Count, 1);
for n = 1:Candidate_Count
    First_Unit(n) = find(Candidate_Index == n, 1);
end
end

function GFL = aggregate_gfl_node_parameters(GFL, Node_Count)
%% 式(8)-(9)、(25)：同节点GFL-WG容量与系统基准电流求和。
% 同节点设备只有相同LVRT阈值才可精确合并为Manuscript规定的三段函数。
% 输入应已满足同节点阈值相同、LVRT连续的模型假设，此处仅进行聚合。

Bus = GFL.Built_Nodes(:);
[Nodes, ~, Group] = unique(Bus, 'stable');
if numel(Nodes) == numel(Bus)
    return;
end
Fields = {'PN_MW', 'K_Q', 'I_N_Rated', 'Delta_I_Rated', 'V_LVRT_On', 'V_LVRT_Sat'};
Values = zeros(numel(Bus), numel(Fields));
for f = 1:numel(Fields)
    if f == 1
        Input = GFL.PN_MW(:);
    else
        Input = GFL.LVRT.(Fields{f})(:);
    end
    Values(:, f) = Input;
end
Output = zeros(numel(Nodes), numel(Fields));
for n = 1:numel(Nodes)
    V = Values(Group == n, :);
    Power = sum(V(:, 1));
    Rated_Current = sum(V(:, 1).*V(:, 3));
    Output(n, :) = [Power, sum(V(:, 1).*V(:, 2).*V(:, 3))/Rated_Current, ...
        Rated_Current/Power, sum(V(:, 1).*V(:, 4))/Power, V(1, 5:6)];
end
GFL.Built_Nodes = Nodes;
for f = 1:numel(Fields)
    Value = zeros(Node_Count, 1);
    Value(Nodes) = Output(:, f);
    if f == 1
        GFL.PN_MW = Value;
    else
        GFL.LVRT.(Fields{f}) = Value;
    end
end
end
