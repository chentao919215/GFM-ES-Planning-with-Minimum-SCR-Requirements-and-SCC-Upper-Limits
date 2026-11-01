function Result = solve_multiple_snapshot_planning(mpc, CONF, Return_No_Incumbent)
%% 构建并求解规划模型，返回统一的Result结构。
% 可选诊断出口供扫描归档无可行解的停止状态；默认在无可行解时抛错。
if nargin < 3
    Return_No_Incumbent = false;
end

Solve_Tic = tic;

%% 1. 整理输入参数
% u_GFL为已建GFL-WG节点状态，不作为优化变量。
u_GFL = CONF.u_GFL(:);
D = CONF.TypicalDayCount;
K = CONF.WindScenarioCount;
T = CONF.PeriodCount;
Is_Periodwise = strcmp(CONF.SecurityFormulation, 'periodwise');

%% 2. 构造网络数据
% 静态网络矩阵和逐时负荷、GFL-WG可用出力统一由网络构造函数与CONF提供。
NET = build_multiple_snapshot_network(mpc, CONF);

N = NET.N;
G = NET.G;
L = NET.L;
N_GFM = CONF.GFM_Candidate_Count;
N_GFM_Unit = CONF.GFM_Max_Units_Per_Bus;

% 候选节点检验与设备序号唯一性校验。
Unit_Bus = CONF.GFM_Unit_Bus(:);
Unit_Order = CONF.GFM_Unit_Order(:);
[~, Candidate_Index] = ismember(Unit_Bus, CONF.GFM_Candidate_Buses(:));
Unit_Linear_Index = sub2ind([N_GFM, N_GFM_Unit], Candidate_Index, Unit_Order);
assert(numel(unique(Unit_Linear_Index)) == CONF.GFM_Unit_Count, ...
    '同一候选节点的设备序号必须唯一。');
Active_Unit_Mask = false(N_GFM, N_GFM_Unit);
Active_Unit_Mask(Unit_Linear_Index) = true;

% 元件-节点关联矩阵。
Generator_Location_Matrix = NET.Generator_Location_Matrix;
GFM_Candidate_Location_Mat = CONF.GFM_Candidate_Loc_Mat;
GFM_Candidate_Unit_Mat = CONF.GFM_Candidate_Unit_Mat;
Branch_From = NET.Branch_From;
Branch_To = NET.Branch_To;
Branch_Matrix_From = NET.Branch_Matrix_From;
Branch_Matrix_To = NET.Branch_Matrix_To;

% 同步机发电成本与出力上下限参数。
Generator_Cost_Quadratic = NET.Generator_Cost_Quadratic;
Generator_Cost_Linear = NET.Generator_Cost_Linear;
Generator_Cost_Constant = NET.Generator_Cost_Constant;
Generator_P_Max = NET.Generator_P_Max;
Generator_P_Min = NET.Generator_P_Min;

% 同步机UC参数：正常爬坡速率、最小开停机时段数和单次启停成本。
Gen_Ramp_Up = CONF.Gen_Ramp_Up_MW_per_Hour(:);
Gen_Ramp_Down = CONF.Gen_Ramp_Down_MW_per_Hour(:);
Gen_Min_Up = CONF.Gen_Min_Up_Periods(:);
Gen_Min_Down = CONF.Gen_Min_Down_Periods(:);
Gen_Startup_Cost = CONF.Gen_Startup_Cost(:);
Gen_Shutdown_Cost = CONF.Gen_Shutdown_Cost(:);

% 线路、负荷与GFL-WG逐时参数。
Line_B_Series = NET.Line_B_Series;
Line_P_Max = NET.Line_P_Max;
Line_Limited = NET.Line_Limited;
P_Load = NET.P_Load_Profile;
P_GFL_Available = NET.P_GFL_Available_Scenarios;
Scenario_Probability = NET.Wind_Scenario_Probabilities;

% GFM-ES设备参数。
GFM_Unit_PN_MW = CONF.GFM_Unit_PN_MW(:);
GFM_Unit_Energy_MWh = CONF.GFM_Unit_Energy_MWh(:);
GFM_Unit_Annual_Cost = CONF.GFM_Unit_Annual_Cost(:);

