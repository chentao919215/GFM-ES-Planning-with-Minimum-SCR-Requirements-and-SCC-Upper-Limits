function C = add_gfm_es_order_constraints(CONF, u_GFM)
%% 同节点相同GFM-ES按编号选取，保留每种物理配置的一个代表。
% 仅对功率、能量、电气参数和年固定成本完全相同的设备施加顺序约束。
% 输入假定同节点设备的效率、SOC及额定持续时间一致。

%% 1. 读取顺序投建开关与设备分组参数
C = [];
if ~CONF.GFM_Enforce_Sequential_Build
    return;
end

Parameters = [CONF.GFM_Unit_PN_MW(:), CONF.GFM_Unit_Energy_MWh(:), ...
    CONF.GFM_Unit_X_Res(:), CONF.GFM_Unit_X_Vir(:), ...
    CONF.GFM_Unit_I_post(:), CONF.GFM_Unit_Annual_Cost(:)];

%% 2. 在同节点的相同设备组内，按设备编号施加顺序约束
for Bus = reshape(CONF.GFM_Candidate_Buses, 1, [])
    Indices = find(CONF.GFM_Unit_Bus == Bus);
    [~, Order] = sort(CONF.GFM_Unit_Order(Indices));
    Indices = Indices(Order);
    [~, ~, Group] = unique(Parameters(Indices, :), 'rows', 'stable');
    for Group_Index = 1:max(Group)
        Identical_Indices = Indices(Group == Group_Index);
        if numel(Identical_Indices) > 1
            C = [C, u_GFM(Identical_Indices(1:end-1)) >= ...
                u_GFM(Identical_Indices(2:end))]; %#ok<AGROW>
        end
    end
end
end
