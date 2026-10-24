function C = add_converter_source_support_constraints( ...
    SEC, CONF, u_SG, u_Intersection, u_Module)
%% 新版式(29)-(30)：规划阶段电源支撑约束，不依赖SCC/SCR限值开关。

G = size(SEC.Generator_Location,2);
D = CONF.TypicalDayCount;
T = CONF.PeriodCount;
C = [];

for d = 1:D
    % 式(29)：交集UC状态下的安全网络必须有电源支撑。
    C = [C, sum(u_Intersection(:,d))+sum(u_Module) >= 1]; %#ok<AGROW>
    for n = 1:SEC.N
        for c = 1:numel(SEC.Fault_Components{n})
            Nodes = SEC.Fault_Components{n}{c};
            Source_Mask = full(sum(SEC.Source_Location(Nodes,:),1)).';
            for t = 1:T
                % 式(30)：移除故障母线后，每个连通分量逐时均须有源。
                Hourly_Sources = [u_SG(:,d,t);u_Module];
                C = [C, Source_Mask.'*Hourly_Sources >= 1]; %#ok<AGROW>
            end
        end
    end
end

assert(size(SEC.Source_Location,2) == G+numel(u_Module), ...
    '源支撑约束中的同步机与GFM-ES模块维度不一致。');

end
