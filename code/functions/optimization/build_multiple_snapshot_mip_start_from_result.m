function MIPStart = build_multiple_snapshot_mip_start_from_result(Result, CONF)
%% 从刚完成的阶段结果构造下一阶段或更多典型日算例的整数热启动。

source_day_count = numel(Result.u_G)/(CONF.Gn*CONF.PeriodCount);
if source_day_count ~= round(source_day_count) || source_day_count < 1
    error('源结果中的u_G维度与目标算例不兼容。');
end

% 当源结果仅含普通典型日时，将其逐时整数状态复制到目标算例各典型日。
source_u_G = reshape(round(Result.u_G), ...
    CONF.Gn, source_day_count, CONF.PeriodCount);
source_u_GFM_Ch = reshape(round(Result.u_GFM_Ch), ...
    CONF.GFM_Candidate_Count, source_day_count, CONF.PeriodCount);

MIPStart = struct();
MIPStart.u_G = expand_typical_days( ...
    source_u_G, CONF.TypicalDayCount, 'u_G');
MIPStart.u_G_SCC = round(Result.u_G_SCC(:));
MIPStart.u_G_SCR = round(Result.u_G_SCR(:));
MIPStart.u_GFM_Mod = round(Result.u_GFM_Mod);
MIPStart.u_GFM_Ch = expand_typical_days( ...
    source_u_GFM_Ch, CONF.TypicalDayCount, 'u_GFM_Ch');

if isfield(Result, 'u_G_Start') && isfield(Result, 'u_G_Stop')
    source_u_G_Start = reshape(round(Result.u_G_Start), ...
        CONF.Gn, source_day_count, CONF.PeriodCount);
    source_u_G_Stop = reshape(round(Result.u_G_Stop), ...
        CONF.Gn, source_day_count, CONF.PeriodCount);
    MIPStart.u_G_Start = expand_typical_days( ...
        source_u_G_Start, CONF.TypicalDayCount, 'u_G_Start');
    MIPStart.u_G_Stop = expand_typical_days( ...
        source_u_G_Stop, CONF.TypicalDayCount, 'u_G_Stop');
else
    % 兼容未保存启停动作变量的历史结果，并按循环首尾状态补算动作。
    [MIPStart.u_G_Start, MIPStart.u_G_Stop] = ...
        derive_uc_actions(MIPStart.u_G);
end
MIPStart.SourceFile = '';
MIPStart.SourceStage = get_result_stage(Result);

end

function values = expand_typical_days(values, target_day_count, field_name)
%% 将单典型日整数解复制到目标典型日维度。

source_day_count = size(values,2);
if source_day_count == target_day_count
    return;
end
if source_day_count == 1
    values = repmat(values,1,target_day_count,1);
    return;
end

error('源结果中的%s含%d个典型日，无法映射到%d个典型日。', ...
    field_name,source_day_count,target_day_count);

end

function [u_start, u_stop] = derive_uc_actions(u_state)
%% 根据典型日内循环运行状态推导同步机启动、停机动作。

period_count = size(u_state,3);
previous_state = u_state(:,:,[period_count,1:period_count-1]);
u_start = max(u_state-previous_state,0);
u_stop = max(previous_state-u_state,0);

end

function stage_name = get_result_stage(Result)
stage_name = '';
if isfield(Result, 'SolveStage') && ~isempty(Result.SolveStage)
    stage_name = Result.SolveStage;
elseif isfield(Result, 'CONF') && isfield(Result.CONF, 'SolveStage')
    stage_name = Result.CONF.SolveStage;
end
end