% 同一候选节点内各设备采用相同的充放电效率和SOC参数。
GFM_Charge_Efficiency = CONF.GFM_Candidate_Charge_Efficiency(:);
GFM_Discharge_Efficiency = CONF.GFM_Candidate_Discharge_Efficiency(:);
GFM_SOC_Max = CONF.GFM_Candidate_SOC_Max(:);
GFM_SOC_Initial = CONF.GFM_Candidate_SOC_Initial(:);
GFM_SOC_Min = CONF.GFM_Candidate_SOC_Min(:);
for n = 1:N_GFM
    idx = Candidate_Index == n;
    Duration = GFM_Unit_Energy_MWh(idx)./GFM_Unit_PN_MW(idx);
    assert(~isempty(Duration) && all(isfinite(Duration)) && ...
        all(abs(Duration-Duration(1)) < 1e-9), ...
        'Manuscript第III-C节要求同节点设备的额定时长一致。');
end

%% 3. 定义优化变量
% 逐时二进制变量：同步机运行状态以及启动、停机动作。
u_SG = binvar(G, D, T, 'full');
u_SG_Start = binvar(G, D, T, 'full');
u_SG_Stop = binvar(G, D, T, 'full');

% 跨典型日和时段共享的GFM-ES设备投建状态。
u_GFM_Unit = binvar(N_GFM, N_GFM_Unit, 'full');
u_GFM_Unit_Table = reshape(u_GFM_Unit(Unit_Linear_Index), [], 1);

% 候选节点聚合GFM-ES的逐场景逐时充放电状态，1表示充电，0表示放电。
% 当充电功率和放电功率均为零时，该状态可取任一值。
u_GFM_Ch = binvar(N_GFM, D, K, T, 'full');

% 每个典型日分别构造安全状态：SCC采用日内并集，SCR采用日内交集。
u_SG_SCC = binvar(G, D, 'full');
u_SG_SCR = binvar(G, D, 'full');
% 场景相关连续运行变量，统一采用[元件,典型日,场景,时段]索引。
P_SG = sdpvar(G, D, K, T, 'full');
P_GFL = sdpvar(N, D, K, T, 'full');
P_GFL_Curt = sdpvar(N, D, K, T, 'full');
P_GFM_Dis = sdpvar(N_GFM, D, K, T, 'full');
P_GFM_Ch = sdpvar(N_GFM, D, K, T, 'full');
E_GFM = sdpvar(N_GFM, D, K, T, 'full');
P_GFM = sdpvar(N, D, K, T, 'full');
P_SG_Norm = sdpvar(G, D, K, T, 'full');
theta = sdpvar(N, D, K, T, 'full');
P_Line = sdpvar(L, D, K, T, 'full');

% 同步机逐场景逐时运行成本辅助变量。
Cost_SG = sdpvar(G, D, K, T, 'full');

%% 4. 建立约束

%% 4.1 规划约束（Manuscript第III-A节，式(28)-(30)）
% Manuscript式(28)：直接限制跨典型日、场景及运行时段共享的设备投建变量。
C_Plan = [];
C_Plan = [C_Plan, u_GFM_Unit(~Active_Unit_Mask) == 0];
C_Plan = [C_Plan, sum(u_GFM_Unit_Table) <= CONF.GFM_Max_Installed_Units];
% 同节点相同GFM-ES优先选取较小编号，消除编号置换产生的等价解。
C_Plan = [C_Plan, add_gfm_es_order_constraints(CONF, u_GFM_Unit_Table)];
% Manuscript未单列：由式(28)所选设备状态聚合节点功率、能量与设备数。
P_GFM_Installed = GFM_Candidate_Unit_Mat*(GFM_Unit_PN_MW.*u_GFM_Unit_Table);
E_GFM_Installed = GFM_Candidate_Unit_Mat*(GFM_Unit_Energy_MWh.*u_GFM_Unit_Table);
N_GFM_Installed = GFM_Candidate_Unit_Mat*u_GFM_Unit_Table;
P_GFM_Candidate_Upper = GFM_Candidate_Unit_Mat*GFM_Unit_PN_MW;
E_GFM_Initial = GFM_SOC_Initial.*E_GFM_Installed;

