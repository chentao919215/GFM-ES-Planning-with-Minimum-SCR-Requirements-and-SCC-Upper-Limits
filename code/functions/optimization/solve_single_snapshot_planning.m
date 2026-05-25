function [SCC_0,SCC_1,value_P_Line,value_theta,value_P_G,value_P_GFL,value_P_GFM,...
    SCR,Z_val,value_u_GFL,value_u_GFM,value_u_G,value_Cost_CON,value_Cost_GEN,value_Cost_Total,Diagnostics] = solve_single_snapshot_planning(mpc,CONF)
%% 本函数功能是构建并求解单时刻GFM-ES配置优化模型。
%% 输入:
%  mpc:MATPOWER系统数据。
%  CONF:模型参数结构体。

%% 输出:
%  SCR:已建GFL节点的经典短路比，非GFL节点置零。
%  value_u_G:同步机启停状态，1表示投运，0表示停机。
%  value_u_GFM:GFM-ES投建结果，1表示投建，0表示不投建。

%% 建模约定:
%  GFL投建状态已知，不作为优化变量；GFM-ES是本模型的规划对象；
%  模型仅刻画一个时刻，不包含负荷块或多时刻；
%  经典SCR采用E_th=1p.u.，X_th为次暂态电抗的口径。

%% 1. 整理输入数据
% 已建GFL状态由参数文件给定，不作为本函数中的优化变量
u_GFL = CONF.u_GFL(:);
LoadFactor = CONF.LoadFactor;

%% 2. 构造网络数据
% 网络矩阵、负荷、成本和导纳相关参数统一由network模块生成。
NET = build_single_snapshot_network(mpc, CONF, LoadFactor);

% 算例规模参数
N = NET.N;
G = NET.G;
L = NET.L;

% 位置矩阵和线路端点信息
Gen_Loc_Mat = NET.Gen_Loc_Mat;
Branch_From = NET.Branch_From;
Branch_To = NET.Branch_To;
Branch_Mat_From = NET.Branch_Mat_From;
Branch_Mat_To = NET.Branch_Mat_To;

% 机组成本参数
Gen_Cost_Quad  = NET.Gen_Cost_Quad;
Gen_Cost_Lin   = NET.Gen_Cost_Lin;
Gen_Cost_Const = NET.Gen_Cost_Const;

% 机组出力上下限
Gen_Pmax = NET.Gen_Pmax;
Gen_Pmin = NET.Gen_Pmin;

% 潮流、负荷和GFM-ES候选节点参数
Line_B_series = NET.Line_B_series;
P_Load = NET.P_Load;
Cost_Conv_GFM = NET.Cost_Conv_GFM;
Mask_GFM = NET.Mask_GFM;

% 导纳矩阵和GFM-ES接入导纳参数
Y0 = NET.Y0;
Y_SG_Add = NET.Y_SG_Add;
Y0_all = NET.Y0_all;
B_gfm = NET.B_gfm;
DeltaY = NET.DeltaY;
DeltaY_abs = NET.DeltaY_abs;

% 阻抗矩阵元素上下界用于二进制-连续变量乘积的McCormick线性化
Z_bounds = calculate_impedance_bounds(NET, CONF);

%% 3. 定义优化变量
% 二进制变量统一采用常规语义:1表示投运或投建，0表示停机或不投建。
u_SG  = binvar(G,1,'full');
u_GFM = binvar(N,1,'full');

% 连续运行变量
P_SG   = sdpvar(G,1,'full');
P_GFL  = sdpvar(N,1,'full');
P_GFM  = sdpvar(N,1,'full');
theta  = sdpvar(N,1,'full');
P_Line = sdpvar(L,1,'full');

% 节点阻抗矩阵的实部和虚部
Z_real = sdpvar(N,N,'symmetric');
Z_imag = sdpvar(N,N,'symmetric');

% 以下辅助变量用于基于阻抗元素上下界的McCormick线性化。
W_SGZ_X = sdpvar(G,N,'full');
W_SGZ_R = sdpvar(G,N,'full');
W_GFMZ_X = sdpvar(N,N,'full');
W_GFMZ_R = sdpvar(N,N,'full');
W_GFM = sdpvar(N,1,'full');

%% 4. 建立约束
C = [];

%% 4.1 GFM-ES规划约束
C_plan = [];

% GFM-ES投建数量上限
C_plan = [C_plan, sum(u_GFM) >= 0, sum(u_GFM) <= CONF.N_GFM_max];

% GFM-ES只能在候选节点投建，且不能与已建GFL节点重叠
C_plan = [C_plan, u_GFM(~Mask_GFM) == 0];
C_plan = [C_plan, u_GFL + u_GFM <= 1];

%% 4.2 单时刻潮流与运行约束
C1 = [];
Ref_Bus_Idx = (mpc.bus(:,2) == 3);

