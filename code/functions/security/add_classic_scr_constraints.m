function C_SCR = add_classic_scr_constraints(CONF, u_GFL, X_Diag, PN_PU)
%% 本函数功能是构造已建GFL节点的经典短路比下限约束。
% 经典SCR约束只作用于已建GFL节点。
% X_diag为节点自阻抗虚部对角元素，PN_pu为变流器额定容量标幺值。

CONF = normalize_multiple_snapshot_conf(CONF);

C_SCR = [];

% 筛选已建GFL节点
GFL_Index = u_GFL > 0.5;

if any(GFL_Index)
    PN_PU = expand_scr_capacity(PN_PU, numel(u_GFL));
    C_SCR = [C_SCR, PN_PU(GFL_Index).*X_Diag(GFL_Index) <= CONF.KZ / CONF.SCR_min];
end

end

function PN_PU = expand_scr_capacity(PN_PU, n_Nodes)
%% 本函数功能是将SCR容量参数扩展为节点向量。

PN_PU = PN_PU(:);

if isscalar(PN_PU)
    PN_PU = repmat(PN_PU, n_Nodes, 1);
elseif numel(PN_PU) ~= n_Nodes
    error('PN_pu长度应为1或节点数量%d。', n_Nodes);
end

end
