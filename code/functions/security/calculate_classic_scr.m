function SCR = calculate_classic_scr(X_diag_val, u_GFL, PN_pu)
%% 本函数功能是按经典短路比公式计算SCR。

idx_gfl = u_GFL > 0.5;
SCR = zeros(numel(u_GFL),1);
PN_pu = expand_scr_capacity(PN_pu, numel(u_GFL));
SCR(idx_gfl) = 1./max(PN_pu(idx_gfl).*X_diag_val(idx_gfl), 1e-12);

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
