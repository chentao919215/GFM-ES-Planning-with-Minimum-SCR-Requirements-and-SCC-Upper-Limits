function [SCC_0, SCC_1] = calculate_short_circuit_currents( ...
    Z_Val, Value_u_GFM_Module, u_GFL, CONF, Y0, Y_SG_Add, Phi_GFL_Scaled)
%% 本函数功能是计算基准状态和优化配置后的短路电流。
%
% SCC_0表示未考虑GFM-ES投建结果时的基准短路电流。
% SCC_1按《ver_2》式(1.74)至式(1.77)计算聚合安全工况短路电流。

CONF = normalize_multiple_snapshot_conf(CONF);

%% 1. 计算优化配置后的短路电流
N = numel(u_GFL);
SCC_1 = zeros(N,1);
if nargin < 7 || isempty(Phi_GFL_Scaled)
    Phi_GFL_Scaled = zeros(N,1);
else
    Phi_GFL_Scaled = Phi_GFL_Scaled(:);
end
if numel(Phi_GFL_Scaled) ~= N
    error('GFL-WG故障转移项长度应与系统节点数一致。');
end

GFM_Delta_Node = CONF.GFM_Module_Loc_Mat * ...
    (CONF.GFM_Module_DeltaY_abs(:).*Value_u_GFM_Module(:));
Delta_I_Fault_Node = CONF.Delta_I_GFL_pu_Node(:).*u_GFL(:);

for i = 1:N
    % 非故障GFL-WG转移项先还原KZ尺度，再除以节点自阻抗。
    x_Diag = max(imag(Z_Val(i,i)),1e-12);
    I_Vs = (1+Phi_GFL_Scaled(i)/CONF.KZ)/x_Diag - ...
        GFM_Delta_Node(i);

    % 标幺短路电流换算为kA
    SCC_1(i) = (I_Vs+Delta_I_Fault_Node(i))*CONF.Base_kA;
end

%% 2. 计算基准短路电流
% 基准状态只包含网络导纳和同步机等效导纳
Y_0_Sc = Y0 + Y_SG_Add;
Z_0_Sc = full(Y_0_Sc)\eye(N);
X_0_Diag = abs(imag(diag(Z_0_Sc)));

% 由节点自阻抗虚部计算三相短路电流
SCC_0 = (1./max(X_0_Diag, 1e-12))*CONF.Base_kA;

end
