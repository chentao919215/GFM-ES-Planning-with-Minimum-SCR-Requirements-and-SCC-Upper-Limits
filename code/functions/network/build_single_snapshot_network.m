function NET = build_single_snapshot_network(mpc, CONF, LoadFactor)
%BUILD_SINGLE_SNAPSHOT_NETWORK 构造单时刻优化所需的网络矩阵和基础参数。

N = CONF.Bn;
G = CONF.Gn;
L = CONF.Ln;

NET = struct();
NET.N = N;
NET.G = G;
NET.L = L;

NET.Gen_Loc_Mat = sparse(mpc.gen(:,1), (1:G)', 1, N, G);

NET.Load_Indices = find(mpc.bus(:,3) ~= 0 | mpc.bus(:,4) ~= 0);
Nd = length(NET.Load_Indices);
NET.Nd = Nd;
NET.Load_Loc_Mat = sparse(NET.Load_Indices, (1:Nd)', 1, N, Nd);

NET.Branch_From = mpc.branch(:,1);
NET.Branch_To   = mpc.branch(:,2);
NET.Branch_Mat_From = sparse(NET.Branch_From, (1:L)', 1, N, L);
NET.Branch_Mat_To   = sparse(NET.Branch_To,   (1:L)', 1, N, L);

NET.Gen_Cost_Quad  = mpc.gencost(:,5);
NET.Gen_Cost_Lin   = mpc.gencost(:,6);
NET.Gen_Cost_Const = mpc.gencost(:,7);

NET.Gen_Pmax = mpc.gen(:,9);
NET.Gen_Pmin = mpc.gen(:,10);

NET.Line_B_series = CONF.Base_MVA ./ mpc.branch(:,4);
P_Load_Profile = mpc.bus(NET.Load_Indices,3);
P_Load_Base = full(NET.Load_Loc_Mat * P_Load_Profile);
NET.P_Load = LoadFactor * P_Load_Base;

NET.Cost_Conv_GFM = CONF.Cost_Conv_GFM;

cand_GFM = CONF.GFM_Candidates(:)';
NET.Mask_GFM = false(N,1);
NET.Mask_GFM(cand_GFM) = true;

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

NET.Y_SG_Add = sparse(1:N, 1:N, (NET.Gen_Loc_Mat*ones(G,1)).*(1/(1i*CONF.Xd_Gen)), N, N);
NET.Y0_all   = NET.Y0 + NET.Y_SG_Add;

NET.B_gfm = 1/CONF.X_GFM_res;

NET.DeltaY = 1/(1i*(CONF.X_GFM_res+CONF.X_GFM_vir)) - 1/(1i*CONF.X_GFM_res);
NET.DeltaY_abs = abs(NET.DeltaY)*ones(N,1);

end
