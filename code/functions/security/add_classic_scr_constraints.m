function C_scr = add_classic_scr_constraints(CONF, u_GFL, X_diag, PN_pu)
%ADD_CLASSIC_SCR_CONSTRAINTS 构造经典短路比下限约束。

C_scr = [];
idx_gfl = u_GFL > 0.5;

if any(idx_gfl)
    C_scr = [C_scr, PN_pu * X_diag(idx_gfl) <= CONF.KZ / CONF.SCR_min];
end

end
