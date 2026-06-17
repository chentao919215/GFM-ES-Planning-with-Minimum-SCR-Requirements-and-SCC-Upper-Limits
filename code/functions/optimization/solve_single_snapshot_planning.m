function [SCC_0,SCC_1,value_P_Line,value_theta,value_P_G,value_P_GFL,value_P_GFM,...
    SCR,Z_val,value_u_GFL,value_u_G,value_Cost_CON,value_Cost_GEN,...
    value_Cost_Total,Diagnostics,value_u_GFM_Mod,value_P_GFM_Mod] = solve_single_snapshot_planning(mpc,CONF)
%% 构建并求解确定性单时刻模块化GFM-ES配置优化模型
% GFL-WG投建状态由参数文件给定；GFM-ES以模块为规划对象。
% 本函数负责建立DCOPF、阻抗重构、安全约束和成本目标，并调用求解器。

%% 1. 整理输入参数
% u_GFL为已建GFL-WG节点状态，不作为优化变量。
u_GFL = CONF.u_GFL(:);
LoadFactor = CONF.LoadFactor;

%% 2. 构造网络数据
% 网络矩阵、负荷、成本、导纳和模块参数统一由network模块与CONF提供。
NET = build_single_snapshot_network(mpc, CONF, LoadFactor);

N = NET.N;
G = NET.G;
L = NET.L;
M_GFM = CONF.GFM_Module_Count;

Gen_Loc_Mat = NET.Gen_Loc_Mat;
GFM_Module_Loc_Mat = CONF.GFM_Module_Loc_Mat;
Branch_From = NET.Branch_From;
Branch_To = NET.Branch_To;
Branch_Mat_From = NET.Branch_Mat_From;
Branch_Mat_To = NET.Branch_Mat_To;

Gen_Cost_Quad  = NET.Gen_Cost_Quad;
Gen_Cost_Lin   = NET.Gen_Cost_Lin;
Gen_Cost_Const = NET.Gen_Cost_Const;

Gen_Pmax = NET.Gen_Pmax;
Gen_Pmin = NET.Gen_Pmin;

Line_B_series = NET.Line_B_series;
Line_Pmax = NET.Line_Pmax;
Line_Limited = NET.Line_Limited;
P_Load = NET.P_Load;
GFM_Module_PN = CONF.GFM_Module_PN(:);
GFM_Module_Cost_Conv = CONF.GFM_Module_Cost_Conv(:);

Y0 = NET.Y0;
Y_SG_Add = NET.Y_SG_Add;
B_gfm_mod = NET.B_gfm_mod;
DeltaY_abs_mod = NET.DeltaY_abs_mod;

% 阻抗矩阵元素上下界用于McCormick线性化。
Z_bounds = calculate_impedance_bounds(NET, CONF);

%% 3. 定义优化变量
% 二进制变量:同步机启停状态和GFM-ES模块投建状态。
u_SG      = binvar(G,1,'full');
u_GFM_mod = binvar(M_GFM,1,'full');

% 连续运行变量:各类电源出力、节点相角和线路潮流。
P_SG      = sdpvar(G,1,'full');
P_GFL     = sdpvar(N,1,'full');
P_GFM_mod = sdpvar(M_GFM,1,'full');
theta     = sdpvar(N,1,'full');
P_Line    = sdpvar(L,1,'full');

% 节点级GFM-ES总出力由模块出力按接入节点聚合得到。
P_GFM = GFM_Module_Loc_Mat*P_GFM_mod;

% 节点阻抗矩阵拆分为实部和虚部建模。
Z_real = sdpvar(N,N,'symmetric');
Z_imag = sdpvar(N,N,'symmetric');

% 以下辅助变量用于线性化二元变量与阻抗元素的乘积。
W_SGZ_X = sdpvar(G,N,'full');
W_SGZ_R = sdpvar(G,N,'full');
W_GFMZ_X = sdpvar(M_GFM,N,'full');
W_GFMZ_R = sdpvar(M_GFM,N,'full');
W_GFM = sdpvar(M_GFM,1,'full');
Cost_SG = sdpvar(G,1,'full');

%% 4. 建立约束
C = [];

%% 4.1 GFM-ES规划约束
% 控制全系统GFM-ES模块投建数量上限。
C_plan = [];
C_plan = [C_plan, sum(u_GFM_mod) <= CONF.N_GFM_Module_Max];

% 同一候选节点内的模块可按序投建，以减少等价解。
if CONF.GFM_Module_Sequential
    module_bus = CONF.GFM_Module_Bus(:);
    module_order = CONF.GFM_Module_Order(:);
    unique_module_bus = unique(module_bus, 'stable');

    for k_bus = 1:numel(unique_module_bus)
        idx = find(module_bus == unique_module_bus(k_bus));
        [~, order_idx] = sort(module_order(idx));
        idx = idx(order_idx);

        if numel(idx) > 1
            C_plan = [C_plan, u_GFM_mod(idx(1:end-1)) >= u_GFM_mod(idx(2:end))];
        end
    end
