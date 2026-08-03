function MIP_Start = build_multiple_snapshot_mip_start_from_result(Result, CONF)
%% 从刚完成的阶段结果构造下一阶段或更多典型日算例的整数热启动。

CONF = normalize_multiple_snapshot_conf(CONF);

Source_Day_Count = numel(Result.u_G)/(CONF.Gn*CONF.PeriodCount);
if Source_Day_Count ~= round(Source_Day_Count) || Source_Day_Count < 1
    error('源结果中的u_G维度与目标算例不兼容。');
end

% 当源结果仅含普通典型日时，将其逐时整数状态复制到目标算例各典型日。
Source_u_G = reshape(round(Result.u_G), ...
    CONF.Gn, Source_Day_Count, CONF.PeriodCount);
Source_Scenario_Count = numel(Result.u_GFM_Ch)/( ...
    CONF.GFM_Candidate_Count*Source_Day_Count*CONF.PeriodCount);
if Source_Scenario_Count ~= round(Source_Scenario_Count) || Source_Scenario_Count < 1
    error('源结果中的u_GFM_Ch场景维度与目标算例不兼容。');
end
Source_u_GFM_Ch = reshape(round(Result.u_GFM_Ch), ...
    CONF.GFM_Candidate_Count, Source_Day_Count, ...
    Source_Scenario_Count, CONF.PeriodCount);
Source_u_G_SCC = reshape(round(Result.u_G_SCC), ...
    CONF.Gn, Source_Day_Count);
Source_u_G_SCR = reshape(round(Result.u_G_SCR), ...
    CONF.Gn, Source_Day_Count);

MIP_Start = struct();
MIP_Start.u_G = expand_typical_days( ...
    Source_u_G, CONF.TypicalDayCount, 'u_G');
% 聚合安全状态也按源结果的典型日维度映射，D=1时复制到目标各日。
MIP_Start.u_G_SCC = expand_typical_days( ...
    Source_u_G_SCC, CONF.TypicalDayCount, 'u_G_SCC');
MIP_Start.u_G_SCR = expand_typical_days( ...
    Source_u_G_SCR, CONF.TypicalDayCount, 'u_G_SCR');
MIP_Start.u_GFM_Mod = round(Result.u_GFM_Mod);
MIP_Start.u_GFM_Ch = expand_typical_days( ...
    Source_u_GFM_Ch, CONF.TypicalDayCount, 'u_GFM_Ch');
MIP_Start.u_GFM_Ch = expand_wind_scenarios( ...
    MIP_Start.u_GFM_Ch, CONF.WindScenarioCount, Result);

Source_u_G_Start = reshape(round(Result.u_G_Start), ...
    CONF.Gn, Source_Day_Count, CONF.PeriodCount);
Source_u_G_Stop = reshape(round(Result.u_G_Stop), ...
    CONF.Gn, Source_Day_Count, CONF.PeriodCount);
MIP_Start.u_G_Start = expand_typical_days( ...
    Source_u_G_Start, CONF.TypicalDayCount, 'u_G_Start');
MIP_Start.u_G_Stop = expand_typical_days( ...
    Source_u_G_Stop, CONF.TypicalDayCount, 'u_G_Stop');
MIP_Start.Source_File = '';
MIP_Start.Source_Stage = get_result_stage(Result);

end

function values = expand_typical_days(values, Target_Day_Count, Field_Name)
%% 将单典型日整数解复制到目标典型日维度。

Source_Day_Count = size(values,2);
if Source_Day_Count == Target_Day_Count
    return;
end
if Source_Day_Count == 1
    replication = ones(1,max(ndims(values),2));
    replication(2) = Target_Day_Count;
    values = repmat(values,replication);
    return;
end

error('源结果中的%s含%d个典型日，无法映射到%d个典型日。', ...
    Field_Name,Source_Day_Count,Target_Day_Count);

end

function values = expand_wind_scenarios(values, Target_Scenario_Count, Result)
%% 将整数热启动的场景维映射到目标算例。

Source_Scenario_Count = size(values,3);
if Source_Scenario_Count == Target_Scenario_Count
    return;
end
if Source_Scenario_Count == 1
    values = repmat(values,1,1,Target_Scenario_Count,1);
    return;
end
if Target_Scenario_Count == 1
    Source_Base_Index = Result.CONF.WindScenarioBaseIndex;
    if ~isfinite(Source_Base_Index) || Source_Base_Index < 1 || ...
            Source_Base_Index > Source_Scenario_Count || ...
            Source_Base_Index ~= round(Source_Base_Index)
        error('源结果未定义有效的基准风电场景索引。');
    end
    values = values(:,:,Source_Base_Index,:);
    return;
end

error('源结果含%d个风电场景，无法映射到%d个风电场景。', ...
    Source_Scenario_Count,Target_Scenario_Count);

end

function Stage_Name = get_result_stage(Result)
Stage_Name = Result.SolveStage;
end
