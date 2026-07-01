function [SCC_0,SCC_1,value_P_Line,value_theta,value_P_G,value_P_GFL,value_P_GFM,...
    SCR,Z_SCC_val,Z_SCR_val,value_u_GFL,value_u_G,value_u_G_SCC,value_u_G_SCR,...
    value_Cost_CON,value_Cost_GEN,value_Cost_Total,Diagnostics,...
    value_u_GFM_Mod,value_P_GFM_Dis,value_P_GFM_Ch,value_E_GFM,...
    value_u_GFM_Ch,value_P_GFL_Curt,value_Cost_Curt] = ...
    solve_multiple_snapshot_planning(mpc,CONF)
%% 构建并求解确定性多时刻模块化GFM-ES配置优化模型
% GFL-WG接入状态与逐时可用出力由参数文件给定；GFM-ES以模块为规划对象。
% 本函数负责建立多时刻DCOPF、GFM-ES能量循环、聚合安全工况、阻抗重构、
% 安全约束和成本目标。

%% 1. 整理输入参数
% u_GFL为已建GFL-WG节点状态，不作为优化变量。
u_GFL = CONF.u_GFL(:);
D     = CONF.TypicalDayCount;
T     = CONF.PeriodCount;

%% 2. 构造网络数据
% 静态网络矩阵和逐时负荷、GFL-WG可用出力统一由network模块与CONF提供。
NET = build_multiple_snapshot_network(mpc, CONF);

N = NET.N;
G = NET.G;
L = NET.L;
M_GFM = CONF.GFM_Module_Count;
N_GFM = CONF.GFM_Candidate_Count;
N_GFM_Module = CONF.GFM_MaxModulesPerCandidate;

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

% 线路、负荷与GFL-WG逐时参数。
Line_B_series = NET.Line_B_series;
Line_Pmax     = NET.Line_Pmax;
Line_Limited  = NET.Line_Limited;
P_Load        = NET.P_Load_Profile;
P_GFL_Max     = NET.P_GFL_Available_Profile;

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
% 逐时二进制变量:同步机在各典型日、各时段的启停状态。
u_SG = binvar(G,D,T,'full');

% 跨典型日和时段共享的GFM-ES模块投建状态。
u_GFM_mod       = binvar(N_GFM,N_GFM_Module,'full');
u_GFM_mod_table = u_GFM_mod(module_linear_idx);

% 候选节点聚合GFM-ES的逐时充放电状态，1表示充电，0表示放电。
% 当充电功率和放电功率均为零时，该状态可取任一值。
u_GFM_ch = binvar(N_GFM,D,T,'full');

% 最大短路电流水平工况采用逐时同步机状态并集，最弱SCR工况采用其交集。
u_SG_SCC = binvar(G,1,'full');
u_SG_SCR = binvar(G,1,'full');

% 连续运行变量:各类电源出力、节点相角和线路潮流。
P_SG      = sdpvar(G,D,T,'full');
P_GFL     = sdpvar(N,D,T,'full');
% GFL-WG逐时弃风功率与实际出力、可用出力采用相同的节点-典型日-时段索引。
P_GFL_curt = sdpvar(N,D,T,'full');
P_GFM_dis = sdpvar(N_GFM,D,T,'full');
P_GFM_ch  = sdpvar(N_GFM,D,T,'full');
E_GFM     = sdpvar(N_GFM,D,T,'full');
P_GFM     = sdpvar(N,D,T,'full');
P_SG_Norm = sdpvar(G,D,T,'full');
theta     = sdpvar(N,D,T,'full');
P_Line    = sdpvar(L,D,T,'full');

% 两个聚合安全工况分别建立节点阻抗矩阵的实部和虚部。
Z_SCC_real = sdpvar(N,N,'symmetric');
Z_SCC_imag = sdpvar(N,N,'symmetric');
Z_SCR_real = sdpvar(N,N,'symmetric');
Z_SCR_imag = sdpvar(N,N,'symmetric');

% 最大短路电流水平工况的阻抗重构辅助变量。
W_SGZ_X_SCC  = sdpvar(G,N,'full');
W_SGZ_R_SCC  = sdpvar(G,N,'full');
W_GFMZ_X_SCC = sdpvar(M_GFM,N,'full');
W_GFMZ_R_SCC = sdpvar(M_GFM,N,'full');
W_GFM_SCC    = sdpvar(M_GFM,1,'full');

