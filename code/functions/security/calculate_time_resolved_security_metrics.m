function [SCC_TimeResolved, SCR_TimeResolved, Status] = ...
    calculate_time_resolved_security_metrics( ...
    NET, CONF, Module_State, u_GFL, TimeResolved_SG_State)
%% Recalculate SCC and classic SCR from final actual hourly SG states.
% SCC_TimeResolved has conceptual dimensions [period, typical_day,
% scc_security_node] and unit kA. SCR_TimeResolved has conceptual
% dimensions [period, typical_day, gfl_node] and is dimensionless.

CONF = normalize_multiple_snapshot_conf(CONF);
T = CONF.PeriodCount;
D = CONF.TypicalDayCount;
G = NET.G;
if ~isequal(size(TimeResolved_SG_State), [G D T])
    error('TimeResolvedSecurity:SGStateDimensionMismatch', ...
        'Hourly SG state must have dimensions [generator, typical_day, period] = %s.', ...
        mat2str([G D T]));
end

SCC_Nodes = CONF.SCC_Constraint_Original_Nodes(:);
SCR_Nodes = CONF.Safety_GFL_Original_Nodes(:);
SCC_TimeResolved = nan(T,D,numel(SCC_Nodes));
SCR_TimeResolved = nan(T,D,numel(SCR_Nodes));
Status = struct();
Status.SCC.Available = false(T,D);
Status.SCR.Available = false(T,D);
Status.Issues = struct('Metric',{},'TypicalDay',{},'Period',{}, ...
    'Identifier',{},'Message',{});

for d = 1:D
    for t = 1:T
        State_Label = sprintf('typical day %d, period %d',d,t);
        try
            Fixed_State_Network = build_fixed_state_safety_network( ...
                NET, CONF, Module_State, TimeResolved_SG_State(:,d,t), ...
                State_Label);
        catch Cause
            Status = record_issue(Status,'SCC',d,t,Cause);
            Status = record_issue(Status,'SCR',d,t,Cause);
            continue;
        end

        try
            SCC_One_State = calculate_fixed_state_scc( ...
                NET, CONF, Module_State, u_GFL, ...
                TimeResolved_SG_State(:,d,t), SCC_Nodes, State_Label, ...
                Fixed_State_Network);
            SCC_TimeResolved(t,d,:) = reshape(SCC_One_State,1,1,[]);
            Status.SCC.Available(t,d) = true;
        catch Cause
            Status = record_issue(Status,'SCC',d,t,Cause);
        end

        try
            SCR_One_State = calculate_fixed_state_scr( ...
                NET, CONF, Module_State, u_GFL, ...
                TimeResolved_SG_State(:,d,t), SCR_Nodes, State_Label, ...
                Fixed_State_Network);
            SCR_TimeResolved(t,d,:) = reshape(SCR_One_State,1,1,[]);
            Status.SCR.Available(t,d) = true;
        catch Cause
            Status = record_issue(Status,'SCR',d,t,Cause);
        end
    end
end

Status.SCC.AllAvailable = all(Status.SCC.Available,'all');
Status.SCR.AllAvailable = all(Status.SCR.Available,'all');
Status.AllAvailable = Status.SCC.AllAvailable && Status.SCR.AllAvailable;

end

function Status = record_issue(Status,Metric,Day_Index,Period_Index,Cause)
Issue = struct('Metric',Metric,'TypicalDay',Day_Index, ...
    'Period',Period_Index,'Identifier',Cause.identifier, ...
    'Message',Cause.message);
Status.Issues(end+1) = Issue;
end
