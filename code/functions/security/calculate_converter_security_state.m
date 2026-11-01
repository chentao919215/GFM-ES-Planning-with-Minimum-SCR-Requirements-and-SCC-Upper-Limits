function [SCC, SCR, X] = calculate_converter_security_state( ...
    SEC, CONF, SG_State, Unit_State, Calculate_SCC, Calculate_SCR)
%% Manuscript式(4)-(17)、(24)-(25)：不依赖优化求解器的固定状态安全复算。
% 残压采用带残差回溯的分段牛顿法，直接求解非故障节点的残余电压。

if nargin < 5
    Calculate_SCC = true;
end
if nargin < 6
    Calculate_SCR = true;
end
U = [SG_State(:);Unit_State(:)];
assert(all(abs(U-round(U)) < 1e-6) && all(U >= -1e-6 & U <= 1+1e-6), ...
    '安全复算要求0/1设备状态。');
U = round(U);
Source = SEC.Source_Location*(SEC.Source_b.*U);
A = SEC.A0+diag(Source);
assert(sum(U) >= 1, 'Manuscript式(29)：安全网络无源支撑。');
SCC = nan(SEC.N, 1);
SCR = nan(numel(SEC.GFL), 1);
X = [];
if Calculate_SCR
    X = full(A\eye(SEC.N));
    Nodes = CONF.Safety_Retained_Nodes(SEC.GFL);
    SCR = 1./(diag(X(SEC.GFL, SEC.GFL)).*CONF.PN_GFL_pu_Node(Nodes));
end
if ~Calculate_SCC
    return;
end
RHS = SEC.A0*ones(SEC.N, 1)+Source;
Beta = SEC.Unit_Location*(SEC.Unit_Delta_b.*round(Unit_State(:)));
for n = 1:SEC.N
    for c = 1:numel(SEC.Fault_Components{n})
        Nodes = SEC.Fault_Components{n}{c};
        assert(sum(Source(Nodes)) > 0, ...
            'Manuscript式(30)：故障母线移除后的连通分量无源支撑。');
    end
    J = setdiff((1:SEC.N).', n);
    V = ones(numel(J), 1);
    AJ = A(J, J);
    for Iteration = 1:100
        [Phi, Slope] = local_lvrt(V, SEC, J);
        F = AJ*V-Phi-RHS(J);
        if norm(F, inf) < 1e-10
            break;
        end
        Step = -(AJ+diag(Slope))\F;
        Alpha = 1;
        for Backtrack = 1:50
            Trial = V+Alpha*Step;
            Phi_Trial = local_lvrt(Trial, SEC, J);
            if norm(AJ*Trial-Phi_Trial-RHS(J), 2) <= ...
                    (1-1e-4*Alpha)*norm(F, 2)
                break;
            end
            Alpha = Alpha/2;
        end
        V = Trial;
    end
    Phi = local_lvrt(V, SEC, J);
    Residual = norm(AJ*V-Phi-RHS(J), inf);
    assert(Residual < 1e-8 && all(V > 0 & V <= 1+1e-9), ...
        '残余电压求解未收敛到Manuscript规定的正实解。');
    SCC(n) = (SEC.B0(n, J)*V+RHS(n)-Beta(n)+SEC.LVRT_Max(n))*CONF.Base_kA;
end
end

function [Phi, Slope] = local_lvrt(V, SEC, J)
%% 按残余电压计算分段LVRT附加无功电流及对应斜率。
Raw = SEC.LVRT_Slope(J).*(SEC.LVRT_On(J)-V);
Phi = min(SEC.LVRT_Max(J), max(0, Raw));
Slope = SEC.LVRT_Slope(J).*(Raw > 0 & Raw < SEC.LVRT_Max(J));
end