% 最弱电压支撑强度工况的阻抗重构辅助变量。
W_SGZ_X_SCR  = sdpvar(G,N,'full');
W_SGZ_R_SCR  = sdpvar(G,N,'full');
W_GFMZ_X_SCR = sdpvar(M_GFM,N,'full');
W_GFMZ_R_SCR = sdpvar(M_GFM,N,'full');

% 同步机逐时运行成本辅助变量。
Cost_SG = sdpvar(G,D,T,'full');

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

%% 4.2 多时刻潮流与运行约束
% 采用DCOPF描述各典型日、各时段的节点功率平衡、线路潮流和参考相角。
C_operation = [];
Ref_Bus_Idx = (mpc.bus(:,2) == 3);
Gen_Prange = Gen_Pmax - Gen_Pmin;
Gen_Prange_Inv = spdiags(1./Gen_Prange,0,G,G);

% 按典型日索引d和时段索引t逐一建立运行约束。
% 后续机组组合约束可在本循环中直接引用同一典型日的t-1时段。
for d = 1:D
    for t = 1:T
        u_SG_dt = u_SG(:,d,t);
        P_SG_dt = P_SG(:,d,t);
        P_GFL_dt = P_GFL(:,d,t);
        P_GFL_curt_dt = P_GFL_curt(:,d,t);
        P_GFM_dis_dt = P_GFM_dis(:,d,t);
        P_GFM_ch_dt = P_GFM_ch(:,d,t);
        E_GFM_dt = E_GFM(:,d,t);
        u_GFM_ch_dt = u_GFM_ch(:,d,t);
        P_GFM_dt = P_GFM(:,d,t);
        P_SG_Norm_dt = P_SG_Norm(:,d,t);
        theta_dt = theta(:,d,t);
        P_Line_dt = P_Line(:,d,t);

        % 候选节点GFM-ES净注入功率等于放电功率减去充电功率。
        C_operation = [C_operation, ...
            P_GFM_dt == GFM_Candidate_Loc_Mat*(P_GFM_dis_dt-P_GFM_ch_dt)];

        % 节点有功功率平衡约束。
        P_SG_Node_dt = Gen_Loc_Mat*P_SG_dt;
        P_Inj_dt = P_SG_Node_dt + P_GFL_dt + P_GFM_dt - P_Load(:,d,t);
        C_operation = [C_operation, P_Inj_dt == ...
            Branch_Mat_From*P_Line_dt - Branch_Mat_To*P_Line_dt];

        % 线路潮流、热稳定限额和参考节点相角约束。
        dtheta_dt = theta_dt(Branch_From) - theta_dt(Branch_To);
        C_operation = [C_operation, ...
            P_Line_dt == Line_B_series.*dtheta_dt];
        if any(Line_Limited)
            C_operation = [C_operation, ...
                P_Line_dt(Line_Limited) <= Line_Pmax(Line_Limited), ...
                P_Line_dt(Line_Limited) >= -Line_Pmax(Line_Limited)];
        end
        C_operation = [C_operation, theta_dt(Ref_Bus_Idx) == 0];

        % 同步机出力及归一化出力约束。
        C_operation = [C_operation, ...
            P_SG_Norm_dt == Gen_Prange_Inv*(P_SG_dt-Gen_Pmin.*u_SG_dt), ...
            P_SG_Norm_dt >= 0, P_SG_Norm_dt <= u_SG_dt];

        % 按式(1.25)建立实际出力、可用出力与弃风功率的平衡关系。
        % 按式(1.26)限制弃风功率，并利用已建状态将非GFL-WG节点固定为零。
        P_GFL_available_dt = P_GFL_Max(:,d,t).*u_GFL;
        C_operation = [C_operation, ...
            P_GFL_dt == P_GFL_available_dt-P_GFL_curt_dt, ...
            P_GFL_curt_dt >= 0, P_GFL_curt_dt <= P_GFL_available_dt];

        % 充电功率和放电功率均不超过已投建模块的聚合额定功率。
        % 第二组上界利用充放电状态避免同一时刻同时充电和放电。
        C_operation = [C_operation, ...
            u_GFM_ch_dt <= N_GFM_Installed, ...
            P_GFM_ch_dt >= 0, P_GFM_ch_dt <= P_GFM_Installed, ...
            P_GFM_ch_dt <= P_GFM_Candidate_Upper.*u_GFM_ch_dt, ...
            P_GFM_dis_dt >= 0, P_GFM_dis_dt <= P_GFM_Installed, ...
            P_GFM_dis_dt <= P_GFM_Candidate_Upper.*(1-u_GFM_ch_dt)];

        % 储能量按时段持续小时数递推；首时段从给定初始SOC对应的能量开始。
        delta_t = CONF.PeriodDurations_Hours(t);
        if t == 1
            E_GFM_prev = E_GFM_Initial;
        else
            E_GFM_prev = E_GFM(:,d,t-1);
        end
        C_operation = [C_operation, E_GFM_dt == E_GFM_prev + ...
            GFM_Charge_Efficiency.*P_GFM_ch_dt*delta_t - ...
            P_GFM_dis_dt.*delta_t./GFM_Discharge_Efficiency];

        % 各时刻结束储能量受SOC上下限约束；未投建节点的能量自动固定为零。
        C_operation = [C_operation, ...
            E_GFM_dt >= GFM_SOC_Min.*E_GFM_Installed, ...
            E_GFM_dt <= GFM_SOC_Max.*E_GFM_Installed];

        % 可选地要求每个时刻至少存在一个同步机或GFM-ES模块作为电压源。
        if CONF.Require_Source_Online
            C_operation = [C_operation, ...
                sum(u_SG_dt) + sum(u_GFM_mod_table) >= 1];
        end
    end

    % 每个典型日末恢复到初始SOC，保证典型日内部能量循环闭合。
    C_operation = [C_operation, E_GFM(:,d,T) == E_GFM_Initial];
