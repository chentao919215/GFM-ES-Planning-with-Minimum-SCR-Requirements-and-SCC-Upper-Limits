function SCR = calculate_classic_scr(X_diag_val, u_GFL, PN_pu)
%CALCULATE_CLASSIC_SCR 按 SCR = 1/(P_N_pu X_th) 计算经典短路比。

idx_gfl = u_GFL > 0.5;
SCR = zeros(numel(u_GFL),1);
SCR(idx_gfl) = 1./max(PN_pu * X_diag_val(idx_gfl), 1e-12);

end