end

%% 4.2 单时刻潮流与运行约束
% 采用DCOPF描述节点功率平衡、线路潮流和参考相角。
C1 = [];
Ref_Bus_Idx = (mpc.bus(:,2) == 3);

P_SG_Node = Gen_Loc_Mat*P_SG;
P_Inj = P_SG_Node + P_GFL + P_GFM - P_Load;
C1 = [C1, P_Inj == Branch_Mat_From*P_Line - Branch_Mat_To*P_Line];

dtheta = theta(Branch_From) - theta(Branch_To);
C1 = [C1, P_Line == Line_B_series .* dtheta];

% 仅对MATPOWER中给定热稳定限额的线路施加潮流上下限。
if any(Line_Limited)
    C1 = [C1, P_Line(Line_Limited) <= Line_Pmax(Line_Limited)];
    C1 = [C1, P_Line(Line_Limited) >= -Line_Pmax(Line_Limited)];
end
C1 = [C1, theta(Ref_Bus_Idx) == 0];

% 可选要求:至少存在一个同步机或GFM-ES模块作为电压源支撑。
if CONF.Require_Source_Online
    C1 = [C1, sum(u_SG) + sum(u_GFM_mod) >= 1];
end

C1 = [C1, P_SG >= Gen_Pmin.*u_SG, P_SG <= Gen_Pmax.*u_SG];

% 归一化同步机出力用于构造分段透视割成本约束。
Gen_Prange = Gen_Pmax - Gen_Pmin;
if any(Gen_Prange <= 0)
    error('Generator Pmax must be greater than Pmin for piecewise cost modeling.');
end
P_SG_Norm = spdiags(1./Gen_Prange, 0, G, G) * (P_SG - Gen_Pmin.*u_SG);
C1 = [C1, P_SG_Norm >= 0, P_SG_Norm <= u_SG];

C1 = [C1, P_GFL >= 0, P_GFL <= CONF.PN_GFL_Node.*u_GFL];
C1 = [C1, P_GFM_mod >= 0, P_GFM_mod <= GFM_Module_PN .* u_GFM_mod];

%% 4.3 阻抗矩阵重构约束
% 采用文档中的形式:Y0*Z + 同步机在线贡献 + GFM-ES投建贡献 = I。
C2 = [];

% 同步机支路贡献:W_SGZ_* = u_SG .* Z(同步机接入节点,:)。
Z_SG_real = Gen_Loc_Mat'*Z_real;
Z_SG_imag = Gen_Loc_Mat'*Z_imag;
U_SG_Row = repmat(u_SG, 1, N);
Z_SG_real_L = Gen_Loc_Mat'*Z_bounds.real_min;
Z_SG_real_U = Gen_Loc_Mat'*Z_bounds.real_max;
Z_SG_imag_L = Gen_Loc_Mat'*Z_bounds.imag_min;
Z_SG_imag_U = Gen_Loc_Mat'*Z_bounds.imag_max;

C2 = [C2, add_binary_product_bounds(W_SGZ_X, Z_SG_imag, U_SG_Row, Z_SG_imag_L, Z_SG_imag_U)];
C2 = [C2, add_binary_product_bounds(W_SGZ_R, Z_SG_real, U_SG_Row, Z_SG_real_L, Z_SG_real_U)];

G_sus = 1/CONF.Xd_Gen;
W_sum_X = Gen_Loc_Mat * W_SGZ_X;
W_sum_R = Gen_Loc_Mat * W_SGZ_R;

% GFM-ES模块贡献:W_GFMZ_* = u_GFM_mod .* Z(模块接入节点,:)。
Z_GFM_real = GFM_Module_Loc_Mat' * Z_real;
Z_GFM_imag = GFM_Module_Loc_Mat' * Z_imag;
U_GFM_Mod_Row = repmat(u_GFM_mod, 1, N);
Z_GFM_real_L = GFM_Module_Loc_Mat' * Z_bounds.real_min;
Z_GFM_real_U = GFM_Module_Loc_Mat' * Z_bounds.real_max;
Z_GFM_imag_L = GFM_Module_Loc_Mat' * Z_bounds.imag_min;
Z_GFM_imag_U = GFM_Module_Loc_Mat' * Z_bounds.imag_max;

C2 = [C2, add_binary_product_bounds(W_GFMZ_X, Z_GFM_imag, U_GFM_Mod_Row, Z_GFM_imag_L, Z_GFM_imag_U)];
C2 = [C2, add_binary_product_bounds(W_GFMZ_R, Z_GFM_real, U_GFM_Mod_Row, Z_GFM_real_L, Z_GFM_real_U)];

