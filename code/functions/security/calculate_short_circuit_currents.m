function [SCC_0, SCC_1, SCC_2] = calculate_short_circuit_currents( ...
    NET, CONF, Value_u_GFM_Module, u_GFL, Value_u_G_SCC, ...
    Z_SCC_Optimization, Phi_GFL_Scaled)
%% 统一计算全同步机基准、优化模型和后验复算三组短路电流结果。
% SCC_0：基础网络投入全部同步机，不考虑规划新增GFM-ES。
% SCC_1：直接采用优化模型的阻抗近似和保守GFL-WG转移项。
% SCC_2：固定最优投建与同步机聚合状态，独立重构故障网络并复算。

CONF = normalize_multiple_snapshot_conf(CONF);

N = NET.N;
D = size(Value_u_G_SCC,2);
G = NET.G;
M = CONF.GFM_Module_Count;
Safety_Nodes = NET.Safety_Retained_Nodes(:);
NS = numel(Safety_Nodes);

if ~isequal(size(Value_u_G_SCC), [G D]) || ...
        numel(Value_u_GFM_Module) ~= M || numel(u_GFL) ~= N
    error('SCC后处理输入的设备状态维度与网络规模不一致。');
end
if size(Z_SCC_Optimization,1) ~= NS || ...
        size(Z_SCC_Optimization,2) ~= NS || ...
        size(Z_SCC_Optimization,3) ~= D || ...
        ~isequal(size(Phi_GFL_Scaled), [NS D])
    error('优化模型SCC阻抗或GFL-WG转移项维度与安全网络不一致。');
end

Value_u_GFM_Module = validate_binary_result(Value_u_GFM_Module(:), ...
    'GFM-ES模块投建状态');
Value_u_G_SCC = validate_binary_result(Value_u_G_SCC, ...
    '同步机SCC聚合状态');
u_GFL = validate_binary_result(u_GFL(:), 'GFL-WG节点状态');

%% 1. SCC_1：优化模型计算结果
% 对应文档式(1.74)-(1.85)。非安全网络保留节点按定义保持为0。
SCC_1 = zeros(N,D);
GFM_Delta_Node = CONF.GFM_Module_Loc_Mat * ...
    (CONF.GFM_Module_DeltaY_abs(:).*Value_u_GFM_Module);
GFL_Fault_Increment_Node = CONF.Delta_I_GFL_pu_Node(:).*u_GFL;

for d = 1:D
    X_Diag = imag(diag(Z_SCC_Optimization(:,:,d)));
    if any(~isfinite(X_Diag)) || any(X_Diag <= 0)
        error('典型日%d的优化模型SCC自阻抗无效。',d);
    end
    SCC_1(Safety_Nodes,d) = ((1+Phi_GFL_Scaled(:,d)/CONF.KZ)./X_Diag - ...
        GFM_Delta_Node(Safety_Nodes) + ...
        GFL_Fault_Increment_Node(Safety_Nodes))*CONF.Base_kA;
end

%% 2. SCC_0：全同步机基准结果
% 基础网络投入全部同步机，并计入故障节点GFL-WG增量电流及非故障
% 节点GFL-WG的LVRT转移贡献；规划新增GFM-ES模块全部取未投建。
SCC_0_One_Day = calculate_posthoc_scc(NET, CONF, zeros(M,1), ...
    u_GFL, ones(G,1), '全同步机基准工况');
SCC_0 = repmat(SCC_0_One_Day,1,D);

%% 3. SCC_2：后验复算结果
% 每个典型日仅固定最优离散状态，重新构造完整故障网络；本段不读取
% SCC_1使用的阻抗辅助变量、LVRT辅助变量或保守转移系数。
SCC_2 = zeros(N,D);
for d = 1:D
    SCC_2(:,d) = calculate_posthoc_scc(NET, CONF, ...
        Value_u_GFM_Module, u_GFL, Value_u_G_SCC(:,d), ...
        sprintf('典型日%d后验复算工况',d));
end

end

function SCC = calculate_posthoc_scc( ...
    NET, CONF, Module_State, u_GFL, SG_State, State_Label)
%% 按固定设备状态独立重构网络并复算全部原始节点的总SCC。

N = NET.N;
SG_Node_Admittance = NET.Generator_Location_Matrix * ...
    (SG_State.*(1./(1i*CONF.Xd_Gen(:))));
GFM_Node_Admittance = CONF.GFM_Module_Loc_Mat * ...
    (Module_State.*(1./(1i*CONF.GFM_Module_X_Res(:))));
Y_Fault = NET.Y_0 + spdiags( ...
    SG_Node_Admittance+GFM_Node_Admittance,0,N,N);
if rcond(full(Y_Fault)) < 1e-12
    error('%s的节点导纳矩阵不可逆。',State_Label);
end
Z_Fault = full(Y_Fault)\eye(N);

SG_Source_Susceptance = NET.Generator_Location_Matrix * ...
    (SG_State.*(-imag(1./(1i*CONF.Xd_Gen(:)))));
GFM_Source_Susceptance = CONF.GFM_Module_Loc_Mat * ...
    (Module_State.*(1./CONF.GFM_Module_X_Res(:)));
Source_Susceptance = SG_Source_Susceptance+GFM_Source_Susceptance;
B_Fault = -imag(NET.Y_0) + spdiags(Source_Susceptance,0,N,N);

GFM_Delta_Node = CONF.GFM_Module_Loc_Mat * ...
    (CONF.GFM_Module_DeltaY_abs(:).*Module_State);
