function C_SCC = add_short_circuit_current_constraints_periodwise( ...
    NET, CONF, u_SG, u_GFM_Module, u_GFL, V_F, I_SC)
%% 由逐时故障节点KCL构造精确MILP短路电流限值约束。
% Manuscript Section II-C，式(15)-(21)的逐时节点方程实现。非故障节点
% 的LVRT电流已在4.4.3进入残压方程；此处保留故障节点GFL饱和增量和
% 本地GFM-ES虚拟阻抗限流，与calculate_fixed_state_scc同口径。

CONF = normalize_multiple_snapshot_conf(CONF);
NS = NET.Safety_N;
D = CONF.TypicalDayCount;
T = CONF.PeriodCount;
if ~isequal([size(V_F,1),size(V_F,2),size(V_F,3),size(V_F,4)], ...
        [NS,NS,D,T]) || ...
        ~isequal([size(I_SC,1),size(I_SC,2),size(I_SC,3)], [NS,D,T])
    error('PW故障残压或短路电流变量维度与安全网络不一致。');
end

Safety_Nodes = NET.Safety_Retained_Nodes(:);
B0 = -NET.B_0_Safety;
b_SG = -imag(1./(1i*CONF.Xd_Gen(:)));
b_GFM = 1./CONF.GFM_Module_X_Res(:);
GFM_Source = NET.Safety_GFM_Module_Location_Matrix* ...
    (b_GFM.*u_GFM_Module);
GFM_Local_Limiting = NET.Safety_GFM_Module_Location_Matrix* ...
    (CONF.GFM_Module_DeltaY_abs(:).*u_GFM_Module);
GFL_Fault_Increment = CONF.Delta_I_GFL_pu_Node(Safety_Nodes).* ...
    u_GFL(Safety_Nodes);
I_Limit = CONF.I_limit(Safety_Nodes);
C_SCC = [I_SC(:) >= 0];

for d = 1:D
    for t = 1:T
        SG_Source = NET.Safety_Generator_Location_Matrix* ...
            (b_SG.*u_SG(:,d,t));
        for n = 1:NS
            Other = [1:n-1,n+1:NS];
            % 故障节点V(n,n)=0；由B_fault*V=source+DeltaI-I_SC得到KCL。
            % 本地GFM电纳变化量与后验SCC的local-only规则一致。
            C_SCC = [C_SCC, I_SC(n,d,t) == ...
                SG_Source(n)+GFM_Source(n) - ...
                sum(B0(n,Other).*V_F(n,Other,d,t)) + ...
                GFL_Fault_Increment(n)-GFM_Local_Limiting(n), ...
                I_SC(n,d,t) <= I_Limit(n)]; %#ok<AGROW>
        end
    end
end
end
