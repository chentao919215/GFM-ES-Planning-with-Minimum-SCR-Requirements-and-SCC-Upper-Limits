function C_prod = add_binary_product_bounds(W, X, U_bin, X_lower, X_upper)
%ADD_BINARY_PRODUCT_BOUNDS Linearize W = U_bin .* X with elementwise bounds.

C_prod = [];
C_prod = [C_prod, W >= X_lower.*U_bin];
C_prod = [C_prod, W <= X_upper.*U_bin];
C_prod = [C_prod, W - X >= -X_upper.*(1-U_bin)];
C_prod = [C_prod, W - X <= -X_lower.*(1-U_bin)];

end
