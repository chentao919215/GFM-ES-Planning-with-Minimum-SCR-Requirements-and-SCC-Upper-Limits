function [SCC_0,SCC_1,value_P_Line,value_theta,value_P_G,value_P_GFL,value_P_GFM,...
    SCR,Z_SCC_val,Z_SCR_val,value_u_GFL,value_u_G,value_u_G_SCC,value_u_G_SCR,...
    value_Cost_CON,value_Cost_GEN,value_Cost_Total,Diagnostics,...
    value_u_GFM_Mod,value_P_GFM_Dis,value_P_GFM_Ch,value_E_GFM,...
    value_u_GFM_Ch,value_P_GFL_Curt,value_Cost_Curt,...
    value_u_G_Start,value_u_G_Stop,value_Cost_UC] = ...
    solve_multiple_snapshot_planning(mpc,CONF)
%% 构建并求解场景随机多时段模块化GFM-ES配置优化模型
% GFM-ES投建和同步机组合状态跨风电场景共享，其余运行变量按场景补救。
% 安全状态仍仅在各典型日内跨时段聚合，安全网络与McCormick变量不带场景维。

%% 1. 整理输入参数
% u_GFL为已建GFL-WG节点状态，不作为优化变量。
u_GFL = CONF.u_GFL(:);
D     = CONF.TypicalDayCount;
K     = CONF.WindScenarioCount;
T     = CONF.PeriodCount;

%% 2. 构造网络数据
% 静态网络矩阵和逐时负荷、GFL-WG可用出力统一由network模块与CONF提供。
NET = build_multiple_snapshot_network(mpc, CONF);

N = NET.N;
G = NET.G;
L = NET.L;
NS = NET.Safety_N;
NGFL = NET.Safety_GFL_Count;
M_GFM = CONF.GFM_Module_Count;
N_GFM = CONF.GFM_Candidate_Count;
N_GFM_Module = CONF.GFM_MaxModulesPerCandidate;
safety_nodes = NET.Safety_Retained_Nodes;
gfl_original_nodes = NET.Safety_GFL_Original_Nodes;
gfl_reduced_indices = NET.Safety_GFL_Reduced_Indices;

% 候选节点检验与模块序号唯一性校验。
module_bus   = CONF.GFM_Module_Bus(:);
module_order = CONF.GFM_Module_Order(:);
[~, candidate_idx] = ismember(module_bus, CONF.GFM_Module_Candidates(:));
module_linear_idx  = sub2ind([N_GFM, N_GFM_Module], candidate_idx, module_order);
active_module_mask = false(N_GFM, N_GFM_Module);
active_module_mask(module_linear_idx) = true;

% 元件-节点关联矩阵。
Gen_Loc_Mat        = NET.Gen_Loc_Mat;
GFM_Candidate_Loc_Mat = CONF.GFM_Candidate_Loc_Mat;
GFM_Candidate_Module_Mat = CONF.GFM_Candidate_Module_Mat;
Branch_From        = NET.Branch_From;
Branch_To          = NET.Branch_To;
Branch_Mat_From    = NET.Branch_Mat_From;
Branch_Mat_To      = NET.Branch_Mat_To;

% 同步机发电成本与出力上下限参数。
Gen_Cost_Quad  = NET.Gen_Cost_Quad;
Gen_Cost_Lin   = NET.Gen_Cost_Lin;
Gen_Cost_Const = NET.Gen_Cost_Const;
Gen_Pmax = NET.Gen_Pmax;
Gen_Pmin = NET.Gen_Pmin;

% 同步机UC参数：正常爬坡速率、最小开停机时段数和单次启停成本。
Gen_Ramp_Up = CONF.Gen_Ramp_Up_MW_per_Hour(:);
Gen_Ramp_Down = CONF.Gen_Ramp_Down_MW_per_Hour(:);
Gen_Min_Up = CONF.Gen_Min_Up_Periods(:);
Gen_Min_Down = CONF.Gen_Min_Down_Periods(:);
Gen_Startup_Cost = CONF.Gen_Startup_Cost(:);
Gen_Shutdown_Cost = CONF.Gen_Shutdown_Cost(:);

