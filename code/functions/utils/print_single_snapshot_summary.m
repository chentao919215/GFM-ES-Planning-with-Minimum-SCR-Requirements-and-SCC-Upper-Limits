function print_single_snapshot_summary(Result, result_file)
%% 本函数功能是在命令行打印单时刻规划的关键结果。

fprintf('\n单时刻 GFM-ES 配置完成。\n');
fprintf('结果文件：%s\n', result_file);
fprintf('总成本：%.6f\n', Result.Cost.Total);
fprintf('同步机启停 u_G：1 = 投运，0 = 停机。\n');
disp(Result.u_G(:)');

if isfield(Result, 'u_GFM_Mod') && ~isempty(Result.u_GFM_Mod)
    fprintf('GFM-ES模块投建 u_GFM_Mod：1 = 投建，0 = 不投建。\n');
    disp(Result.u_GFM_Mod(:)');
end

fprintf('YALMIP建模时间：%.3f s\n', Result.Diagnostics.yalmiptime);
fprintf('求解器时间：%.3f s\n', Result.Diagnostics.solvertime);

end