% 式(29)-(30)：源支撑是规划可行性条件，不随SCC/SCR限值开关关闭。
Security_Network = prepare_converter_security_network(NET, CONF);
if Is_Periodwise
    % 逐时对照：式(29)逐时采用实际UC，式(30)仍逐故障连通分量有源。
    Snapshot_CONF = CONF;
    Snapshot_CONF.PeriodCount = 1;
    C_Source_Support = [];
    for t = 1:T
        C_Source_Support = [C_Source_Support, ...
            add_converter_source_support_constraints( ...
            Security_Network, Snapshot_CONF, u_SG(:, :, t), ...
            u_SG(:, :, t), u_GFM_Unit_Table)];
    end
else
    C_Source_Support = add_converter_source_support_constraints( ...
        Security_Network, CONF, u_SG, u_SG_SCR, u_GFM_Unit_Table);
end
C_Plan = [C_Plan, C_Source_Support];

%% 4.2 基础潮流约束（Manuscript第III-B节，式(31)-(32)）
C_Power_Flow = [];
Ref_Bus_Index = (mpc.bus(:, 2) == 3);
Generator_P_Range = Generator_P_Max - Generator_P_Min;
assert(all(Generator_P_Range >= 0), '同步机出力上限不得小于下限。');

for d = 1:D
    for t = 1:T
        u_SG_d_t = u_SG(:, d, t);
        for k = 1:K
            P_SG_d_k_t = P_SG(:, d, k, t);
            P_GFL_d_k_t = P_GFL(:, d, k, t);
            P_GFL_Curt_d_k_t = P_GFL_Curt(:, d, k, t);
            P_GFM_Dis_d_k_t = P_GFM_Dis(:, d, k, t);
            P_GFM_Ch_d_k_t = P_GFM_Ch(:, d, k, t);
            P_GFM_d_k_t = P_GFM(:, d, k, t);
            P_SG_Norm_d_k_t = P_SG_Norm(:, d, k, t);
            Theta_d_k_t = theta(:, d, k, t);
            P_Line_d_k_t = P_Line(:, d, k, t);

            % Manuscript第III-B节，式(31)：节点有功功率平衡。
            P_SG_Node_d_k_t = Generator_Location_Matrix*P_SG_d_k_t;
            P_Inj_d_k_t = P_SG_Node_d_k_t + P_GFL_d_k_t + P_GFM_d_k_t - P_Load(:, d, t);
            C_Power_Flow = [C_Power_Flow, P_Inj_d_k_t == ...
                Branch_Matrix_From*P_Line_d_k_t - Branch_Matrix_To*P_Line_d_k_t];

            % Manuscript第III-B节，式(32)：同步机出力上下限。
            % 归一化关系供式(27)中的分段透视运行成本使用。
            C_Power_Flow = [C_Power_Flow, ...
                P_SG_d_k_t == Generator_P_Min.*u_SG_d_t + ...
                Generator_P_Range.*P_SG_Norm_d_k_t, ...
                P_SG_Norm_d_k_t >= 0, P_SG_Norm_d_k_t <= u_SG_d_t];

            % Manuscript第III-B节，式(32)：GFM-ES节点净注入。
            C_Power_Flow = [C_Power_Flow, ...
                P_GFM_d_k_t == GFM_Candidate_Location_Mat* ...
                (P_GFM_Dis_d_k_t-P_GFM_Ch_d_k_t)];

            % Manuscript第III-B节，式(32)：GFL-WG出力与弃风。
            P_GFL_Available_d_k_t = P_GFL_Available(:, d, k, t).*u_GFL;
            C_Power_Flow = [C_Power_Flow, ...
                P_GFL_d_k_t == P_GFL_Available_d_k_t-P_GFL_Curt_d_k_t, ...
                P_GFL_Curt_d_k_t >= 0, ...
                P_GFL_Curt_d_k_t <= P_GFL_Available_d_k_t];

            % Manuscript第III-B节：标准无损DC潮流、线路限额与参考相角。
            Delta_Theta_d_k_t = Theta_d_k_t(Branch_From) - Theta_d_k_t(Branch_To);
            C_Power_Flow = [C_Power_Flow, ...
                P_Line_d_k_t == Line_B_Series.*Delta_Theta_d_k_t];
            if any(Line_Limited)
                C_Power_Flow = [C_Power_Flow, ...
                    P_Line_d_k_t(Line_Limited) <= Line_P_Max(Line_Limited), ...
                    P_Line_d_k_t(Line_Limited) >= -Line_P_Max(Line_Limited)];
            end
            C_Power_Flow = [C_Power_Flow, Theta_d_k_t(Ref_Bus_Index) == 0];
        end
    end
end

