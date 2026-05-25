function [SCC_0, SCC_1] = calculate_short_circuit_currents(Z_val, value_u_GFM, u_GFL, CONF, DeltaY, Y0, Y_SG_Add)
%% 本函数功能是计算基准状态和优化配置后的短路电流。
%
% SCC_0表示未考虑GFM-ES投建结果时的基准短路电流。
% SCC_1表示考虑优化得到的GFM-ES投建结果后的短路电流。

%% 1. 计算优化配置后的短路电流
N = numel(u_GFL);
SCC_1 = zeros(N,1);

for i = 1:N
    % 由节点自阻抗得到等值电压源支路导纳
    Y_th = 1/(imag(Z_val(i,i))+1e-12);

    % GFM-ES投建后会改变等值电压源支路导纳
    I_vs = Y_th - value_u_GFM(i)*abs(DeltaY);

    % 已建GFL按电流源贡献计入短路电流
    I_cs = (CONF.I_post+CONF.PN/CONF.Base_MVA)*u_GFL(i);

    % 标幺短路电流换算为kA
    SCC_1(i) = (I_vs+I_cs)*CONF.Base_kA;
end

%% 2. 计算基准短路电流
% 基准状态只包含网络导纳和同步机等效导纳
Y0_sc = Y0 + Y_SG_Add;
Z0_sc = inv(full(Y0_sc));
X0_diag = abs(imag(diag(Z0_sc)));

% 由节点自阻抗虚部计算三相短路电流
SCC_0 = (1./max(X0_diag, 1e-12))*CONF.Base_kA;

end