GFL_Fault_Increment_Node = CONF.Delta_I_GFL_pu_Node(:).*u_GFL;
GFL_Nodes = find(u_GFL > 0.5);
SCC = zeros(N,1);

for n = 1:N
    X_Self = imag(Z_Fault(n,n));
    if ~isfinite(X_Self) || X_Self <= 0
        error('%s在节点%d的自阻抗虚部无效。',State_Label,n);
    end

    Delta_I_LVRT = solve_lvrt_increment_current( ...
        B_Fault, Source_Susceptance, n, GFL_Nodes, CONF);
    Nonfault_GFL_Nodes = GFL_Nodes(GFL_Nodes ~= n);
    Transfer_Current = 0;
    for GFL_Node = reshape(Nonfault_GFL_Nodes,1,[])
        Transfer_Current = Transfer_Current + ...
            abs(Z_Fault(n,GFL_Node)/Z_Fault(n,n))* ...
            Delta_I_LVRT(GFL_Node);
    end

    SCC_PU = 1/X_Self-GFM_Delta_Node(n) + ...
        GFL_Fault_Increment_Node(n)+Transfer_Current;
    if ~isfinite(SCC_PU) || SCC_PU < 0
        error('%s在节点%d得到无效的后验短路电流。',State_Label,n);
    end
    SCC(n) = SCC_PU*CONF.Base_kA;
end

end

function Delta_I = solve_lvrt_increment_current( ...
    B_Fault, Source_Susceptance, Fault_Node, GFL_Nodes, CONF)
%% 按文档式(1.52)-(1.69)枚举三段LVRT区间并求解故障残余电压。

N = size(B_Fault,1);
Nonfault_Nodes = [1:Fault_Node-1, Fault_Node+1:N];
Active_GFL_Nodes = GFL_Nodes(GFL_Nodes ~= Fault_Node);
GFL_Count = numel(Active_GFL_Nodes);
Segment_Count = 3^GFL_Count;
Tolerance = 1e-8;

for Segment_Index = 0:Segment_Count-1
    Segment = mod(floor(Segment_Index./(3.^(0:GFL_Count-1))),3);
    Coefficient = B_Fault(Nonfault_Nodes,Nonfault_Nodes);
    Right_Hand_Side = Source_Susceptance(Nonfault_Nodes);

    % 文档式(1.61)将GFL-WG增量电流作为节点平衡式右端的正注入。
    for GFL_Index = 1:GFL_Count
        GFL_Node = Active_GFL_Nodes(GFL_Index);
        Reduced_Index = find(Nonfault_Nodes == GFL_Node,1);
        if Segment(GFL_Index) == 1
            Slope = CONF.KQ_GFL_Node(GFL_Node)* ...
                CONF.I_GFL_N_pu_Node(GFL_Node);
            Coefficient(Reduced_Index,Reduced_Index) = ...
                Coefficient(Reduced_Index,Reduced_Index)+Slope;
            Right_Hand_Side(Reduced_Index) = ...
                Right_Hand_Side(Reduced_Index) + ...
                Slope*CONF.V_LVRT_On_Node(GFL_Node);
        elseif Segment(GFL_Index) == 2
            Right_Hand_Side(Reduced_Index) = Right_Hand_Side(Reduced_Index) + ...
                CONF.Delta_I_GFL_pu_Node(GFL_Node);
        end
    end

    if rcond(full(Coefficient)) < 1e-12
        continue;
    end
    Voltage = zeros(N,1);
    Voltage(Nonfault_Nodes) = Coefficient\Right_Hand_Side;
    if any(~isfinite(Voltage)) || ...
            any(Voltage(Active_GFL_Nodes) < -Tolerance)
        continue;
    end

    Delta_I_Candidate = zeros(N,1);
    Segment_Is_Valid = true;
    for GFL_Index = 1:GFL_Count
        GFL_Node = Active_GFL_Nodes(GFL_Index);
        V_p = Voltage(GFL_Node);
        V_On = CONF.V_LVRT_On_Node(GFL_Node);
        V_Sat = CONF.V_LVRT_Sat_Node(GFL_Node);
        if Segment(GFL_Index) == 0
            Segment_Is_Valid = Segment_Is_Valid && V_p >= V_On-Tolerance;
        elseif Segment(GFL_Index) == 1
            Segment_Is_Valid = Segment_Is_Valid && ...
                V_p >= V_Sat-Tolerance && V_p <= V_On+Tolerance;
            Delta_I_Candidate(GFL_Node) = CONF.KQ_GFL_Node(GFL_Node) * ...
                CONF.I_GFL_N_pu_Node(GFL_Node)*(V_On-V_p);
        else
            Segment_Is_Valid = Segment_Is_Valid && V_p <= V_Sat+Tolerance;
            Delta_I_Candidate(GFL_Node) = ...
                CONF.Delta_I_GFL_pu_Node(GFL_Node);
        end
    end

    if Segment_Is_Valid
        Delta_I = Delta_I_Candidate;
        return;
    end
end

error('节点%d故障时未找到满足三段LVRT定义的残余电压解。',Fault_Node);
end

function Binary_Value = validate_binary_result(Binary_Value, Value_Label)
%% 验证求解结果中的离散状态，再固定为对应的0-1方案。

if any(~isfinite(Binary_Value(:))) || ...
        any(abs(Binary_Value(:)-round(Binary_Value(:))) > 1e-5)
    error('%s不是有效的0-1求解结果。',Value_Label);
end
Binary_Value = round(Binary_Value);
end
