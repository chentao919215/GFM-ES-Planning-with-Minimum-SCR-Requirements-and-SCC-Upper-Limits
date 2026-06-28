function MIPStart = build_multiple_snapshot_mip_start_from_result(Result, CONF)
%% 从刚完成的阶段结果构造下一阶段的整数热启动。

MIPStart = struct();
MIPStart.u_G = reshape(round(Result.u_G), ...
    CONF.Gn, CONF.TypicalDayCount, CONF.PeriodCount);
MIPStart.u_G_SCC = round(Result.u_G_SCC(:));
MIPStart.u_G_SCR = round(Result.u_G_SCR(:));
MIPStart.u_GFM_Mod = round(Result.u_GFM_Mod);
MIPStart.SourceFile = '';
MIPStart.SourceStage = get_result_stage(Result);

end

function stage_name = get_result_stage(Result)
stage_name = '';
if isfield(Result, 'SolveStage') && ~isempty(Result.SolveStage)
    stage_name = Result.SolveStage;
elseif isfield(Result, 'CONF') && isfield(Result.CONF, 'SolveStage')
    stage_name = Result.CONF.SolveStage;
end
end
