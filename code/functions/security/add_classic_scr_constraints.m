function C_scr = add_classic_scr_constraints(CONF, u_GFL, X_diag, PN_pu)
%% 本函数功能是构造已建GFL节点的经典短路比下限约束。
% 经典SCR约束只作用于已建GFL节点。
% X_diag为节点自阻抗虚部对角元素，PN_pu为变流器额定容量标幺值。

C_scr = [];

% 筛选已建GFL节点
idx_gfl = u_GFL > 0.5;

if any(idx_gfl)
    PN_pu = expand_scr_capacity(PN_pu, numel(u_GFL));
    C_scr = [C_scr, PN_pu(idx_gfl).*X_diag(idx_gfl) <= CONF.KZ / CONF.SCR_min];
end

end

function PN_pu = expand_scr_capacity(PN_pu, n_nodes)
%% 本函数功能是将SCR容量参数扩展为节点向量。

PN_pu = PN_pu(:);

if isscalar(PN_pu)
    PN_pu = repmat(PN_pu, n_nodes, 1);
elseif numel(PN_pu) ~= n_nodes
    error('PN_pu长度应为1或节点数量%d。', n_nodes);
end

end
