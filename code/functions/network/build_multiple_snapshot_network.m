function NET = build_multiple_snapshot_network(mpc, CONF)
%% 本函数功能是构造多时刻优化所需的网络矩阵和逐时参数。
%% 1. 生成算例规模参数和位置矩阵
N = CONF.Bn;
G = CONF.Gn;
L = CONF.Ln;

NET   = struct();
NET.N = N;
NET.G = G;
NET.L = L;

% 机组-节点关联矩阵。
NET.Gen_Loc_Mat = sparse(mpc.gen(:,1),(1:G)',1,N,G);

% 负荷-节点关联矩阵。
NET.Load_Indices = find(mpc.bus(:,3) ~= 0 | mpc.bus(:,4) ~= 0);
NET.Nd           = numel(NET.Load_Indices);
NET.Load_Loc_Mat = sparse(NET.Load_Indices,(1:NET.Nd)',1,N,NET.Nd);

% 线路端点和线路-节点关联矩阵。
NET.Branch_From     = mpc.branch(:,1);
NET.Branch_To       = mpc.branch(:,2);
NET.Branch_Mat_From = sparse(NET.Branch_From,(1:L)',1,N,L);
NET.Branch_Mat_To   = sparse(NET.Branch_To,(1:L)',1,N,L);

%% 2. 生成优化模型基础参数
% 同步机成本与有功出力上下限。
NET.Gen_Cost_Quad  = mpc.gencost(:,5);
NET.Gen_Cost_Lin   = mpc.gencost(:,6);
NET.Gen_Cost_Const = mpc.gencost(:,7);
NET.Gen_Pmax       = mpc.gen(:,9);
NET.Gen_Pmin       = CONF.Gen_Pmin;

% 线路潮流计算参数。
NET.Line_B_series = CONF.Base_MVA./mpc.branch(:,4);
NET.Line_Pmax     = mpc.branch(:,6);
NET.Line_Limited  = isfinite(NET.Line_Pmax) & NET.Line_Pmax > 0;

% 基准节点有功负荷。
NET.P_Load = full(NET.Load_Loc_Mat*mpc.bus(NET.Load_Indices,3));

% 多时刻负荷、GFL-WG可用出力和运行权重。
NET.P_Load_Profile          = CONF.P_Load_Profile;
NET.P_GFL_Available_Profile = CONF.P_GFL_Available_Profile;
NET.OperatingWeights_Hours  = CONF.OperatingWeights_Hours;

%% 3. 生成节点导纳矩阵
fb = mpc.branch(:,1);
tb = mpc.branch(:,2);
r  = mpc.branch(:,3);
x  = mpc.branch(:,4);
b  = mpc.branch(:,5);

y    = 1./(r+1i*x);
b_sh = 1i*b/2;

Y_ff   = sparse(fb,fb,y+b_sh,N,N);
Y_tt   = sparse(tb,tb,y+b_sh,N,N);
Y_ft   = sparse(fb,tb,-y,N,N);
Y_tf   = sparse(tb,fb,-y,N,N);
NET.Y0 = Y_ff+Y_tt+Y_ft+Y_tf;

% 同步机内电势支路等效为节点接地导纳。
Y_SG_Node    = (NET.Gen_Loc_Mat*ones(G,1)).*(1/(1i*CONF.Xd_Gen));
NET.Y_SG_Add = sparse(1:N,1:N,Y_SG_Node,N,N);

%% 4. 生成模块化GFM-ES导纳参数
NET.B_gfm_mod      = -1./CONF.GFM_Module_X_res(:);
NET.DeltaY_mod     = CONF.GFM_Module_DeltaY(:);
NET.DeltaY_abs_mod = abs(NET.DeltaY_mod);

end
