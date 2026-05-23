function [SCC_0, SCC_1] = calculate_short_circuit_currents(Z_val, value_u_GFM, u_GFL, CONF, DeltaY, Y0, Y_SG_Add)
%CALCULATE_SHORT_CIRCUIT_CURRENTS 计算优化后和基准状态下的短路电流。

N = numel(u_GFL);
SCC_1 = zeros(N,1);

for i = 1:N
    Y_th = 1/(imag(Z_val(i,i))+1e-12);
    I_vs = Y_th - value_u_GFM(i)*abs(DeltaY);
    I_cs = (CONF.I_post+CONF.PN/CONF.Base_MVA)*u_GFL(i);
    SCC_1(i) = (I_vs+I_cs)*CONF.Base_kA;
end

Y0_sc = Y0 + Y_SG_Add;
Z0_sc = inv(full(Y0_sc));
X0_diag = abs(imag(diag(Z0_sc)));

SCC_0 = (1./max(X0_diag, 1e-12))*CONF.Base_kA;

end