% 线路、负荷与GFL-WG逐时参数。
Line_B_series = NET.Line_B_series;
Line_Pmax     = NET.Line_Pmax;
Line_Limited  = NET.Line_Limited;
P_Load        = NET.P_Load_Profile;
P_GFL_Available = NET.P_GFL_Available_Scenarios;
Scenario_Probability = NET.WindScenarioProbabilities;

% GFM-ES模块参数。
GFM_Module_PN        = CONF.GFM_Module_PN(:);
GFM_Module_Energy    = CONF.GFM_Module_Rated_Energy(:);
GFM_Module_Cost_Conv = CONF.GFM_Module_Cost_Conv(:);
DeltaY_abs_mod       = NET.DeltaY_abs_mod;

% 同一候选节点内各模块采用相同的充放电效率和SOC参数。
GFM_Charge_Efficiency    = CONF.GFM_Candidate_Charge_Efficiency(:);
GFM_Discharge_Efficiency = CONF.GFM_Candidate_Discharge_Efficiency(:);
GFM_SOC_Max              = CONF.GFM_Candidate_SOC_Max(:);
GFM_SOC_Initial          = CONF.GFM_Candidate_SOC_Initial(:);
GFM_SOC_Min              = CONF.GFM_Candidate_SOC_Min(:);

% 阻抗矩阵元素上下界用于McCormick线性化。
Z_bounds = calculate_impedance_bounds(NET, CONF);

%% 3. 定义优化变量
% 逐时二进制变量：同步机运行状态以及启动、停机动作。
u_SG = binvar(G,D,T,'full');
u_SG_start = binvar(G,D,T,'full');
u_SG_stop = binvar(G,D,T,'full');

% 跨典型日和时段共享的GFM-ES模块投建状态。
u_GFM_mod       = binvar(N_GFM,N_GFM_Module,'full');
u_GFM_mod_table = u_GFM_mod(module_linear_idx);

% 候选节点聚合GFM-ES的逐场景逐时充放电状态，1表示充电，0表示放电。
% 当充电功率和放电功率均为零时，该状态可取任一值。
u_GFM_ch = binvar(N_GFM,D,K,T,'full');

% 每个典型日分别构造安全状态：SCC采用日内并集，SCR采用日内交集。
u_SG_SCC = binvar(G,D,'full');
u_SG_SCR = binvar(G,D,'full');

% 场景相关连续运行变量，统一采用[元件,典型日,场景,时段]索引。
P_SG       = sdpvar(G,D,K,T,'full');
P_GFL      = sdpvar(N,D,K,T,'full');
P_GFL_curt = sdpvar(N,D,K,T,'full');
P_GFM_dis  = sdpvar(N_GFM,D,K,T,'full');
P_GFM_ch   = sdpvar(N_GFM,D,K,T,'full');
E_GFM      = sdpvar(N_GFM,D,K,T,'full');
P_GFM      = sdpvar(N,D,K,T,'full');
P_SG_Norm  = sdpvar(G,D,K,T,'full');
theta      = sdpvar(N,D,K,T,'full');
P_Line     = sdpvar(L,D,K,T,'full');

% 各典型日分别重构安全阻抗；SCC构造完整矩阵，SCR仅构造GFL-WG节点列。
% SCC采用三维full变量并在约束中逐典型日显式施加对称性。
Z_SCC_real = sdpvar(NS,NS,D,'full');
Z_SCC_imag = sdpvar(NS,NS,D,'full');
Z_SCR_real = sdpvar(NS,NGFL,D,'full');
Z_SCR_imag = sdpvar(NS,NGFL,D,'full');

