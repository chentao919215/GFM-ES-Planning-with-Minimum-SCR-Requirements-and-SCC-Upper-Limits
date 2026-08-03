function SCR = calculate_classic_scr(X_Diag_Val, u_GFL, PN_PU)
%% 本函数功能是按经典短路比公式计算SCR。

GFL_Index = u_GFL > 0.5;
SCR = zeros(numel(u_GFL),1);
PN_PU = expand_scr_capacity(PN_PU, numel(u_GFL));
SCR(GFL_Index) = 1./max(PN_PU(GFL_Index).*X_Diag_Val(GFL_Index), 1e-12);

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
