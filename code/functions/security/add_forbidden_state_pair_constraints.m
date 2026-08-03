function C_Forbid = add_forbidden_state_pair_constraints( ...
    Invalid_Pairs, State_Table, Lambda_Configuration, u_SG_SCC, u_SG)
%% 禁止配置方案与不可逆的“并集状态-实际状态”组合同时出现。
% invalid_pairs每行依次记录[配置方案索引,并集状态索引,实际状态索引]。

C_Forbid = [];
if isempty(Invalid_Pairs)
    return;
end

[G,D] = size(u_SG_SCC);
G2 = size(u_SG,1);
D2 = size(u_SG,2);
T = size(u_SG,3);
if G2 ~= G || D2 ~= D
    error('同步机并集状态与逐时状态变量维度不一致。');
end
if size(State_Table,2) ~= G
    error('同步机状态目录维度与UC状态变量不一致。');
end

for r = 1:size(Invalid_Pairs,1)
    c = Invalid_Pairs(r,1);
    Union_State = State_Table(Invalid_Pairs(r,2),:).';
    Actual_State = State_Table(Invalid_Pairs(r,3),:).';
    if c < 1 || c > numel(Lambda_Configuration)
        error('不可行状态目录中的配置方案索引无效。');
    end

    % 将目录状态显式复制到各典型日，避免依赖YALMIP的单例维隐式扩展。
    Union_State_By_Day = repmat(Union_State,1,D);
    Union_Mismatch = sum((1-Union_State_By_Day).*u_SG_SCC + ...
        Union_State_By_Day.*(1-u_SG_SCC),1);
    for d = 1:D
        for t = 1:T
            Actual_Status = u_SG(:,d,t);
            Actual_Mismatch = sum((1-Actual_State).*Actual_Status + ...
                Actual_State.*(1-Actual_Status));
            % 选中配置方案时，并集状态或实际状态必须至少有一位不同。
            C_Forbid = [C_Forbid, Lambda_Configuration(c) <= ...
                Union_Mismatch(d) + Actual_Mismatch]; %#ok<AGROW>
        end
    end
end
end