% 短路电流水平保守上界工况的阻抗重构与SCC辅助变量。
W_SGZ_X_SCC  = sdpvar(G,NS,D,'full');
W_SGZ_R_SCC  = sdpvar(G,NS,D,'full');
W_GFMZ_X_SCC = sdpvar(M_GFM,NS,D,'full');
W_GFMZ_R_SCC = sdpvar(M_GFM,NS,D,'full');
W_GFM_SCC    = sdpvar(M_GFM,D,'full');

% 电压支撑强度保守下界工况的阻抗重构辅助变量。
W_SGZ_X_SCR  = sdpvar(G,NGFL,D,'full');
W_SGZ_R_SCR  = sdpvar(G,NGFL,D,'full');
W_GFMZ_X_SCR = sdpvar(M_GFM,NGFL,D,'full');
W_GFMZ_R_SCR = sdpvar(M_GFM,NGFL,D,'full');

% 同步机逐场景逐时运行成本辅助变量。
Cost_SG = sdpvar(G,D,K,T,'full');

%% 4. 建立约束
%% 4.1 GFM-ES规划约束
% 控制全系统GFM-ES模块投建数量上限，并禁用参数表中未配置的模块位置。
C_plan = [];
C_plan = [C_plan, u_GFM_mod(~active_module_mask) == 0];
C_plan = [C_plan, sum(u_GFM_mod_table) <= CONF.N_GFM_Module_Max];

% 将已投建模块的额定功率与额定能量聚合到候选节点。
P_GFM_Installed = GFM_Candidate_Module_Mat* ...
    (GFM_Module_PN.*u_GFM_mod_table);
E_GFM_Installed = GFM_Candidate_Module_Mat* ...
    (GFM_Module_Energy.*u_GFM_mod_table);
N_GFM_Installed = GFM_Candidate_Module_Mat*u_GFM_mod_table;
P_GFM_Candidate_Upper = GFM_Candidate_Module_Mat*GFM_Module_PN;
E_GFM_Initial = GFM_SOC_Initial.*E_GFM_Installed;

% 同一候选节点内的模块可按序投建，以减少等价解。
if CONF.GFM_Module_Sequential
    unique_module_bus = unique(module_bus, 'stable');
    for k_bus = 1:numel(unique_module_bus)
        idx = find(module_bus == unique_module_bus(k_bus));
        [~, order_idx] = sort(module_order(idx));
        idx = idx(order_idx);
        if numel(idx) > 1
            C_plan = [C_plan, ...
                u_GFM_mod_table(idx(1:end-1)) >= u_GFM_mod_table(idx(2:end))]; %#ok<AGROW>
        end
    end
end

%% 4.2 场景化多时段潮流与运行约束
% UC状态及启停动作跨场景共享；出力、储能运行和网络变量随场景变化。
C_operation = [];
Ref_Bus_Idx = (mpc.bus(:,2) == 3);
Gen_Prange = Gen_Pmax - Gen_Pmin;
Gen_Prange_Inv = spdiags(1./Gen_Prange,0,G,G);