end

%% 4.3 聚合安全状态约束
% u_SG_SCC为所有典型日、所有时段同步机投运状态的并集。
C_aggregate = [];
u_SG_sum     = zeros(G,1);
u_SG_off_sum = zeros(G,1);

for d = 1:D
    for t = 1:T
        u_SG_dt = u_SG(:,d,t);
        C_aggregate = [C_aggregate, u_SG_SCC >= u_SG_dt];
        C_aggregate = [C_aggregate, u_SG_SCR <= u_SG_dt];
        u_SG_sum     = u_SG_sum + u_SG_dt;
        u_SG_off_sum = u_SG_off_sum + (1-u_SG_dt);
    end
end
% u_SG_SCC为所有典型日、所有时段同步机投运状态的并集。
C_aggregate = [C_aggregate, u_SG_SCC <= u_SG_sum];

% u_SG_SCR为所有典型日、所有时段同步机投运状态的交集。
C_aggregate = [C_aggregate, 1-u_SG_SCR <= u_SG_off_sum];

%% 4.4 阻抗矩阵重构约束
% 分别使用同步机状态并集和交集重构Z_SCC与Z_SCR。
C_impedance_SCC = add_impedance_reconstruction_constraints( ...
    NET, CONF, Z_bounds, u_SG_SCC, u_GFM_mod_table, ...
    Z_SCC_real, Z_SCC_imag, W_SGZ_X_SCC, W_SGZ_R_SCC, ...
    W_GFMZ_X_SCC, W_GFMZ_R_SCC);

C_impedance_SCR = add_impedance_reconstruction_constraints( ...
    NET, CONF, Z_bounds, u_SG_SCR, u_GFM_mod_table, ...
    Z_SCR_real, Z_SCR_imag, W_SGZ_X_SCR, W_SGZ_R_SCR, ...
    W_GFMZ_X_SCR, W_GFMZ_R_SCR);

%% 4.5 短路电流水平约束
% 最大短路电流水平约束仅使用同步机状态并集对应的Z_SCC。
PN_pu = CONF.PN_GFL_pu_Node;
X_diag_SCC = diag(Z_SCC_imag);
X_diag_L = diag(Z_bounds.imag_min);
X_diag_U = diag(Z_bounds.imag_max);
C_scc = add_short_circuit_current_constraints(CONF, u_GFL, ...
    u_GFM_mod_table, W_GFM_SCC, X_diag_SCC, DeltaY_abs_mod, ...
    PN_pu, X_diag_L, X_diag_U);

