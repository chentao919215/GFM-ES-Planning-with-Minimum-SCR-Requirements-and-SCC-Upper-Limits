function [SCC_0,SCC_1,value_P_Line,value_theta,value_P_G,value_P_GFL,value_P_GFM,...
    SCR,Z_val,value_u_GFL,value_u_GFM,value_u_G,value_Cost_CON,value_Cost_GEN,value_Cost_Total,Diagnostics] = solve_single_snapshot_planning(mpc,CONF)
%SOLVE_SINGLE_SNAPSHOT_PLANNING 单时刻 GFM-ES 配置优化模型。
%
% 输入：
%   mpc  - MATPOWER 系统数据。
%   CONF - 模型参数结构体，其中 CONF.u_GFL 为已知 GFL 投建方案。
%
% 输出：
%   SCR       - 已建 GFL 节点的经典短路比，非 GFL 节点置零。
%   value_u_G - 同步机启停状态，1 表示投运，0 表示停机。
%   value_u_GFM - GFM-ES 投建结果，1 表示投建，0 表示不投建。
%
% 建模约定：
%   GFL 投建状态已知，不作为优化变量；GFM-ES 是本模型的规划对象；
%   模型仅刻画一个时刻，不包含负荷块或多时刻；
%   经典 SCR 采用 E_th = 1 p.u. 的口径。

%% 1. 整理输入数据
N = CONF.Bn;
u_GFL = CONF.u_GFL(:);

if numel(u_GFL) ~= N
    error('Known GFL construction vector must have CONF.Bn elements.');
end
if any(u_GFL ~= 0 & u_GFL ~= 1)
    error('CONF.u_GFL must use 0/1 values, where 1 = built and 0 = not built.');
end

LoadFactor = CONF.LoadFactor;
if ~isscalar(CONF.SCR_min) || CONF.SCR_min <= 0
    error('CONF.SCR_min must be a positive scalar.');
end

%% 2. 构造网络数据
% 网络矩阵、负荷、成本和导纳相关参数统一由 network 模块生成。
NET = build_single_snapshot_network(mpc, CONF, LoadFactor);

N = NET.N;
G = NET.G;
L = NET.L;

Gen_Loc_Mat = NET.Gen_Loc_Mat;
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
P_Load = NET.P_Load;
Cost_Conv_GFM = NET.Cost_Conv_GFM;
Mask_GFM = NET.Mask_GFM;

Y0 = NET.Y0;
Y_SG_Add = NET.Y_SG_Add;
Y0_all = NET.Y0_all;
B_gfm = NET.B_gfm;
DeltaY = NET.DeltaY;
DeltaY_abs = NET.DeltaY_abs;

Z_bounds = calculate_impedance_bounds(NET, CONF);

%% 3. 定义优化变量
% 二进制变量统一采用常规语义：1 表示投运或投建，0 表示停机或不投建。
u_SG  = binvar(G,1,'full');
u_GFM = binvar(N,1,'full');

P_SG   = sdpvar(G,1,'full');
P_GFL  = sdpvar(N,1,'full');
P_GFM  = sdpvar(N,1,'full');
theta  = sdpvar(N,1,'full');
P_Line = sdpvar(L,1,'full');

Z_real = sdpvar(N,N,'symmetric');
Z_imag = sdpvar(N,N,'symmetric');

% 以下辅助变量用于 Big-M 线性化二进制变量与阻抗矩阵元素的乘积。
W_SGZ_X = sdpvar(G,N,'full');
W_SGZ_R = sdpvar(G,N,'full');
W_GFMZ_X = sdpvar(N,N,'full');
W_GFMZ_R = sdpvar(N,N,'full');
W_GFM = sdpvar(N,1,'full');

%% 4. 建立约束
C = [];

%% 4.1 GFM-ES 规划约束
C_plan = [];

C_plan = [C_plan, sum(u_GFM) >= 0, sum(u_GFM) <= CONF.N_GFM_max];
C_plan = [C_plan, u_GFM(~Mask_GFM) == 0];
C_plan = [C_plan, u_GFL + u_GFM <= 1];

%% 4.2 单时刻潮流与运行约束
C1 = [];
Ref_Bus_Idx = (mpc.bus(:,2) == 3);

% 采用 DC 潮流近似描述节点功率平衡、线路潮流与参考相角。
P_SG_Node = Gen_Loc_Mat*P_SG;
P_Inj     = P_SG_Node + P_GFL + P_GFM - P_Load;
C1 = [C1, P_Inj == Branch_Mat_From*P_Line - Branch_Mat_To*P_Line];

dtheta = theta(Branch_From) - theta(Branch_To);
C1 = [C1, P_Line == Line_B_series .* dtheta];
C1 = [C1, theta(Ref_Bus_Idx) == 0];

C1 = [C1, sum(u_SG) >= 1];
C1 = [C1, P_SG >= Gen_Pmin.*u_SG, P_SG <= Gen_Pmax.*u_SG];
C1 = [C1, P_GFL >= 0, P_GFL <= CONF.PN * u_GFL];
C1 = [C1, P_GFM >= 0, P_GFM <= CONF.PN * u_GFM];

%% 4.3 阻抗矩阵重构约束
C2 = [];