%% 4.3 电源运行约束

%% 4.3.1 UC约束（Manuscript第III-B节，式(33)及标准UC约束）
% SG启停状态在同一典型日内跨风电场景共享。
C_UC = [];
for d = 1:D
    for t = 1:T
        u_SG_d_t = u_SG(:, d, t);
        Previous_t = mod(t-2, T)+1;
        u_SG_Previous = u_SG(:, d, Previous_t);
        u_SG_Start_d_t = u_SG_Start(:, d, t);
        u_SG_Stop_d_t = u_SG_Stop(:, d, t);
        Delta_t = CONF.PeriodDurations_Hours(t);
        Gen_Startup_Power = min(Generator_P_Max, Generator_P_Min+Gen_Ramp_Up*Delta_t);
        Gen_Shutdown_Power = min(Generator_P_Max, Generator_P_Min+Gen_Ramp_Down*Delta_t);

        % Manuscript第III-B节，式(33)：启停互斥与循环状态转换。
        C_UC = [C_UC, ...
            u_SG_Start_d_t+u_SG_Stop_d_t <= 1, ...
            u_SG_d_t-u_SG_Previous == u_SG_Start_d_t-u_SG_Stop_d_t];

        % Manuscript第III-B节引用的标准UC约束：逐场景同步机爬坡。
        for k = 1:K
            P_SG_d_k_t = P_SG(:, d, k, t);
            P_SG_Previous = P_SG(:, d, k, Previous_t);
            C_UC = [C_UC, ...
                P_SG_d_k_t-P_SG_Previous <= Gen_Ramp_Up*Delta_t.*u_SG_Previous + ...
                Gen_Startup_Power.*u_SG_Start_d_t, ...
                P_SG_Previous-P_SG_d_k_t <= Gen_Ramp_Down*Delta_t.*u_SG_d_t + ...
                Gen_Shutdown_Power.*u_SG_Stop_d_t];
        end
    end

    % Manuscript第III-B节引用的标准UC约束：循环最小开、停机时间。
    for g = 1:G
        for t = 1:T
            Up_Window = mod((t-Gen_Min_Up(g)+1:t)-1, T)+1;
            Down_Window = mod((t-Gen_Min_Down(g)+1:t)-1, T)+1;
            C_UC = [C_UC, ...
                sum(reshape(u_SG_Start(g, d, Up_Window), [], 1)) <= u_SG(g, d, t), ...
                sum(reshape(u_SG_Stop(g, d, Down_Window), [], 1)) <= 1-u_SG(g, d, t)]; %#ok<AGROW>
        end
    end
end

%% 4.3.2 GFM-ES约束（Manuscript第III-C节，式(34)-(35)）
% 充放电状态与运行变量随风电场景变化，投建状态跨场景共享。
C_GFM_ES = [];
for d = 1:D
    for t = 1:T
        Delta_t = CONF.PeriodDurations_Hours(t);
        for k = 1:K
            P_GFM_Dis_d_k_t = P_GFM_Dis(:, d, k, t);
            P_GFM_Ch_d_k_t = P_GFM_Ch(:, d, k, t);
            E_GFM_d_k_t = E_GFM(:, d, k, t);
            u_GFM_Ch_d_k_t = u_GFM_Ch(:, d, k, t);

            % Manuscript第III-C节，式(34)：功率边界与充放电互斥。
            C_GFM_ES = [C_GFM_ES, ...
                u_GFM_Ch_d_k_t <= N_GFM_Installed, ...
                P_GFM_Ch_d_k_t >= 0, P_GFM_Ch_d_k_t <= P_GFM_Installed, ...
                P_GFM_Ch_d_k_t <= P_GFM_Candidate_Upper.*u_GFM_Ch_d_k_t, ...
                P_GFM_Dis_d_k_t >= 0, P_GFM_Dis_d_k_t <= P_GFM_Installed, ...
                P_GFM_Dis_d_k_t <= P_GFM_Candidate_Upper.*(1-u_GFM_Ch_d_k_t)];

            % Manuscript第III-C节，式(35)：能量递推与SOC边界。
            if t == 1
                E_GFM_Previous = E_GFM_Initial;
            else
                E_GFM_Previous = E_GFM(:, d, k, t-1);
            end
            C_GFM_ES = [C_GFM_ES, E_GFM_d_k_t == E_GFM_Previous + ...
                GFM_Charge_Efficiency.*P_GFM_Ch_d_k_t*Delta_t - ...
                P_GFM_Dis_d_k_t*Delta_t./GFM_Discharge_Efficiency, ...
                E_GFM_d_k_t >= GFM_SOC_Min.*E_GFM_Installed, ...
                E_GFM_d_k_t <= GFM_SOC_Max.*E_GFM_Installed];
        end
    end

    % Manuscript第III-C节，式(35)：典型日内首尾能量闭合。
    for k = 1:K
        C_GFM_ES = [C_GFM_ES, E_GFM(:, d, k, T) == E_GFM_Initial];
    end