%% 4.6 经典短路比约束
% 最弱电压支撑强度约束仅使用同步机状态交集对应的Z_SCR。
X_diag_SCR = diag(Z_SCR_imag);
C_scr = add_classic_scr_constraints(CONF, u_GFL, X_diag_SCR, PN_pu);
C_scr = [C_scr, sum(u_SG_SCR) + sum(u_GFM_mod_table) >= 1];

%% 5. 构造目标函数
% 同步机单位时间运行成本采用归一化出力上的分段透视割近似。
Gen_Cost_Quad_Norm = Gen_Cost_Quad .* (Gen_Prange.^2);
Gen_Cost_Lin_Norm = (2.*Gen_Cost_Quad.*Gen_Pmin + Gen_Cost_Lin) .* Gen_Prange;
Gen_Cost_Const_Norm = Gen_Cost_Quad.*(Gen_Pmin.^2) + ...
    Gen_Cost_Lin.*Gen_Pmin + Gen_Cost_Const;

C_cost = [];
Cost_GEN = 0;
Cost_Curt = 0;
for d = 1:D
    for t = 1:T
        C_cost = [C_cost, Cost_SG(:,d,t) >= 0];
        P_SG_Norm_dt = P_SG_Norm(:,d,t);
        for xi = CONF.GenCostBreakpoints(:)'
            tangent_slope = 2.*Gen_Cost_Quad_Norm.*xi + Gen_Cost_Lin_Norm;
            tangent_intercept = Gen_Cost_Const_Norm - Gen_Cost_Quad_Norm.*(xi^2);
            C_cost = [C_cost, Cost_SG(:,d,t) >= ...
                tangent_slope.*P_SG_Norm_dt + ...
                tangent_intercept.*u_SG(:,d,t)];
        end

        % 按典型日代表天数和时段持续小时数折算同步机全年运行成本。
        Cost_GEN = Cost_GEN + CONF.OperatingWeights_Hours(d,t)*sum(Cost_SG(:,d,t));

        % 按式(1.1)采用相同运行权重折算GFL-WG全年弃风成本。
        Cost_Curt = Cost_Curt + CONF.OperatingWeights_Hours(d,t)* ...
            CONF.GFL_Curtailment_Cost_per_MWh*sum(P_GFL_curt(:,d,t));
    end
end

% 统一装配规划、运行、安全和成本约束。
C = [C_plan, C_operation, C_aggregate, C_impedance_SCC, ...
    C_impedance_SCR, C_scc, C_scr, C_cost];

% GFM-ES年化投建成本由单位功率成本和单位能量成本预先汇总到模块级。
Cost_GFM_Inv = GFM_Module_Cost_Conv'*u_GFM_mod_table;
Cost_Total_Annual = Cost_GEN + Cost_GFM_Inv + Cost_Curt;
Objective = Cost_Total_Annual/CONF.ObjectiveScale;

%% 6. 调用求解器
% 求解器参数由build_gurobi_options统一设置。
ops = build_gurobi_options(CONF.Solver);
if isfield(CONF, 'MIPStart')
    assign(u_SG, CONF.MIPStart.u_G);
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

% 逐时结果保持[元件,典型日,时段]三维索引结构。
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

value_u_GFL = u_GFL;
value_u_G_SCC = value(u_SG_SCC);
value_u_G_SCR = value(u_SG_SCR);
value_u_GFM_Mod = value(u_GFM_mod);
value_u_GFM_Ch = value(u_GFM_ch);

% 阻抗矩阵在模型中经过CONF.KZ缩放，输出时还原到原始标幺尺度。
Z_SCC_val = value(Z_SCC_real)/CONF.KZ + 1i*value(Z_SCC_imag)/CONF.KZ;
Z_SCR_val = value(Z_SCR_real)/CONF.KZ + 1i*value(Z_SCR_imag)/CONF.KZ;

X_diag_SCR_val = value(X_diag_SCR)/CONF.KZ;
SCR = calculate_classic_scr(X_diag_SCR_val, u_GFL, PN_pu);

%% 8. 计算短路电流指标
% SCC_1采用聚合短路电流工况Z_SCC，SCC_0保留原始全同步机基准值。
[SCC_0, SCC_1] = calculate_short_circuit_currents(Z_SCC_val, ...
    value_u_GFM_Mod(module_linear_idx), u_GFL, CONF, NET.Y0, NET.Y_SG_Add);

end
