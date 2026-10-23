function GFL = aggregate_gfl_node_parameters(GFL, Node_Count)
%% 新版式(8)-(9)、(25)：同节点GFL-WG容量与系统基准电流求和。
% 同节点设备只有相同LVRT阈值才可精确合并为论文规定的三段函数。
% 不同阈值产生更多分段，必须由用户提供符合模型假设的节点参数。

Bus = GFL.Built_Nodes(:);
[Nodes,~,Group] = unique(Bus,'stable');
if numel(Nodes) == numel(Bus), return; end
Fields = {'PN_MW','K_Q','I_N_Rated','Delta_I_Rated','V_LVRT_On','V_LVRT_Sat'};
Values = zeros(numel(Bus),numel(Fields));
for f = 1:numel(Fields)
    Input = GFL.(Fields{f})(:);
    if isscalar(Input)
        Values(:,f) = Input;
    elseif numel(Input) == numel(Bus)
        Values(:,f) = Input;
    else
        error('GFL节点表参数%s必须为标量或与Built_Nodes等长。',Fields{f});
    end
end
Output = zeros(numel(Nodes),numel(Fields));
for n = 1:numel(Nodes)
    V = Values(Group == n,:);
    assert(all(abs(V(:,5:6)-V(1,5:6)) < 1e-12,'all'), ...
        '同节点GFL-WG阈值不同，无法精确聚合为三段LVRT函数。');
    assert(all(abs(V(:,4)-V(:,2).*V(:,3).*(V(:,5)-V(:,6))) < 1e-9), ...
        '各GFL-WG必须分别满足LVRT连续性。');
    Power = sum(V(:,1));
    Rated_Current = sum(V(:,1).*V(:,3));
    Output(n,:) = [Power, sum(V(:,1).*V(:,2).*V(:,3))/Rated_Current, ...
        Rated_Current/Power, sum(V(:,1).*V(:,4))/Power, V(1,5:6)];
end
GFL.Built_Nodes = Nodes;
for f = 1:numel(Fields)
    if nargin < 2
        GFL.(Fields{f}) = Output(:,f);
    else
        Full_Node_Value = zeros(Node_Count,1);
        Full_Node_Value(Nodes) = Output(:,f);
        GFL.(Fields{f}) = Full_Node_Value;
    end
end
end
