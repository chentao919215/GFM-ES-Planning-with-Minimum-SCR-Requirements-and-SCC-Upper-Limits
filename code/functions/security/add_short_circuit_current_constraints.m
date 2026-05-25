function C_sc = add_short_circuit_current_constraints(CONF, u_GFL, u_GFM, W_GFM, X_diag, DeltaY_abs, PN_pu, X_diag_L, X_diag_U)
%% 本函数功能是构造短路电流水平约束。
% X_diag为节点自阻抗虚部对角元素。
% W_GFM用于线性化u_GFM.*X_diag。
% 约束用于限制故障点短路电流不超过CONF.I_limit。

C_sc = [];

% GFL和GFM-ES的额定故障电流贡献
I_GFLN = PN_pu;
I_GFLP = CONF.I_post;

% 线性化GFM-ES投建状态与节点自阻抗的乘积
C_sc = [C_sc, add_binary_product_bounds(W_GFM, X_diag, u_GFM, X_diag_L, X_diag_U)];

% 已建GFL状态为给定参数，可直接与连续变量相乘
W_GFL_fixed = u_GFL.*X_diag;

% 短路电流上限约束
C_sc = [C_sc, CONF.KZ <= CONF.I_limit.*X_diag + DeltaY_abs.*W_GFM - (I_GFLP+I_GFLN).*W_GFL_fixed];

end
