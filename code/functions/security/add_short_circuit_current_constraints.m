function [C_Sc, C_McCormick] = add_short_circuit_current_constraints( ...
    CONF, u_GFL, u_GFM_Module, W_GFM, X_Diag, Delta_Y_Abs_Module, ...
    X_Diag_L, X_Diag_U, Phi_GFL)
%% 本函数功能是构造短路电流水平约束。
% X_diag为节点自阻抗虚部对角元素。
% W_GFM用于线性化u_GFM_mod.*X_diag(module_bus)。
% Phi_GFL为非故障节点GFL-WG增量电流的配置相关转移项。
% 主体约束对应Manuscript Section II-C, Eqs. (20)-(21)及Appendix-C。

CONF = normalize_multiple_snapshot_conf(CONF);

C_Sc = [];
C_McCormick = [];
if nargin < 9 || isempty(Phi_GFL)
    Phi_GFL = zeros(size(X_Diag));
end

% 故障节点GFL-WG的额定基值电流在推导中抵消，仅保留饱和增量电流。
Delta_I_GFL = CONF.Delta_I_GFL_pu_Node(:);

% Manuscript Eq. (21)：GFM-ES投建状态与并集自电抗的McCormick乘积。
X_GFM_Diag = CONF.GFM_Module_Loc_Mat'*X_Diag;
X_GFM_Diag_L = CONF.GFM_Module_Loc_Mat'*X_Diag_L;
X_GFM_Diag_U = CONF.GFM_Module_Loc_Mat'*X_Diag_U;
C_McCormick = [C_McCormick, add_binary_product_bounds(W_GFM, X_GFM_Diag, u_GFM_Module, X_GFM_Diag_L, X_GFM_Diag_U)];

% 已建GFL-WG状态为给定参数，可直接与连续自阻抗相乘。
W_GFL_Delta_Fixed = u_GFL.*Delta_I_GFL.*X_Diag;

% 同一故障节点上的多个GFM-ES模块贡献按等效电纳变化量累加
GFM_Delta_Term = CONF.GFM_Module_Loc_Mat*(Delta_Y_Abs_Module(:).*W_GFM);

% Manuscript Eq. (21)：短路电流聚合保守上界。
C_Sc = [C_Sc, CONF.KZ + Phi_GFL <= ...
    CONF.I_limit.*X_Diag + GFM_Delta_Term - W_GFL_Delta_Fixed];

end
