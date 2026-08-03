function C_Forbid = add_forbidden_configuration_state_constraints( ...
    Invalid_States, State_Table, Lambda_Configuration, u_SG_State)
%% 禁止配置方案与不可逆同步机聚合状态同时出现。
% invalid_states每行依次记录[配置方案索引,同步机状态索引]。

C_Forbid = [];
if isempty(Invalid_States)
    return;
end

[G,D] = size(u_SG_State);
if size(State_Table,2) ~= G
    error('同步机状态目录维度与聚合状态变量不一致。');
end

for r = 1:size(Invalid_States,1)
    c = Invalid_States(r,1);
    State_Index = Invalid_States(r,2);
    if c < 1 || c > numel(Lambda_Configuration)
        error('不可行状态目录中的配置方案索引无效。');
    end
    if State_Index < 1 || State_Index > size(State_Table,1)
        error('不可行状态目录中的同步机状态索引无效。');
    end

    Forbidden_State = State_Table(State_Index,:).';
    for d = 1:D
        State_Status = u_SG_State(:,d);
        State_Mismatch = sum((1-Forbidden_State).*State_Status + ...
            Forbidden_State.*(1-State_Status));
        % 选中配置方案时，聚合状态必须至少有一个同步机位与目录状态不同。
        C_Forbid = [C_Forbid, Lambda_Configuration(c) <= State_Mismatch]; %#ok<AGROW>
    end
end

end
