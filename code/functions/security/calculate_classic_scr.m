function SCR = calculate_classic_scr(X_diag_val, u_GFL, PN_pu)
%% 本函数功能是按经典短路比公式计算SCR。

idx_gfl = u_GFL > 0.5;
SCR = zeros(numel(u_GFL),1);
SCR(idx_gfl) = 1./max(PN_pu * X_diag_val(idx_gfl), 1e-12);

end
