function print_multiple_snapshot_summary(Result, result_file)
%% 本函数功能是在命令行打印多时刻规划的关键结果。

fprintf('\n多时刻 GFM-ES 配置完成。\n');
fprintf('结果文件：%s\n', result_file);
fprintf('典型日数量：%d，时段数量：%d。\n', ...
    Result.CONF.TypicalDayCount, Result.CONF.PeriodCount);
fprintf('总成本：%.6f\n', Result.Cost.Total);
fprintf('同步机聚合状态 u_G_SCC/u_G_SCR：1 = 投运，0 = 停机。\n');
disp(Result.u_G_SCC(:)');
disp(Result.u_G_SCR(:)');

if isfield(Result, 'u_GFM_Mod') && ~isempty(Result.u_GFM_Mod)
    fprintf('GFM-ES模块投建 u_GFM_Mod：1 = 投建，0 = 不投建。\n');
    disp(Result.u_GFM_Mod);
end

fprintf('YALMIP建模时间：%.3f s\n', Result.Diagnostics.yalmiptime);
fprintf('求解器时间：%.3f s\n', Result.Diagnostics.solvertime);
if isfield(Result.Diagnostics, 'has_incumbent') && Result.Diagnostics.has_incumbent
    fprintf('最佳界：%.6f，相对间隙：%.4f%%，节点数：%.0f。\n', ...
        Result.Diagnostics.best_bound, 100*Result.Diagnostics.mip_gap, ...
        Result.Diagnostics.node_count);
end

end