% 先建立场景共享的UC时序约束，再逐场景建立运行补救约束。
for d = 1:D
    for t = 1:T
        u_SG_dt = u_SG(:,d,t);
        % 典型日内同步机状态和启停动作按日首与日末循环衔接。
        % 启动与停机动作互斥，并由相邻时段运行状态的变化唯一确定。
        previous_t = mod(t-2,T)+1;
        u_SG_prev = u_SG(:,d,previous_t);
        u_SG_start_dt = u_SG_start(:,d,t);
        u_SG_stop_dt = u_SG_stop(:,d,t);
        delta_t = CONF.PeriodDurations_Hours(t);
        Gen_Startup_Power = min(Gen_Pmax, Gen_Pmin+Gen_Ramp_Up*delta_t);
        Gen_Shutdown_Power = min(Gen_Pmax, Gen_Pmin+Gen_Ramp_Down*delta_t);
        C_operation = [C_operation, ...
            u_SG_start_dt+u_SG_stop_dt <= 1, ...
            u_SG_dt-u_SG_prev == u_SG_start_dt-u_SG_stop_dt];

        % 电压源存在性仅依赖场景共享状态，无需按场景复制。
        if CONF.Require_Source_Online
            C_operation = [C_operation, ...
                sum(u_SG_dt) + sum(u_GFM_mod_table) >= 1];
        end

        for k = 1:K
            P_SG_dkt = P_SG(:,d,k,t);
            P_GFL_dkt = P_GFL(:,d,k,t);
            P_GFL_curt_dkt = P_GFL_curt(:,d,k,t);
            P_GFM_dis_dkt = P_GFM_dis(:,d,k,t);
            P_GFM_ch_dkt = P_GFM_ch(:,d,k,t);
            E_GFM_dkt = E_GFM(:,d,k,t);
            u_GFM_ch_dkt = u_GFM_ch(:,d,k,t);
            P_GFM_dkt = P_GFM(:,d,k,t);
            P_SG_Norm_dkt = P_SG_Norm(:,d,k,t);
            theta_dkt = theta(:,d,k,t);
            P_Line_dkt = P_Line(:,d,k,t);

            % GFM-ES净注入及节点功率平衡。
            C_operation = [C_operation, ...
                P_GFM_dkt == GFM_Candidate_Loc_Mat* ...
                (P_GFM_dis_dkt-P_GFM_ch_dkt)];
            P_SG_Node_dkt = Gen_Loc_Mat*P_SG_dkt;
            P_Inj_dkt = P_SG_Node_dkt + P_GFL_dkt + P_GFM_dkt - P_Load(:,d,t);
            C_operation = [C_operation, P_Inj_dkt == ...
                Branch_Mat_From*P_Line_dkt - Branch_Mat_To*P_Line_dkt];

            % 场景相关线路潮流、热稳定限额和参考节点相角。
            dtheta_dkt = theta_dkt(Branch_From) - theta_dkt(Branch_To);
            C_operation = [C_operation, ...
                P_Line_dkt == Line_B_series.*dtheta_dkt];
            if any(Line_Limited)
                C_operation = [C_operation, ...
                    P_Line_dkt(Line_Limited) <= Line_Pmax(Line_Limited), ...
                    P_Line_dkt(Line_Limited) >= -Line_Pmax(Line_Limited)];
            end
            C_operation = [C_operation, theta_dkt(Ref_Bus_Idx) == 0];

            % 同步机出力、归一化出力和逐场景爬坡约束。
            P_SG_prev = P_SG(:,d,k,previous_t);
            C_operation = [C_operation, ...
                P_SG_Norm_dkt == Gen_Prange_Inv* ...
                (P_SG_dkt-Gen_Pmin.*u_SG_dt), ...
                P_SG_Norm_dkt >= 0, P_SG_Norm_dkt <= u_SG_dt, ...
                P_SG_dkt-P_SG_prev <= Gen_Ramp_Up*delta_t.*u_SG_prev + ...
                    Gen_Startup_Power.*u_SG_start_dt, ...
                P_SG_prev-P_SG_dkt <= Gen_Ramp_Down*delta_t.*u_SG_dt + ...
                    Gen_Shutdown_Power.*u_SG_stop_dt];

            % 严格区分场景可用出力、额定功率和实际出力。弃风至少吸收
            % 可用出力超过场站额定功率的部分，实际出力因此不超过额定值。
            P_GFL_available_dkt = P_GFL_Available(:,d,k,t).*u_GFL;
            C_operation = [C_operation, ...
                P_GFL_dkt == P_GFL_available_dkt-P_GFL_curt_dkt, ...
                P_GFL_curt_dkt >= 0, ...
                P_GFL_curt_dkt >= P_GFL_available_dkt-CONF.PN_GFL_Node, ...
                P_GFL_curt_dkt <= P_GFL_available_dkt];

            % GFM-ES充放电互斥、功率边界和逐场景能量递推。
            C_operation = [C_operation, ...
                u_GFM_ch_dkt <= N_GFM_Installed, ...
                P_GFM_ch_dkt >= 0, P_GFM_ch_dkt <= P_GFM_Installed, ...
                P_GFM_ch_dkt <= P_GFM_Candidate_Upper.*u_GFM_ch_dkt, ...
                P_GFM_dis_dkt >= 0, P_GFM_dis_dkt <= P_GFM_Installed, ...
                P_GFM_dis_dkt <= P_GFM_Candidate_Upper.*(1-u_GFM_ch_dkt)];
            if t == 1
                E_GFM_prev = E_GFM_Initial;
            else
                E_GFM_prev = E_GFM(:,d,k,t-1);
            end
            C_operation = [C_operation, E_GFM_dkt == E_GFM_prev + ...
                GFM_Charge_Efficiency.*P_GFM_ch_dkt*delta_t - ...
                P_GFM_dis_dkt*delta_t./GFM_Discharge_Efficiency, ...
                E_GFM_dkt >= GFM_SOC_Min.*E_GFM_Installed, ...
                E_GFM_dkt <= GFM_SOC_Max.*E_GFM_Installed];
        end
    end

    % 最小开、停机约束采用循环滑动窗口，与典型日日首日末状态衔接一致。
    for g = 1:G
        for t = 1:T
            up_window = mod((t-Gen_Min_Up(g)+1:t)-1,T)+1;
            down_window = mod((t-Gen_Min_Down(g)+1:t)-1,T)+1;
            C_operation = [C_operation, ...
                sum(reshape(u_SG_start(g,d,up_window),[],1)) <= u_SG(g,d,t), ...
                sum(reshape(u_SG_stop(g,d,down_window),[],1)) <= 1-u_SG(g,d,t)]; %#ok<AGROW>
        end
    end

    % 各场景均在本典型日内首尾闭合，不跨典型日传递能量状态。
    for k = 1:K
        C_operation = [C_operation, E_GFM(:,d,k,T) == E_GFM_Initial];
    end
