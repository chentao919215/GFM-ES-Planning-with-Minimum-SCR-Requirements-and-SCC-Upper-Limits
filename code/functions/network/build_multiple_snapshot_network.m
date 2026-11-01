function NET = build_multiple_snapshot_network(mpc, CONF)
%% 本函数功能是构造多时段优化所需的网络矩阵和逐时参数。

%% 1. 生成算例规模参数和位置矩阵
N = CONF.Bn;
G = CONF.Gn;
L = CONF.Ln;

NET = struct();
NET.N = N;
NET.G = G;
NET.L = L;

% 机组-节点关联矩阵。
NET.Generator_Location_Matrix = sparse(mpc.gen(:, 1), (1:G)', 1, N, G);

% 负荷-节点关联矩阵。
NET.Load_Indices = find(mpc.bus(:, 3) ~= 0 | mpc.bus(:, 4) ~= 0);
NET.N_d = numel(NET.Load_Indices);
NET.Load_Location_Matrix = sparse(NET.Load_Indices, (1:NET.N_d)', 1, N, NET.N_d);

% 线路端点和线路-节点关联矩阵。
NET.Branch_From = mpc.branch(:, 1);
NET.Branch_To = mpc.branch(:, 2);
NET.Branch_Matrix_From = sparse(NET.Branch_From, (1:L)', 1, N, L);
NET.Branch_Matrix_To = sparse(NET.Branch_To, (1:L)', 1, N, L);

%% 2. 生成优化模型基础参数
% 同步机成本与有功出力上下限。
NET.Generator_Cost_Quadratic = mpc.gencost(:, 5);
NET.Generator_Cost_Linear = mpc.gencost(:, 6);
NET.Generator_Cost_Constant = mpc.gencost(:, 7);
NET.Generator_P_Max = mpc.gen(:, 9);
NET.Generator_P_Min = CONF.Gen_Pmin;

% 线路潮流计算参数。
NET.Line_B_Series = CONF.Base_MVA./mpc.branch(:, 4);
Active_Branch = true(L, 1);
assert(isequal(mpc.bus(:, 1), (1:N).'), ...
    '请先将MATPOWER节点编号转换为连续内部编号1:N。');
if size(mpc.branch, 2) >= 11
    Active_Branch = mpc.branch(:, 11) ~= 0;
end
assert(all(isfinite(mpc.branch(Active_Branch, 4)) & ...
    mpc.branch(Active_Branch, 4) > 0), ...
    '电抗主导网络要求在运线路电抗为有限正数。');
NET.Line_B_Series(~Active_Branch) = 0;
NET.Line_P_Max = mpc.branch(:, 6);
NET.Line_Limited = isfinite(NET.Line_P_Max) & NET.Line_P_Max > 0;

% 基准节点有功负荷。
NET.P_Load = full(NET.Load_Location_Matrix*mpc.bus(NET.Load_Indices, 3));

% 多时段负荷、场景化GFL-WG可用出力、场景概率和运行权重。
NET.P_Load_Profile = CONF.P_Load_Profile;
NET.P_GFL_Available_Scenarios = CONF.P_GFL_Available_Scenarios;
NET.Wind_Scenario_Probabilities = CONF.WindScenarioProbabilities;
NET.Operating_Weights_Hours = CONF.OperatingWeights_Hours;

%% 3. 生成正常网络节点导纳矩阵
% 本矩阵保留线路串联电阻和并联电纳，不用于Manuscript中的安全网络。
fb = mpc.branch(:, 1);
tb = mpc.branch(:, 2);
r = mpc.branch(:, 3);
x = mpc.branch(:, 4);
b = mpc.branch(:, 5);

y = 1./(r+1i*x);
b_Sh = 1i*b/2;
y(~Active_Branch) = 0;
b_Sh(~Active_Branch) = 0;

Y_Ff = sparse(fb, fb, y+b_Sh, N, N);
Y_Tt = sparse(tb, tb, y+b_Sh, N, N);
Y_Ft = sparse(fb, tb, -y, N, N);
Y_Tf = sparse(tb, fb, -y, N, N);
NET.Y_0 = Y_Ff+Y_Tt+Y_Ft+Y_Tf;

% 同步机内电势支路等效为节点接地导纳；每台机组允许使用独立次暂态电抗。
Y_SG_Unit = 1./(1i*CONF.Xd_Gen(:));
Y_SG_Node = NET.Generator_Location_Matrix*Y_SG_Unit;
NET.Y_SG_Add = sparse(1:N, 1:N, Y_SG_Node, N, N);

%% 4. 构造Kron降阶安全网络
% Manuscript第II-A节，式(1)：B_0=Im[Y_0]。安全网络采用无损
% 感性近似，在Kron消元前忽略线路串联电阻和并联电纳。
Y_Series_Safety = 1./(1i*x);
Y_Series_Safety(~Active_Branch) = 0;
Y_Safety_Ff = sparse(fb, fb, Y_Series_Safety, N, N);
Y_Safety_Tt = sparse(tb, tb, Y_Series_Safety, N, N);
Y_Safety_Ft = sparse(fb, tb, -Y_Series_Safety, N, N);
Y_Safety_Tf = sparse(tb, fb, -Y_Series_Safety, N, N);
NET.Y_0_Safety_Full = Y_Safety_Ff+Y_Safety_Tt+Y_Safety_Ft+Y_Safety_Tf;
NET.B_0_Safety_Full = imag(NET.Y_0_Safety_Full);

% SCC与SCR工况共用同一保留节点集合和原节点-降阶节点映射。
Safety_Nodes = CONF.Safety_Retained_Nodes(:);
Eliminated_Nodes = setdiff((1:N).', Safety_Nodes, 'stable');
NS = numel(Safety_Nodes);

NET.Safety_Retained_Nodes = Safety_Nodes;
NET.Safety_Eliminated_Nodes = Eliminated_Nodes;
NET.Safety_Original_To_Reduced = CONF.Safety_Original_To_Reduced(:);
NET.Safety_N = NS;
NET.Safety_GFL_Original_Nodes = CONF.Safety_GFL_Original_Nodes(:);
NET.Safety_GFL_Reduced_Indices = CONF.Safety_GFL_Reduced_Indices(:);
NET.Safety_GFL_Count = CONF.Safety_GFL_Count;

% 所有状态相关导纳节点均被保留，因此设备状态导纳可在Kron消元后直接叠加。
NET.Safety_Generator_Location_Matrix = NET.Generator_Location_Matrix(Safety_Nodes, :);
NET.Safety_GFM_Unit_Location_Matrix = ...
    CONF.GFM_Unit_Loc_Mat(Safety_Nodes, :);
Y_SS = NET.Y_0_Safety_Full(Safety_Nodes, Safety_Nodes);
if isempty(Eliminated_Nodes)
    NET.Y_0_Safety = Y_SS;
else
    Y_SE = NET.Y_0_Safety_Full(Safety_Nodes, Eliminated_Nodes);
    Y_ES = NET.Y_0_Safety_Full(Eliminated_Nodes, Safety_Nodes);
    Y_EE = full(NET.Y_0_Safety_Full(Eliminated_Nodes, Eliminated_Nodes));
    if rcond(Y_EE) < 1e-12
        error('Kron消元失败：被消元节点对应的基础导纳子矩阵不可逆。');
    end
    NET.Y_0_Safety = sparse(Y_SS-Y_SE*(Y_EE\Y_ES));
end
NET.B_0_Safety = imag(NET.Y_0_Safety);

Y_SG_Node_Safety = NET.Safety_Generator_Location_Matrix*Y_SG_Unit;
NET.Y_SG_Add_Safety = sparse(1:NS, 1:NS, Y_SG_Node_Safety, NS, NS);

%% 5. 生成GFM-ES导纳参数
NET.B_GFM_Unit = -1./CONF.GFM_Unit_X_Res(:);
NET.Delta_Y_Unit = CONF.GFM_Unit_DeltaY(:);
NET.Delta_Y_Abs_Unit = CONF.GFM_Unit_DeltaY_abs(:);

end
