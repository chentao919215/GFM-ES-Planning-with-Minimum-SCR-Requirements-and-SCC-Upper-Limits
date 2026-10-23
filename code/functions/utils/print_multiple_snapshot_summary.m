function print_multiple_snapshot_summary(Result, Result_File)
%% 本函数功能是在命令行打印多时段规划的关键结果。

fprintf('\n多时段 GFM-ES 配置完成。\n');
fprintf('结果文件：%s\n', Result_File);
fprintf('典型日数量：%d，时段数量：%d。\n', ...
    Result.CONF.TypicalDayCount, Result.CONF.PeriodCount);
fprintf('风电场景数量：%d；场景顺序：%s。\n', ...
    Result.CONF.WindScenarioCount, ...
    strjoin(Result.CONF.WindScenarioNames, ', '));
fprintf('各典型日场景概率（行=典型日，列=场景）：\n');
disp(Result.CONF.WindScenarioProbabilities);
fprintf('总成本：%.6f\n', Result.Cost.Total);
fprintf('GFL-WG全年弃风成本：%.6f\n', Result.Cost.Curt);
fprintf('同步机全年启停成本：%.6f\n', Result.Cost.UC);
fprintf('同步机日内聚合状态按[机组,典型日]排列：1 = 投运，0 = 停机。\n');
fprintf('u_G_SCC（各典型日内并集）：\n');
disp(Result.u_G_SCC);
fprintf('u_G_SCR（各典型日内交集）：\n');
disp(Result.u_G_SCR);

SCC_Nodes = Result.SafetyNetwork.SCCTimeResolvedOriginalNodes(:);
SCR_Nodes = Result.SafetyNetwork.SCRTimeResolvedOriginalNodes(:);
SCC_Hourly_Max = reshape(max(Result.SCC_TimeResolved,[],1), ...
    Result.CONF.TypicalDayCount,numel(SCC_Nodes)).';
SCR_Hourly_Min = reshape(min(Result.SCR_TimeResolved,[],1), ...
    Result.CONF.TypicalDayCount,numel(SCR_Nodes)).';
fprintf('SCC_1（聚合保守上界，kA；行=原始节点，列=典型日）：\n');
disp(Result.SCC_1);
fprintf('逐时SCC日内最大值（节点顺序%s，列=典型日）：\n',mat2str(SCC_Nodes.'));
disp(SCC_Hourly_Max);
fprintf('聚合SCR下界（GFL节点顺序%s，列=典型日）：\n',mat2str(SCR_Nodes.'));
disp(Result.SCR(SCR_Nodes,:));
fprintf('逐时SCR日内最小值（列=典型日）：\n');
disp(SCR_Hourly_Min);
fprintf(['聚合保守性：SCC最大违反量 %.6g kA（容差 %.6g），', ...
    'SCR最大违反量 %.6g（容差 %.6g），通过=%d。\n'], ...
    Result.SecurityValidation.SCC.MaximumViolation, ...
    Result.SecurityValidation.SCC.Tolerance, ...
    Result.SecurityValidation.SCR.MaximumViolation, ...
    Result.SecurityValidation.SCR.Tolerance, ...
    Result.SecurityValidation.Passed);

fprintf('GFM-ES模块投建 u_GFM_Mod：1 = 投建，0 = 不投建。\n');
disp(Result.u_GFM_Mod);

fprintf('GFM-ES候选节点日内SOC范围（按已投建额定能量归一化）：\n');
Installed_Energy = Result.CONF.GFM_Candidate_Module_Mat* ...
    (Result.CONF.GFM_Module_Rated_Energy(:).*reshape(Result.u_GFM_Mod( ...
    sub2ind(size(Result.u_GFM_Mod), ...
    Result.CONF.GFM_Module_Candidate_Index(:), ...
    Result.CONF.GFM_Module_Order(:))),[],1));
SOC_Value = Result.E_GFM./reshape(Installed_Energy,[],1,1,1);
SOC_Value(~isfinite(SOC_Value)) = NaN;
disp([min(SOC_Value,[],[2,3,4],'omitnan'), ...
    max(SOC_Value,[],[2,3,4],'omitnan')]);

fprintf('YALMIP optimize调用开销：%.3f s\n', Result.Diagnostics.yalmiptime);
fprintf('求解器时间：%.3f s\n', Result.Diagnostics.solvertime);
fprintf('求解流程墙钟时间（含逐时安全后处理，不含保存）：%.3f s\n', ...
    Result.solve_time);
if Result.Diagnostics.has_incumbent
    fprintf('最佳界：%.6f，相对间隙：%.4f%%，节点数：%.0f。\n', ...
        Result.Diagnostics.best_bound, 100*Result.Diagnostics.mip_gap, ...
        Result.Diagnostics.node_count);
end

end
