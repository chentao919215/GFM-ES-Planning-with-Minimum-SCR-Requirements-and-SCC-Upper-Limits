function SEC = prepare_converter_security_network(NET, CONF)
%% 式(1)-(3)、(24)及Manuscript附录：安全网络、连通分量与有效电抗界。
% 不枚举配置或UC状态。任一有源网络至少包含一个单源网络，故M矩阵
% 逆的单调性给出逐元素上界：所有单源网络电抗的逐元素最大值。

SEC = struct();
SEC.B0 = NET.B_0_Safety;
SEC.A0 = -SEC.B0;
SEC.N = NET.Safety_N;
SEC.Generator_Location = NET.Safety_Generator_Location_Matrix;
SEC.Unit_Location = NET.Safety_GFM_Unit_Location_Matrix;
SEC.Source_Location = [SEC.Generator_Location, SEC.Unit_Location];
SEC.Source_b = [1./CONF.Xd_Gen(:); 1./CONF.GFM_Unit_X_Res(:)];
SEC.Unit_Delta_b = 1./CONF.GFM_Unit_X_Res(:) - ...
    1./(CONF.GFM_Unit_X_Res(:)+CONF.GFM_Unit_X_Vir(:));
SEC.Source_Bus = zeros(numel(SEC.Source_b), 1);
for j = 1:numel(SEC.Source_b)
    Bus = find(SEC.Source_Location(:, j));
    assert(isscalar(Bus), '每个源必须对应一个保留节点。');
    SEC.Source_Bus(j) = Bus;
end
assert(all(isfinite(SEC.Source_b) & SEC.Source_b > 0), ...
    '源电抗必须为有限正数。');
assert(all(isfinite(SEC.Unit_Delta_b) & SEC.Unit_Delta_b >= 0), ...
    '虚拟电抗必须为有限非负数。');

% 仅按矩阵的非零边判定连通性，不用任意阈值删除弱连接。
Adjacency = SEC.B0 > 0;
Adjacency(1:SEC.N+1:end) = false;
assert(max(conncomp(graph(Adjacency))) == 1, ...
    'Manuscript要求连通的无损安全网络。');
assert(norm(SEC.B0-SEC.B0.', inf) < 1e-9 && ...
    norm(SEC.B0*ones(SEC.N, 1), inf) < 1e-9, ...
    '安全网络必须为无损、无并联支路的对称电纳矩阵。');
SEC.Fault_Components = cell(SEC.N, 1);
for n = 1:SEC.N
    J = setdiff((1:SEC.N).', n);
    Components = conncomp(graph(Adjacency(J, J)));
    for c = unique(Components)
        SEC.Fault_Components{n}{end+1} = J(Components == c);
    end
end

SEC.X_Upper = zeros(SEC.N);
if CONF.Enable_SCR
    for j = 1:numel(SEC.Source_b)
        A = SEC.A0;
        p = SEC.Source_Bus(j);
        A(p, p) = A(p, p)+SEC.Source_b(j);
        X = full(A\eye(SEC.N));
        assert(all(isfinite(X), 'all') && min(X, [], 'all') >= -1e-9, ...
            '无法获得有效的单源电抗界。');
        SEC.X_Upper = max(SEC.X_Upper, X);
    end
    % 只向外放宽浮点舍入误差，不改变物理约束。
    SEC.X_Upper = SEC.X_Upper + 1e-9*max(1, max(SEC.X_Upper, [], 'all'));
end
Nodes = NET.Safety_Retained_Nodes;
SEC.LVRT_On = CONF.V_LVRT_On_Node(Nodes);
SEC.LVRT_Sat = CONF.V_LVRT_Sat_Node(Nodes);
SEC.LVRT_Slope = CONF.KQ_GFL_Node(Nodes).*CONF.I_GFL_N_pu_Node(Nodes);
SEC.LVRT_Max = CONF.Delta_I_GFL_pu_Node(Nodes);
SEC.GFL = NET.Safety_GFL_Reduced_Indices;
Non_GFL = setdiff((1:SEC.N).', SEC.GFL);
SEC.LVRT_Slope(Non_GFL) = 0;
SEC.LVRT_Max(Non_GFL) = 0;
g = SEC.GFL;
assert(all(SEC.LVRT_Sat(g) >= 0 & SEC.LVRT_Sat(g) <= SEC.LVRT_On(g)) && ...
    all(SEC.LVRT_On(g) <= 1) && all(SEC.LVRT_Slope(g) > 0) && ...
    all(abs(SEC.LVRT_Max(g)-SEC.LVRT_Slope(g).* ...
    (SEC.LVRT_On(g)-SEC.LVRT_Sat(g))) < 1e-9), ...
    '节点聚合LVRT参数必须满足Manuscript式(9)的连续三段函数。');
end
