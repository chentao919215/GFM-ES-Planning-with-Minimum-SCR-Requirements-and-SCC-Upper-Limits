function C_sc = add_short_circuit_current_constraints(CONF, u_GFL, u_GFM, W_GFM, X_diag, DeltaY_abs, PN_pu)
%ADD_SHORT_CIRCUIT_CURRENT_CONSTRAINTS 构造短路电流水平约束。

C_sc = [];

I_GFLN = PN_pu;
I_GFLP = CONF.I_post;

C_sc = [C_sc, W_GFM - X_diag >= -CONF.M_BIG_Z*(1-u_GFM)];
C_sc = [C_sc, W_GFM - X_diag <=  CONF.M_BIG_Z*(1-u_GFM)];
C_sc = [C_sc, W_GFM          >= -CONF.M_BIG_Z*u_GFM];
C_sc = [C_sc, W_GFM          <=  CONF.M_BIG_Z*u_GFM];

W_GFL_fixed = u_GFL .* X_diag;
C_sc = [C_sc, CONF.KZ <= CONF.I_limit.*X_diag + DeltaY_abs.*W_GFM - (I_GFLP+I_GFLN).*W_GFL_fixed];

end