end

%% 4.3 聚合安全状态约束
% 每个典型日分别对逐时同步机状态取并集和交集，典型日之间不再聚合。
C_aggregate = [];
for d = 1:D
    u_SG_sum_d     = zeros(G,1);
    u_SG_off_sum_d = zeros(G,1);
    for t = 1:T
        u_SG_dt = u_SG(:,d,t);
        C_aggregate = [C_aggregate, u_SG_SCC(:,d) >= u_SG_dt];
        C_aggregate = [C_aggregate, u_SG_SCR(:,d) <= u_SG_dt];
        u_SG_sum_d     = u_SG_sum_d + u_SG_dt;
        u_SG_off_sum_d = u_SG_off_sum_d + (1-u_SG_dt);
    end

    % u_SG_SCC(:,d)为典型日d内各时段同步机投运状态的并集。
    C_aggregate = [C_aggregate, u_SG_SCC(:,d) <= u_SG_sum_d];

    % u_SG_SCR(:,d)为典型日d内各时段同步机投运状态的交集。
    C_aggregate = [C_aggregate, 1-u_SG_SCR(:,d) <= u_SG_off_sum_d];
end

%% 4.4 阻抗矩阵重构约束
% 两类工况共用降阶安全网络，并复用相同的逐元素阻抗上下界。
% SCC逐典型日构造全部阻抗列，SCR逐典型日仅构造GFL-WG节点列。
C_impedance_SCC = [];
C_impedance_SCR = [];
C_scc = [];
C_scr = [];
X_diag_SCR = [];