B_gfm_mat = spdiags(B_gfm_mod(:), 0, M_GFM, M_GFM);
W_gfm_sum_X = GFM_Module_Loc_Mat * (B_gfm_mat * W_GFMZ_X);
W_gfm_sum_R = GFM_Module_Loc_Mat * (B_gfm_mat * W_GFMZ_R);

% 将复数矩阵方程拆成实部和虚部两个线性约束组。
Y0_R = real(Y0);
Y0_I = imag(Y0);

LHS_Real = Y0_R*Z_real - Y0_I*Z_imag + G_sus*W_sum_X + W_gfm_sum_X;
LHS_Imag = Y0_R*Z_imag + Y0_I*Z_real - G_sus*W_sum_R - W_gfm_sum_R;

I_vec = reshape(eye(N), [], 1) * CONF.KZ;

C2 = [C2, LHS_Real(:) - I_vec >= -CONF.ERR_TOL, LHS_Real(:) - I_vec <= CONF.ERR_TOL];
C2 = [C2, LHS_Imag(:) >= -CONF.ERR_TOL, LHS_Imag(:) <= CONF.ERR_TOL];

%% 4.4 短路电流水平约束
% 限制各故障节点的三相短路电流不超过给定上限。
PN_pu = CONF.PN_GFL_pu_Node;
X_diag = diag(Z_imag);
X_diag_L = diag(Z_bounds.imag_min);
X_diag_U = diag(Z_bounds.imag_max);
C3 = add_short_circuit_current_constraints(CONF, u_GFL, u_GFM_mod, W_GFM, X_diag, DeltaY_abs_mod, PN_pu, X_diag_L, X_diag_U);

%% 4.5 经典短路比约束
% 仅对已建GFL-WG节点施加经典SCR下限。
C4 = add_classic_scr_constraints(CONF, u_GFL, X_diag, PN_pu);

C = [C, C_plan, C1, C2, C3, C4];

%% 5. 构造目标函数
% 同步机运行成本采用归一化出力上的分段透视割近似。
Gen_Cost_Quad_Norm = Gen_Cost_Quad .* (Gen_Prange.^2);
Gen_Cost_Lin_Norm = (2.*Gen_Cost_Quad.*Gen_Pmin + Gen_Cost_Lin) .* Gen_Prange;
Gen_Cost_Const_Norm = Gen_Cost_Quad.*(Gen_Pmin.^2) + ...
                      Gen_Cost_Lin.*Gen_Pmin + Gen_Cost_Const;

C_cost = Cost_SG >= 0;
for xi = CONF.GenCostBreakpoints(:)'
    tangent_slope = 2.*Gen_Cost_Quad_Norm.*xi + Gen_Cost_Lin_Norm;
    tangent_intercept = Gen_Cost_Const_Norm - Gen_Cost_Quad_Norm.*(xi^2);
    C_cost = [C_cost, Cost_SG >= CONF.AnnualHours * ...
        (tangent_slope.*P_SG_Norm + tangent_intercept.*u_SG)]; %#ok<AGROW>
end
C = [C, C_cost];

Cost_GEN = sum(Cost_SG);
Cost_GFM_Inv = GFM_Module_Cost_Conv' * u_GFM_mod;
Objective = Cost_GEN + Cost_GFM_Inv;

%% 6. 调用求解器
% 求解器参数由build_gurobi_options统一设置。
ops = build_gurobi_options();
sol = optimize(C, Objective, ops);

%% 7. 提取优化结果
if sol.problem == 0
    disp('Solver converged successfully.');
else
    disp(['Solver failed with code: ' num2str(sol.problem)]);
end

Diagnostics = build_single_snapshot_diagnostics(sol);

value_Cost_Total = value(Objective);
value_Cost_GEN = value(Cost_GEN);
value_Cost_CON = value(Cost_GFM_Inv);

value_P_GFL = value(P_GFL);
value_P_GFM = value(P_GFM);
value_P_GFM_Mod = value(P_GFM_mod);
value_P_G = value(P_SG);
value_theta = value(theta);
value_P_Line = value(P_Line);

value_u_G = value(u_SG);
value_u_GFL = u_GFL;
value_u_GFM_Mod = value(u_GFM_mod);

% 阻抗矩阵在模型中经过CONF.KZ缩放，输出时还原到原始标幺尺度。
Z_real_val = value(Z_real)/CONF.KZ;
Z_imag_val = value(Z_imag)/CONF.KZ;
Z_val = Z_real_val + 1i*Z_imag_val;

X_diag_val = value(X_diag)/CONF.KZ;
SCR = calculate_classic_scr(X_diag_val, u_GFL, PN_pu);

%% 8. 计算短路电流指标
% 分别输出基准状态和优化配置后的短路电流水平。
[SCC_0, SCC_1] = calculate_short_circuit_currents(Z_val, value_u_GFM_Mod, u_GFL, CONF, Y0, Y_SG_Add);

end