% YZ = I 被拆成实部和虚部约束；CONF.KZ 用于改善数值尺度。
Z_SG_real = Gen_Loc_Mat'*Z_real;
Z_SG_imag = Gen_Loc_Mat'*Z_imag;
U_SG_Off_Mat = repmat(1-u_SG, 1, N);
Z_SG_real_L = Gen_Loc_Mat'*Z_bounds.real_min;
Z_SG_real_U = Gen_Loc_Mat'*Z_bounds.real_max;
Z_SG_imag_L = Gen_Loc_Mat'*Z_bounds.imag_min;
Z_SG_imag_U = Gen_Loc_Mat'*Z_bounds.imag_max;

% 同步机导纳以“全在线”为基准，W_SGZ_* 表示停机机组需要扣除的项。
C2 = [C2, add_binary_product_bounds(W_SGZ_X, Z_SG_imag, U_SG_Off_Mat, Z_SG_imag_L, Z_SG_imag_U)];
C2 = [C2, add_binary_product_bounds(W_SGZ_R, Z_SG_real, U_SG_Off_Mat, Z_SG_real_L, Z_SG_real_U)];

G_sus   = 1/CONF.Xd_Gen;
W_sum_X = Gen_Loc_Mat * W_SGZ_X;
W_sum_R = Gen_Loc_Mat * W_SGZ_R;

% W_GFMZ_* 表示投建 GFM-ES 后对应节点导纳对阻抗方程的影响。
U_GFM_Row = repmat(u_GFM, 1, N);

C2 = [C2, add_binary_product_bounds(W_GFMZ_X, Z_imag, U_GFM_Row, Z_bounds.imag_min, Z_bounds.imag_max)];
C2 = [C2, add_binary_product_bounds(W_GFMZ_R, Z_real, U_GFM_Row, Z_bounds.real_min, Z_bounds.real_max)];

Y0_R = real(Y0_all);
Y0_I = imag(Y0_all);

LHS_Real = Y0_R*Z_real - Y0_I*Z_imag - G_sus*W_sum_X + B_gfm*W_GFMZ_X;
LHS_Imag = Y0_R*Z_imag + Y0_I*Z_real + G_sus*W_sum_R - B_gfm*W_GFMZ_R;

I_vec = reshape(eye(N), [], 1) * CONF.KZ;

C2 = [C2, LHS_Real(:) - I_vec >= -CONF.ERR_TOL, LHS_Real(:) - I_vec <= CONF.ERR_TOL];
C2 = [C2, LHS_Imag(:)         >= -CONF.ERR_TOL, LHS_Imag(:)         <= CONF.ERR_TOL];

%% 4.4 短路电流水平约束
PN_pu  = CONF.PN/CONF.Base_MVA;
X_diag = diag(Z_imag);
X_diag_L = diag(Z_bounds.imag_min);
X_diag_U = diag(Z_bounds.imag_max);
C3 = add_short_circuit_current_constraints(CONF, u_GFL, u_GFM, W_GFM, X_diag, DeltaY_abs, PN_pu, X_diag_L, X_diag_U);

%% 4.5 经典短路比约束
C4 = add_classic_scr_constraints(CONF, u_GFL, X_diag, PN_pu);

C = [C,C_plan,C1,C2,C3,C4];

%% 5. 目标函数
% 目标由单时刻同步机运行成本和 GFM-ES 投建成本组成。
Cost_GEN = sum(Gen_Cost_Quad .* (P_SG.^2) + ...
               Gen_Cost_Lin  .*  P_SG     + ...
               Gen_Cost_Const .* u_SG)*8760;

Cost_GFM_Inv = Cost_Conv_GFM*sum(u_GFM);

Objective = Cost_GEN + Cost_GFM_Inv;

%% 6. 求解器设置与求解
ops = build_gurobi_options();
sol = optimize(C, Objective, ops);

%% 7. 提取优化结果
if sol.problem == 0
    disp('Solver converged successfully.');
else
    disp(['Solver failed with code: ' num2str(sol.problem)]);
end

Diagnostics = build_single_snapshot_diagnostics(sol);

% 成本为了直观对比，选择了归一化到以小时为单位。
value_Cost_Total = value(Objective)/8760;  
value_Cost_GEN   = value(Cost_GEN)/8760;
value_Cost_CON   = value(Cost_GFM_Inv)/8760;

value_P_GFL  = value(P_GFL);
value_P_GFM  = value(P_GFM);
value_P_G    = value(P_SG);
value_theta  = value(theta);
value_P_Line = value(P_Line);

value_u_G    = value(u_SG);
value_u_GFL  = u_GFL;
value_u_GFM  = value(u_GFM);

Z_real_val = value(Z_real)/CONF.KZ;
Z_imag_val = value(Z_imag)/CONF.KZ;
Z_val      = Z_real_val + 1i*Z_imag_val;

% SCR 只对已建 GFL 节点有意义，其余节点保留为 0。
X_diag_val = value(X_diag)/CONF.KZ;
SCR = calculate_classic_scr(X_diag_val, u_GFL, PN_pu);

%% 8. 计算短路电流指标
[SCC_0, SCC_1] = calculate_short_circuit_currents(Z_val, value_u_GFM, u_GFL, CONF, DeltaY, Y0, Y_SG_Add);

end