end

%% 4.4 安全约束（Manuscript第II节，式(18)-(26)）
% 并集残余电压直接给出SCC上界；交集仅重构GFL-WG节点电抗列。
if Is_Periodwise
    % 逐时对照：仅将安全状态改为实际UC，运行模型和物理方程共用。
    % 日内并/交集保留为结果诊断，不对逐时模型施加聚合安全限值。
    Logic_CONF = CONF;
    Logic_CONF.Enable_SCC = false;
    Logic_CONF.Enable_SCR = false;
    [C_Security, Security] = add_converter_security_constraints( ...
        NET, Logic_CONF, u_SG, u_SG_SCC, u_SG_SCR, ...
        u_GFM_Unit_Table, Security_Network);
    Security.Periodwise = cell(T, 1);
    for t = 1:T
        [C_Hourly, Hourly_Security] = add_converter_security_constraints( ...
            NET, Snapshot_CONF, u_SG(:, :, t), u_SG(:, :, t), u_SG(:, :, t), ...
            u_GFM_Unit_Table, Security_Network);
        C_Security = [C_Security, C_Hourly];
        Security.Periodwise{t} = Hourly_Security;
        Security.Segment = [Security.Segment;Hourly_Security.Segment];
    end
else
    [C_Security, Security] = add_converter_security_constraints( ...
        NET, CONF, u_SG, u_SG_SCC, u_SG_SCR, u_GFM_Unit_Table, Security_Network);
end

%% 5. 构造目标函数（Manuscript第III-A节，式(27)）
% 同步机单位时间运行成本采用归一化出力上的分段透视割近似。
Gen_Cost_Quad_Norm = Generator_Cost_Quadratic .* (Generator_P_Range.^2);
Gen_Cost_Lin_Norm = (2.*Generator_Cost_Quadratic.*Generator_P_Min + Generator_Cost_Linear) .* Generator_P_Range;
Gen_Cost_Const_Norm = Generator_Cost_Quadratic.*(Generator_P_Min.^2) + ...
    Generator_Cost_Linear.*Generator_P_Min + Generator_Cost_Constant;

