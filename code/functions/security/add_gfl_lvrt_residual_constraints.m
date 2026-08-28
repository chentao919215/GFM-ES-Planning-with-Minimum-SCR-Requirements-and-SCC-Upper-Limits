function [C_LVRT, C_McCormick] = add_gfl_lvrt_residual_constraints( ...
    NET, CONF, u_SG_SCR, u_GFM_Module, V_F, V0, Vlin, Vsat, ...
    D0, Dlin, Dsat, Delta_I, Zeta_SG, Zeta_GFM)
%% 构造《ver_2》三段式LVRT与交集工况残余电压反馈约束。
% 本函数中的节点维度均采用Kron降阶后的安全网络维度。

CONF = normalize_multiple_snapshot_conf(CONF);

NS = NET.Safety_N;
G = NET.G;
M = CONF.GFM_Module_Count;
D = CONF.TypicalDayCount;
GFL_Reduced = NET.Safety_GFL_Reduced_Indices(:);
GFL_Count = numel(GFL_Reduced);

if size(V_F,1) ~= NS || size(V_F,2) ~= NS || size(V_F,3) ~= D
    error('残余电压变量维度与安全网络不一致。');
end
if size(Delta_I,1) ~= NS || size(Delta_I,2) ~= GFL_Count || ...
        size(Delta_I,3) ~= D
    error('LVRT增量电流变量维度与安全网络不一致。');
end
if size(Zeta_SG,1) ~= G || size(Zeta_SG,2) ~= NS || ...
        size(Zeta_SG,3) ~= NS || size(Zeta_SG,4) ~= D
    error('同步机LVRT McCormick变量维度不一致。');
end
if size(Zeta_GFM,1) ~= M || size(Zeta_GFM,2) ~= NS || ...
        size(Zeta_GFM,3) ~= NS || size(Zeta_GFM,4) ~= D
    error('GFM-ES LVRT McCormick变量维度不一致。');
end

B0 = -imag(NET.Y_0_Safety);
b_SG = -imag(1./(1i*CONF.Xd_Gen(:)));
b_GFM = 1./CONF.GFM_Module_X_Res(:);

% 文档2.4.3 GFL-WG故障电压与LVRT增量电流约束，式(1.52)-(1.69)。
C_LVRT = [V_F(:) >= 0, V_F(:) <= 1, ...
    Delta_I >= 0, Delta_I <= repmat( ...
    CONF.Delta_I_GFL_pu_Node(NET.Safety_Retained_Nodes(GFL_Reduced)).',NS,1,D)];
C_McCormick = [];

for d = 1:D
    C_LVRT = [C_LVRT, diag(V_F(:,:,d)) == 0]; %#ok<AGROW>

    for p = 1:NS
        % 文档2.5 McCormick线性化约束，式(1.88)：同步机状态与残余电压乘积。
        U_SG = repmat(u_SG_SCR(:,d),1,NS);
        X_SG = repmat(V_F(:,p,d).',G,1);
        C_McCormick = [C_McCormick, add_binary_product_bounds( ...
            Zeta_SG(:,:,p,d),X_SG,U_SG,zeros(G,NS),ones(G,NS))]; %#ok<AGROW>

        % 文档2.5 McCormick线性化约束，式(1.88)：GFM-ES状态与残余电压乘积。
        U_GFM = repmat(u_GFM_Module,1,NS);
        X_GFM = repmat(V_F(:,p,d).',M,1);
        C_McCormick = [C_McCormick, add_binary_product_bounds( ...
            Zeta_GFM(:,:,p,d),X_GFM,U_GFM,zeros(M,NS),ones(M,NS))]; %#ok<AGROW>

        Original_Node = NET.Safety_Retained_Nodes(p);
        GFL_Index = find(GFL_Reduced == p,1);
        Module_Index = find(NET.Safety_GFM_Module_Location_Matrix(p,:));

        for n = 1:NS
            if p == n
                % 故障节点GFL-WG的饱和增量电流由SCC约束直接处理，
                % 不进入非故障节点LVRT反馈项。
                if ~isempty(GFL_Index)
                    C_LVRT = [C_LVRT, ...
                        D0(n,GFL_Index,d) == 0, ...
                        Dlin(n,GFL_Index,d) == 0, ...
                        Dsat(n,GFL_Index,d) == 0, ...
                        V0(n,GFL_Index,d) == 0, ...
                        Vlin(n,GFL_Index,d) == 0, ...
                        Vsat(n,GFL_Index,d) == 0, ...
                        Delta_I(n,GFL_Index,d) == 0]; %#ok<AGROW>
                end
                continue;
            end

            if ~isempty(GFL_Index)
                von = CONF.V_LVRT_On_Node(Original_Node);
                vsat = CONF.V_LVRT_Sat_Node(Original_Node);
                Delta_i = Delta_I(n,GFL_Index,d);
                C_LVRT = [C_LVRT, ...
                    D0(n,GFL_Index,d)+Dlin(n,GFL_Index,d)+Dsat(n,GFL_Index,d) == 1, ...
                    von*D0(n,GFL_Index,d) <= V0(n,GFL_Index,d), ...
                    V0(n,GFL_Index,d) <= D0(n,GFL_Index,d), ...
                    vsat*Dlin(n,GFL_Index,d) <= Vlin(n,GFL_Index,d), ...
                    Vlin(n,GFL_Index,d) <= von*Dlin(n,GFL_Index,d), ...
                    0 <= Vsat(n,GFL_Index,d), ...
                    Vsat(n,GFL_Index,d) <= vsat*Dsat(n,GFL_Index,d), ...
                    Delta_i == CONF.KQ_GFL_Node(Original_Node)* ...
                        CONF.I_GFL_N_pu_Node(Original_Node)* ...
                        (von*Dlin(n,GFL_Index,d)-Vlin(n,GFL_Index,d)) + ...
                        CONF.Delta_I_GFL_pu_Node(Original_Node)* ...
                        Dsat(n,GFL_Index,d), ...
                    V_F(n,p,d) == ...
                        V0(n,GFL_Index,d)+Vlin(n,GFL_Index,d)+Vsat(n,GFL_Index,d)]; %#ok<AGROW>
                % 保持式(1.61)至式(1.62)的符号约定：DeltaI_GFL作为
                % 残余电压平衡方程右端的正标量电流项。
                rhs = Delta_i;
            else
                rhs = 0;
            end

            SG_At_p = b_SG.*full(NET.Safety_Generator_Location_Matrix(p,:)).';
            SG_Term = SG_At_p.'*(Zeta_SG(:,n,p,d)-u_SG_SCR(:,d));
            if isempty(Module_Index)
                GFM_Term = 0;
            else
                GFM_Term = b_GFM(Module_Index).' * ...
                    (Zeta_GFM(Module_Index,n,p,d)-u_GFM_Module(Module_Index));
            end
            lhs = sum(B0(p,[1:n-1,n+1:NS]).* ...
                V_F(n,[1:n-1,n+1:NS],d)) + SG_Term + GFM_Term;
            C_LVRT = [C_LVRT, lhs == rhs]; %#ok<AGROW>
        end
    end
end
end
