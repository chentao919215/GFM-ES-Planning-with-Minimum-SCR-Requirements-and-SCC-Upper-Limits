function NET = build_single_snapshot_network(mpc, CONF, LoadFactor)
%% 本函数功能是构造单时刻优化所需的网络矩阵和基础参数。
%% 1. 生成算例规模参数和位置矩阵
N = CONF.Bn;
G = CONF.Gn;
L = CONF.Ln;

NET = struct();
NET.N = N;
NET.G = G;
NET.L = L;

% 机组-节点关联矩阵
NET.Gen_Loc_Mat = sparse(mpc.gen(:,1), (1:G)', 1, N, G);

% 负荷-节点关联矩阵
NET.Load_Indices = find(mpc.bus(:,3) ~= 0 | mpc.bus(:,4) ~= 0);
Nd = length(NET.Load_Indices);
NET.Nd = Nd;
NET.Load_Loc_Mat = sparse(NET.Load_Indices, (1:Nd)', 1, N, Nd);

% 线路端点和线路-节点关联矩阵
NET.Branch_From = mpc.branch(:,1);
NET.Branch_To   = mpc.branch(:,2);
NET.Branch_Mat_From = sparse(NET.Branch_From, (1:L)', 1, N, L);
NET.Branch_Mat_To   = sparse(NET.Branch_To,   (1:L)', 1, N, L);

%% 2. 生成优化模型所需的基础参数
% 机组成本参数
NET.Gen_Cost_Quad  = mpc.gencost(:,5);
NET.Gen_Cost_Lin   = mpc.gencost(:,6);
NET.Gen_Cost_Const = mpc.gencost(:,7);

% 机组有功出力上下限
NET.Gen_Pmax = mpc.gen(:,9);
NET.Gen_Pmin = 0.05*mpc.gen(:,9);

% 线路潮流计算参数
NET.Line_B_series = CONF.Base_MVA ./ mpc.branch(:,4);
NET.Line_Pmax = mpc.branch(:,6);
NET.Line_Limited = isfinite(NET.Line_Pmax) & NET.Line_Pmax > 0;

% 节点有功负荷
P_Load_Profile = mpc.bus(NET.Load_Indices,3);
P_Load_Base = full(NET.Load_Loc_Mat * P_Load_Profile);
NET.P_Load = LoadFactor * P_Load_Base;

%% 3. 生成节点导纳矩阵
% 线路参数
fb = mpc.branch(:,1);
tb = mpc.branch(:,2);
r  = mpc.branch(:,3);
x  = mpc.branch(:,4);
b  = mpc.branch(:,5);

z    = r + 1i*x;
y    = 1 ./ z;
b_sh = 1i * b / 2;

Y_ff = sparse(fb, fb,  y + b_sh, N, N);
Y_tt = sparse(tb, tb,  y + b_sh, N, N);
Y_ft = sparse(fb, tb, -y,        N, N);
Y_tf = sparse(tb, fb, -y,        N, N);

NET.Y0 = Y_ff + Y_tt + Y_ft + Y_tf;

% 同步机内电势支路等效为节点接地导纳
NET.Y_SG_Add = sparse(1:N, 1:N, (NET.Gen_Loc_Mat*ones(G,1)).*(1/(1i*CONF.Xd_Gen)), N, N);

%% 4. 生成模块化GFM-ES接入相关导纳参数
NET.B_gfm_mod      = -1./CONF.GFM_Module_X_res(:);
NET.DeltaY_mod     = CONF.GFM_Module_DeltaY(:);
NET.DeltaY_abs_mod = abs(NET.DeltaY_mod);

end