%% 4.5 短路电流水平与经典短路比约束
% SCC覆盖全部已建及候选有源设备接入节点。
% GFL-WG额定功率仅用于安全约束，不与逐时可用出力或实际出力混用。
PN_GFL_rated_pu_node = CONF.PN_GFL_pu_Node;
u_GFL_Safety = u_GFL(safety_nodes);
PN_GFL_rated_pu_safety = PN_GFL_rated_pu_node(safety_nodes);
CONF_Safety = CONF;
CONF_Safety.GFM_Module_Loc_Mat = NET.Safety_GFM_Module_Loc_Mat;
CONF_Safety.I_limit = CONF.I_limit(safety_nodes);
CONF_Safety.I_post_GFL_Node = CONF.I_post_GFL_Node(safety_nodes);
CONF_Safety.PN_GFL_pu_Node = PN_GFL_rated_pu_safety;
X_diag_L = diag(Z_bounds.SCC.imag_min);
X_diag_U = diag(Z_bounds.SCC.imag_max);
% 从SCR阻抗列提取GFL-WG节点自阻抗，并严格采用场站额定功率。
scr_diagonal_indices = sub2ind([NS,NGFL], ...
    gfl_reduced_indices,(1:NGFL).');
PN_GFL_rated_pu = PN_GFL_rated_pu_node(gfl_original_nodes);

for d = 1:D
    Z_SCC_real_d = Z_SCC_real(:,:,d);
    Z_SCC_imag_d = Z_SCC_imag(:,:,d);
    Z_SCR_real_d = Z_SCR_real(:,:,d);
    Z_SCR_imag_d = Z_SCR_imag(:,:,d);

    % 完整SCC阻抗矩阵在每个典型日内均保持对称。
    C_impedance_SCC = [C_impedance_SCC, ...
        Z_SCC_real_d == Z_SCC_real_d.', ...
        Z_SCC_imag_d == Z_SCC_imag_d.'];
    C_impedance_SCC = [C_impedance_SCC, ...
        add_impedance_reconstruction_constraints( ...
        NET, CONF, Z_bounds.SCC, u_SG_SCC(:,d), u_GFM_mod_table, ...
        Z_SCC_real_d, Z_SCC_imag_d, W_SGZ_X_SCC(:,:,d), ...
        W_SGZ_R_SCC(:,:,d), W_GFMZ_X_SCC(:,:,d), ...
        W_GFMZ_R_SCC(:,:,d), (1:NS).')];

    C_impedance_SCR = [C_impedance_SCR, ...
        add_impedance_reconstruction_constraints( ...
        NET, CONF, Z_bounds.SCR, u_SG_SCR(:,d), u_GFM_mod_table, ...
        Z_SCR_real_d, Z_SCR_imag_d, W_SGZ_X_SCR(:,:,d), ...
        W_SGZ_R_SCR(:,:,d), W_GFMZ_X_SCR(:,:,d), ...
        W_GFMZ_R_SCR(:,:,d), gfl_reduced_indices)];

    X_diag_SCC_d = diag(Z_SCC_imag_d);
    C_scc = [C_scc, add_short_circuit_current_constraints( ...
        CONF_Safety, u_GFL_Safety, u_GFM_mod_table, W_GFM_SCC(:,d), ...
        X_diag_SCC_d, DeltaY_abs_mod, PN_GFL_rated_pu_safety, ...
        X_diag_L, X_diag_U)];

    X_diag_SCR_d = Z_SCR_imag_d(scr_diagonal_indices);
    X_diag_SCR = [X_diag_SCR, X_diag_SCR_d]; %#ok<AGROW>
    C_scr = [C_scr, add_classic_scr_constraints( ...
        CONF, ones(NGFL,1), X_diag_SCR_d, PN_GFL_rated_pu), ...
        sum(u_SG_SCR(:,d)) + sum(u_GFM_mod_table) >= 1];
end

%% 5. 构造目标函数
% 同步机单位时间运行成本采用归一化出力上的分段透视割近似。
Gen_Cost_Quad_Norm = Gen_Cost_Quad .* (Gen_Prange.^2);
Gen_Cost_Lin_Norm = (2.*Gen_Cost_Quad.*Gen_Pmin + Gen_Cost_Lin) .* Gen_Prange;
Gen_Cost_Const_Norm = Gen_Cost_Quad.*(Gen_Pmin.^2) + ...
    Gen_Cost_Lin.*Gen_Pmin + Gen_Cost_Const;

C_cost = [];
Cost_GEN = 0;
Cost_Curt = 0;
Cost_UC = 0;
for d = 1:D
    for t = 1:T
        % 启停动作跨场景共享，按典型日权重计费一次。
        Cost_UC = Cost_UC + CONF.TypicalDayWeights_Days(d)*( ...
            Gen_Startup_Cost'*u_SG_start(:,d,t) + ...
            Gen_Shutdown_Cost'*u_SG_stop(:,d,t));
        for k = 1:K
            C_cost = [C_cost, Cost_SG(:,d,k,t) >= 0];
            P_SG_Norm_dkt = P_SG_Norm(:,d,k,t);
            for xi = CONF.GenCostBreakpoints(:)'
                tangent_slope = 2.*Gen_Cost_Quad_Norm.*xi + Gen_Cost_Lin_Norm;
                tangent_intercept = Gen_Cost_Const_Norm - Gen_Cost_Quad_Norm.*(xi^2);
                C_cost = [C_cost, Cost_SG(:,d,k,t) >= ...
                    tangent_slope.*P_SG_Norm_dkt + ...
                    tangent_intercept.*u_SG(:,d,t)];
            end

            % 期望运行成本同时乘典型日权重、场景概率和时段持续时间。
            expected_weight = CONF.OperatingWeights_Hours(d,t)* ...
                Scenario_Probability(d,k);
            Cost_GEN = Cost_GEN + expected_weight*sum(Cost_SG(:,d,k,t));
            Cost_Curt = Cost_Curt + expected_weight* ...
                CONF.GFL_Curtailment_Cost_per_MWh*sum(P_GFL_curt(:,d,k,t));
        end
    end
end

% 统一装配规划、运行、安全和成本约束。
C = [C_plan, C_operation, C_aggregate, C_impedance_SCC, ...
    C_impedance_SCR, C_scc, C_scr, C_cost];

% GFM-ES年化投建成本由单位功率成本和单位能量成本预先汇总到模块级。
Cost_GFM_Inv = GFM_Module_Cost_Conv'*u_GFM_mod_table;
Cost_Total_Annual = Cost_GEN + Cost_GFM_Inv + Cost_Curt + Cost_UC;
Objective = Cost_Total_Annual/CONF.ObjectiveScale;

%% 6. 调用求解器
% 求解器参数由build_gurobi_options统一设置。
ops = build_gurobi_options(CONF.Solver);
if isfield(CONF, 'MIPStart')
    assign(u_SG, CONF.MIPStart.u_G);
    if isfield(CONF.MIPStart, 'u_G_Start')
        assign(u_SG_start, CONF.MIPStart.u_G_Start);
    end
    if isfield(CONF.MIPStart, 'u_G_Stop')
        assign(u_SG_stop, CONF.MIPStart.u_G_Stop);
    end
    assign(u_SG_SCC, CONF.MIPStart.u_G_SCC);
    assign(u_SG_SCR, CONF.MIPStart.u_G_SCR);
    assign(u_GFM_mod, CONF.MIPStart.u_GFM_Mod);
    if isfield(CONF.MIPStart, 'u_GFM_Ch')
        assign(u_GFM_ch, CONF.MIPStart.u_GFM_Ch);
    end
    ops.usex0 = 1;
    ops.warmstart = 1;
end
sol = optimize(C, Objective, ops);

%% 7. 提取优化结果
Diagnostics = build_multiple_snapshot_diagnostics(sol);
Diagnostics.objective_scale = CONF.ObjectiveScale;
Diagnostics.objective = Diagnostics.objective*CONF.ObjectiveScale;
Diagnostics.best_bound = Diagnostics.best_bound*CONF.ObjectiveScale;

if sol.problem == 0
    disp('Solver converged successfully.');
elseif Diagnostics.has_incumbent
    disp(['Solver stopped with code ' num2str(sol.problem), ...
        '; the best incumbent will be saved.']);
else
    error('Solver stopped with code %d without a feasible incumbent.', sol.problem);
end

value_Cost_Total = value(Cost_Total_Annual);
value_Cost_GEN = value(Cost_GEN);
value_Cost_CON = value(Cost_GFM_Inv);
value_Cost_Curt = value(Cost_Curt);
value_Cost_UC = value(Cost_UC);

% 场景相关结果保持[元件,典型日,场景,时段]四维索引结构。
value_P_GFL = value(P_GFL);
value_P_GFL_Curt = value(P_GFL_curt);
value_P_GFM_Dis = value(P_GFM_dis);
value_P_GFM_Ch = value(P_GFM_ch);
value_E_GFM = value(E_GFM);
value_P_GFM = value(P_GFM);
value_P_G = value(P_SG);
value_theta = value(theta);
value_P_Line = value(P_Line);
value_u_G = value(u_SG);
value_u_G_Start = value(u_SG_start);
value_u_G_Stop = value(u_SG_stop);

value_u_GFL = u_GFL;
value_u_G_SCC = value(u_SG_SCC);
value_u_G_SCR = value(u_SG_SCR);
value_u_GFM_Mod = value(u_GFM_mod);
value_u_GFM_Ch = value(u_GFM_ch);

% 阻抗矩阵在模型中经过CONF.KZ缩放，输出时还原到原始标幺尺度。
Z_SCC_val = value(Z_SCC_real)/CONF.KZ + 1i*value(Z_SCC_imag)/CONF.KZ;
Z_SCR_val = value(Z_SCR_real)/CONF.KZ + 1i*value(Z_SCR_imag)/CONF.KZ;

X_diag_SCR_val = value(X_diag_SCR)/CONF.KZ;
SCR = zeros(N,D);
for d = 1:D
    SCR(gfl_original_nodes,d) = calculate_classic_scr( ...
        X_diag_SCR_val(:,d),ones(NGFL,1),PN_GFL_rated_pu);
end

%% 8. 计算短路电流指标
% 每个典型日分别恢复完整节点阻抗，并保持SCC结果的原节点索引。
value_u_GFM_mod_table = value_u_GFM_Mod(module_linear_idx);
Y_GFM_SCC_Node = CONF.GFM_Module_Loc_Mat*(value_u_GFM_mod_table.* ...
    (1./(1i*CONF.GFM_Module_X_res(:))));
SCC_0 = [];
SCC_1 = zeros(N,D);
for d = 1:D
    Y_SG_SCC_Node_d = (NET.Gen_Loc_Mat*value_u_G_SCC(:,d))* ...
        (1/(1i*CONF.Xd_Gen));
    Y_SCC_Full_d = NET.Y0+spdiags( ...
        Y_SG_SCC_Node_d+Y_GFM_SCC_Node,0,N,N);
    if rcond(full(Y_SCC_Full_d)) < 1e-10
        error('典型日%d聚合SCC工况的完整节点导纳矩阵不可逆，无法恢复全节点结果。',d);
    end
    Z_SCC_Full_d = full(Y_SCC_Full_d)\eye(N);
    [SCC_0_d, SCC_1(:,d)] = calculate_short_circuit_currents( ...
        Z_SCC_Full_d,value_u_GFM_mod_table,u_GFL,CONF,NET.Y0,NET.Y_SG_Add);
    if isempty(SCC_0)
        SCC_0 = SCC_0_d;
    end
end

end