% 采用DC潮流近似描述节点功率平衡、线路潮流与参考相角。
% 节点注入功率=同步机出力+GFL出力+GFM-ES出力-节点负荷
P_SG_Node = Gen_Loc_Mat*P_SG;
P_Inj     = P_SG_Node + P_GFL + P_GFM - P_Load;
C1 = [C1, P_Inj == Branch_Mat_From*P_Line - Branch_Mat_To*P_Line];

% 线路潮流和相角约束
dtheta = theta(Branch_From) - theta(Branch_To);
C1 = [C1, P_Line == Line_B_series .* dtheta];
C1 = [C1, theta(Ref_Bus_Idx) == 0];

% 同步机、GFL和GFM-ES出力约束
C1 = [C1, sum(u_SG) >= 1];
C1 = [C1, P_SG >= Gen_Pmin.*u_SG, P_SG <= Gen_Pmax.*u_SG];
C1 = [C1, P_GFL >= 0, P_GFL <= CONF.PN * u_GFL];
C1 = [C1, P_GFM >= 0, P_GFM <= CONF.PN * u_GFM];

%% 4.3 阻抗矩阵重构约束
C2 = [];

% YZ=I被拆成实部和虚部约束；CONF.KZ用于改善数值尺度。
Z_SG_real = Gen_Loc_Mat'*Z_real;
Z_SG_imag = Gen_Loc_Mat'*Z_imag;
U_SG_Off_Mat = repmat(1-u_SG, 1, N);
Z_SG_real_L = Gen_Loc_Mat'*Z_bounds.real_min;
Z_SG_real_U = Gen_Loc_Mat'*Z_bounds.real_max;
Z_SG_imag_L = Gen_Loc_Mat'*Z_bounds.imag_min;
Z_SG_imag_U = Gen_Loc_Mat'*Z_bounds.imag_max;

% 同步机导纳以“全在线”为基准，W_SGZ_*表示停机机组需要扣除的项。
C2 = [C2, add_binary_product_bounds(W_SGZ_X, Z_SG_imag, U_SG_Off_Mat, Z_SG_imag_L, Z_SG_imag_U)];
C2 = [C2, add_binary_product_bounds(W_SGZ_R, Z_SG_real, U_SG_Off_Mat, Z_SG_real_L, Z_SG_real_U)];

G_sus   = 1/CONF.Xd_Gen;
W_sum_X = Gen_Loc_Mat * W_SGZ_X;
W_sum_R = Gen_Loc_Mat * W_SGZ_R;

% W_GFMZ_*表示投建GFM-ES后对应节点导纳对阻抗方程的影响。
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
% 根据节点自阻抗和GFM-ES投建状态限制故障电流水平
PN_pu  = CONF.PN/CONF.Base_MVA;
X_diag = diag(Z_imag);
X_diag_L = diag(Z_bounds.imag_min);
X_diag_U = diag(Z_bounds.imag_max);
C3 = add_short_circuit_current_constraints(CONF, u_GFL, u_GFM, W_GFM, X_diag, DeltaY_abs, PN_pu, X_diag_L, X_diag_U);

%% 4.5 经典短路比约束
% 已建GFL节点需要满足经典SCR下限
C4 = add_classic_scr_constraints(CONF, u_GFL, X_diag, PN_pu);

C = [C,C_plan,C1,C2,C3,C4];

%% 5. 目标函数
% 目标由单时刻同步机运行成本和GFM-ES投建成本组成。
Cost_GEN = sum(Gen_Cost_Quad .* (P_SG.^2) + ...
               Gen_Cost_Lin  .*  P_SG     + ...
               Gen_Cost_Const .* u_SG)*8760;

Cost_GFM_Inv = Cost_Conv_GFM*sum(u_GFM);

Objective = Cost_GEN + Cost_GFM_Inv;

%% 6. 求解器设置与求解
% 求解器参数统一由build_gurobi_options函数设置
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

% 阻抗矩阵在模型中经过CONF.KZ缩放，输出时还原到原始标幺尺度。
Z_real_val = value(Z_real)/CONF.KZ;
Z_imag_val = value(Z_imag)/CONF.KZ;
Z_val      = Z_real_val + 1i*Z_imag_val;

% SCR只对已建GFL节点有意义，其余节点保留为0。
X_diag_val = value(X_diag)/CONF.KZ;
SCR = calculate_classic_scr(X_diag_val, u_GFL, PN_pu);

%% 8. 计算短路电流指标
% 分别计算未投建GFM-ES和投建GFM-ES后的短路电流水平
[SCC_0, SCC_1] = calculate_short_circuit_currents(Z_val, value_u_GFM, u_GFL, CONF, DeltaY, Y0, Y_SG_Add);

end
