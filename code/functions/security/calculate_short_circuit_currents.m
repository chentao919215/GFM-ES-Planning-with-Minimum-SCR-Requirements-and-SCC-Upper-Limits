function [SCC_0, SCC_1, SCC_2] = calculate_short_circuit_currents( ...
    NET, CONF, Value_u_GFM_Module, u_GFL, Value_u_G_SCC, ...
    Z_SCC_Optimization, Phi_GFL_Scaled, Calculate_Legacy_Posthoc)
%% 统一计算全同步机基准、优化模型和后验复算三组短路电流结果。
% SCC_0：基础网络投入全部同步机，不考虑规划新增GFM-ES。
% SCC_1：直接采用优化模型的阻抗近似和保守GFL-WG转移项。
% SCC_2：固定最优投建与同步机聚合状态，按Manuscript Section II-C的
% 无损安全网络独立重构故障电抗矩阵并复算。
% 可选第八个参数默认为true，以保持原有调用兼容；规划结果输出路径传入
% false，因为SCC_0和SCC_2不再保存，其报告用途由逐时后验SCC取代。

CONF = normalize_multiple_snapshot_conf(CONF);
if nargin < 8 || isempty(Calculate_Legacy_Posthoc)
    Calculate_Legacy_Posthoc = true;
end
if ~isscalar(Calculate_Legacy_Posthoc)
    error('Calculate_Legacy_Posthoc必须为标量逻辑值。');
end
Calculate_Legacy_Posthoc = logical(Calculate_Legacy_Posthoc);

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
% 对应Manuscript Eqs. (15)-(21)。非安全网络保留节点按定义保持为0。
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

if ~Calculate_Legacy_Posthoc
    SCC_0 = [];
    SCC_2 = [];
    return;
end

%% 2. SCC_0：全同步机基准结果
% 基础网络投入全部同步机，并计入故障节点GFL-WG增量电流及非故障
% 节点GFL-WG的LVRT转移贡献；规划新增GFM-ES模块全部取未投建。
All_Nodes = (1:N).';
SCC_0_One_Day = calculate_fixed_state_scc(NET, CONF, zeros(M,1), ...
    u_GFL, ones(G,1), All_Nodes, '全同步机基准工况');
SCC_0 = repmat(SCC_0_One_Day,1,D);

%% 3. SCC_2：后验复算结果
% 每个典型日仅固定最优离散状态，重新构造完整故障网络；本段不读取
% SCC_1使用的阻抗辅助变量、LVRT辅助变量或保守转移系数。
SCC_2 = zeros(N,D);
for d = 1:D
    SCC_2(:,d) = calculate_fixed_state_scc(NET, CONF, ...
        Value_u_GFM_Module, u_GFL, Value_u_G_SCC(:,d), All_Nodes, ...
        sprintf('典型日%d后验复算工况',d));
end

end

function Binary_Value = validate_binary_result(Binary_Value, Value_Label)
%% 验证求解结果中的离散状态，再固定为对应的0-1方案。

if any(~isfinite(Binary_Value(:))) || ...
        any(abs(Binary_Value(:)-round(Binary_Value(:))) > 1e-5)
    error('%s不是有效的0-1求解结果。',Value_Label);
end
Binary_Value = round(Binary_Value);
end
