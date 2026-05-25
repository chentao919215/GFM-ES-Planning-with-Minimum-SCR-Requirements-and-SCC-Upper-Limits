function C_prod = add_binary_product_bounds(W, X, U_bin, X_lower, X_upper)
%% 本函数功能是线性化二元变量与连续变量的逐元素乘积。
% 目标关系为W=U_bin.*X，其中U_bin为0/1变量，X为连续变量。
% 已知连续变量满足X_lower<=X<=X_upper。
% 本函数使用McCormick线性化生成等价线性约束。

C_prod = [];
C_prod = [C_prod, W >= X_lower.*U_bin];
C_prod = [C_prod, W <= X_upper.*U_bin];
C_prod = [C_prod, W - X >= -X_upper.*(1-U_bin)];
C_prod = [C_prod, W - X <= -X_lower.*(1-U_bin)];

end