C_Cost = [];
Cost_GEN = 0;
Cost_Curt = 0;
Cost_UC = 0;
for d = 1:D
    for t = 1:T
        % 启停动作跨场景共享，按典型日权重计费一次。
        Cost_UC = Cost_UC + CONF.TypicalDayWeights_Days(d)*( ...
            Gen_Startup_Cost'*u_SG_Start(:, d, t) + ...
            Gen_Shutdown_Cost'*u_SG_Stop(:, d, t));
        for k = 1:K
            C_Cost = [C_Cost, Cost_SG(:, d, k, t) >= 0];
            P_SG_Norm_d_k_t = P_SG_Norm(:, d, k, t);
            for xi = CONF.GenCostBreakpoints(:)'
                Tangent_Slope = 2.*Gen_Cost_Quad_Norm.*xi + Gen_Cost_Lin_Norm;
                Tangent_Intercept = Gen_Cost_Const_Norm - Gen_Cost_Quad_Norm.*(xi^2);
                C_Cost = [C_Cost, Cost_SG(:, d, k, t) >= ...
                    Tangent_Slope.*P_SG_Norm_d_k_t + ...
                    Tangent_Intercept.*u_SG(:, d, t)];
            end

            % 期望运行成本同时乘典型日权重、场景概率和时段持续时间。
            Expected_Weight = CONF.OperatingWeights_Hours(d, t)* ...
                Scenario_Probability(d, k);
            Cost_GEN = Cost_GEN + Expected_Weight*sum(Cost_SG(:, d, k, t));
            Cost_Curt = Cost_Curt + Expected_Weight* ...
                CONF.GFL_Curtailment_Cost_per_MWh*sum(P_GFL_Curt(:, d, k, t));
        end
    end
end

% 目标函数辅助约束先行，随后按Manuscript第III节运行约束与第II节安全约束装配。
C = [C_Cost, C_Plan, C_Power_Flow, C_UC, C_GFM_ES, C_Security];

% 式(27)的GFM-ES年固定成本已包含年化投资和固定运维，各设备仅计一次。
Cost_GFM_Fixed = GFM_Unit_Annual_Cost'*u_GFM_Unit_Table;
Cost_Total_Annual = Cost_GEN + Cost_GFM_Fixed + Cost_Curt + Cost_UC;
Objective = Cost_Total_Annual/CONF.ObjectiveScale;

%% 6. 调用求解器
Enable_SCC = CONF.Enable_SCC;
Enable_SCR = CONF.Enable_SCR;
% Gurobi原生选项从CONF.solver读取。
ops = build_multiple_snapshot_solver_options( ...
    CONF.solver, isfield(CONF, 'MIPStart'));
if isfield(CONF, 'MIPStart')
    assign(u_SG, CONF.MIPStart.u_G);
    assign(u_SG_Start, CONF.MIPStart.u_G_Start);
    assign(u_SG_Stop, CONF.MIPStart.u_G_Stop);
    assign(u_SG_SCC, CONF.MIPStart.u_G_SCC);
    assign(u_SG_SCR, CONF.MIPStart.u_G_SCR);
    assign(u_GFM_Unit, CONF.MIPStart.u_GFM_Unit);
    assign(u_GFM_Ch, CONF.MIPStart.u_GFM_Ch);
end
sol = optimize(C, Objective, ops);

%% 7. 整理求解诊断
Diagnostics = build_multiple_snapshot_diagnostics(sol, Objective, CONF.ObjectiveScale);
% 标量变量数包含二进制变量，二进制变量数为其子集；约束数按标量分量计。
Model_Variable_Ids = getvariables(allvariables(C, Objective));
Binary_Variables = [u_SG(:); u_SG_Start(:); u_SG_Stop(:); ...
    u_GFM_Unit(:); u_GFM_Ch(:); u_SG_SCC(:); u_SG_SCR(:); ...
    Security.Segment(:)];
Diagnostics.Scalar_Variable_Count = numel(Model_Variable_Ids);
Diagnostics.Binary_Variable_Count = numel(intersect( ...
    Model_Variable_Ids, getvariables(Binary_Variables)));
% 约束数按边界提取与求解器预处理之前的标量等式、不等式分量统计。
% YALMIP可能分层存放约束；先展平，避免只统计第一组约束。
Constraint_Model = struct(flatten(C));
Constraint_Clauses = Constraint_Model.clauses;
Diagnostics.Scalar_Constraint_Count = 0;
for Constraint_Index = 1:numel(Constraint_Clauses)
    Diagnostics.Scalar_Constraint_Count = ...
        Diagnostics.Scalar_Constraint_Count + ...
        numel(Constraint_Clauses{Constraint_Index}.data);
end

Saved_CONF = CONF;
if isfield(Saved_CONF, 'MIPStart')
    Saved_CONF = rmfield(Saved_CONF, 'MIPStart');
end
if Return_No_Incumbent && ~Diagnostics.has_incumbent
    Diagnostics.walltime = toc(Solve_Tic);
    Result = struct('CONF', Saved_CONF, 'Diagnostics', Diagnostics);
    return;
end

if sol.problem == 0
    disp('求解器已成功完成求解。');
elseif Diagnostics.has_incumbent
    disp(['求解器以状态码 ' num2str(sol.problem), ...
        ' 停止；返回当前最优可行解。']);
else
    error('求解器以状态码%d停止，未找到可行解。', sol.problem);
end

%% 8. 提取规划与运行结果
Result = struct();
Result.Cost.Total = value(Cost_Total_Annual);
Result.Cost.GEN = value(Cost_GEN);
Result.Cost.GFM_Fixed = value(Cost_GFM_Fixed);
Result.Cost.Curt = value(Cost_Curt);
Result.Cost.UC = value(Cost_UC);

% 场景相关结果保持[元件,典型日,场景,时段]四维索引结构。
Result.P_GFL = value(P_GFL);
Result.P_GFL_Curt = value(P_GFL_Curt);
Result.P_GFM_Dis = value(P_GFM_Dis);
Result.P_GFM_Ch = value(P_GFM_Ch);
Result.E_GFM = value(E_GFM);
Result.P_G = value(P_SG);
Result.P_Line = value(P_Line);
Result.u_G = value(u_SG);
Result.u_G_Start = value(u_SG_Start);
Result.u_G_Stop = value(u_SG_Stop);

% 聚合状态统一由最终逐时SG状态复算；关闭约束时不读取未装配辅助变量。
Result.u_G_SCC = max(round(Result.u_G), [], 3);
Result.u_G_SCR = min(round(Result.u_G), [], 3);
Result.u_GFM_Unit = value(u_GFM_Unit);
Result.u_GFM_Ch = value(u_GFM_Ch);

%% 9. 独立复算聚合与逐时安全指标
Built_Units = reshape(Result.u_GFM_Unit(Unit_Linear_Index), [], 1);
[Result.SCC_Aggregated, Result.SCR_Aggregated, ...
    Result.SCC_TimeResolved, Result.SCR_TimeResolved, ...
    Result.SecurityValidation, X_SCR] = calculate_converter_security_metrics( ...
    NET, CONF, Built_Units, Result.u_G);
Diagnostics.SecurityPosthocRegression = struct();
if strcmp(CONF.SecurityFormulation, 'periodwise')
    % 逐时模型必须与实际UC复算值逐节点、逐典型日、逐时段比较。
    SCC_Difference = nan(CONF.PeriodCount, 1);
    SCR_Difference = nan(CONF.PeriodCount, 1);
    for t = 1:CONF.PeriodCount
        Hourly_Security = Security.Periodwise{t};
        if Enable_SCC
            Hourly_SCC = reshape(Result.SCC_TimeResolved(t, :, :), ...
                CONF.TypicalDayCount, NET.Safety_N).';
            SCC_Difference(t) = finite_max_abs_difference( ...
                Hourly_SCC, value(Hourly_Security.SCC)*CONF.Base_kA);
        end
        if Enable_SCR
            Hourly_X = value(Hourly_Security.X_SCR);
            Optimized_SCR = zeros(CONF.TypicalDayCount, NET.Safety_GFL_Count);
            for d = 1:CONF.TypicalDayCount
                for k = 1:NET.Safety_GFL_Count
                    n = NET.Safety_GFL_Reduced_Indices(k);
                    Bus = NET.Safety_GFL_Original_Nodes(k);
                    Optimized_SCR(d, k) = ...
                        1/(Hourly_X(n, k, d)*CONF.PN_GFL_pu_Node(Bus));
                end
            end
            Hourly_SCR = reshape(Result.SCR_TimeResolved(t, :, :), ...
                CONF.TypicalDayCount, NET.Safety_GFL_Count);
            SCR_Difference(t) = finite_max_abs_difference( ...
                Hourly_SCR, Optimized_SCR);
        end
    end
    if Enable_SCC
        Diagnostics.SecurityPosthocRegression.SCC_MaxAbsDifference_kA = ...
            max(SCC_Difference, [], 'includenan');
    end
    if Enable_SCR
        Diagnostics.SecurityPosthocRegression.SCR_MaxAbsDifference = ...
            max(SCR_Difference, [], 'includenan');
    end
else
    if Enable_SCC
        Diagnostics.SecurityPosthocRegression.SCC_MaxAbsDifference_kA = ...
            finite_max_abs_difference(Result.SCC_Aggregated(NET.Safety_Retained_Nodes, :), ...
            value(Security.SCC)*CONF.Base_kA);
    end
    if Enable_SCR
        Diagnostics.SecurityPosthocRegression.X_SCR_MaxAbsDifference_pu = ...
            finite_max_abs_difference(X_SCR, value(Security.X_SCR));
    end
end
Diagnostics.walltime = toc(Solve_Tic);

%% 10. 保存唯一配置快照与求解诊断
Result.CONF = Saved_CONF;
Result.Diagnostics = Diagnostics;
end

function Maximum = finite_max_abs_difference(A, B)
%% 计算有限元素的最大绝对差，单独处理非有限值和空数组。
if ~isequal(size(A), size(B)) || isempty(A) || ...
        any(~isfinite(A(:))) || any(~isfinite(B(:)))
    Maximum = NaN;
else
    Maximum = max(abs(A(:)-B(:)));
end
end
