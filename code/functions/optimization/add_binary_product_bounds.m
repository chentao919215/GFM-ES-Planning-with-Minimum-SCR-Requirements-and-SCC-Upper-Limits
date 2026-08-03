function C_Prod = add_binary_product_bounds(W, X, U_Bin, X_Lower, X_Upper)
%% 本函数功能是线性化二元变量与连续变量的逐元素乘积。
% 目标关系为W=U_bin.*X，其中U_bin为0/1变量，X为连续变量。
% 已知连续变量满足X_lower<=X<=X_upper。
% 本函数使用McCormick线性化生成等价线性约束。

C_Prod = [];
C_Prod = [C_Prod, W >= X_Lower.*U_Bin];
C_Prod = [C_Prod, W <= X_Upper.*U_Bin];
C_Prod = [C_Prod, W - X >= -X_Upper.*(1-U_Bin)];
C_Prod = [C_Prod, W - X <= -X_Lower.*(1-U_Bin)];

end
