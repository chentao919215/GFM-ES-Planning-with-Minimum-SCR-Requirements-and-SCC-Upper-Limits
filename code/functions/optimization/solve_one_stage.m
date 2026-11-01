function [Result, Result_File] = solve_one_stage(mpc, CONF, Results_Directory, Return_No_Incumbent)
%% 执行一次规划求解，保存返回结果并打印对应摘要。
% Return_No_Incumbent为true时，扫描流程可归档无可行解的诊断结果。
if nargin < 4
    Return_No_Incumbent = false;
end

%% 1. 求解并保存阶段结果
Result = solve_multiple_snapshot_planning(mpc, CONF, Return_No_Incumbent);
ensure_directory(Results_Directory);
Timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
Result_File = fullfile(Results_Directory, ...
    ['multiple_snapshot_planning_result_', Timestamp, '.mat']);
save(Result_File, 'Result', '-v7.3');

%% 2. 根据可行解状态打印摘要或诊断文件位置
if Result.Diagnostics.has_incumbent
    print_multiple_snapshot_summary(Result, Result_File);
else
    fprintf('未找到可行解；诊断信息已保存至：%s\n', Result_File);
end
end

function print_multiple_snapshot_summary(Result, Result_File)
%% 本函数功能是在命令行打印多时段规划的关键结果。

fprintf('\n多时段 GFM-ES 配置完成。\n');
fprintf('结果文件：%s\n', Result_File);
fprintf('典型日数量：%d，时段数量：%d。\n', ...
    Result.CONF.TypicalDayCount, Result.CONF.PeriodCount);
fprintf('风电场景数量：%d，按编号1至%d排列。\n', ...
    Result.CONF.WindScenarioCount, Result.CONF.WindScenarioCount);
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

SCC_Nodes = Result.CONF.SCC_Constraint_Original_Nodes(:);
SCR_Nodes = Result.CONF.Safety_GFL_Original_Nodes(:);
SCC_Hourly_Max = reshape(max(Result.SCC_TimeResolved, [], 1), ...
    Result.CONF.TypicalDayCount, numel(SCC_Nodes)).';
SCR_Hourly_Min = reshape(min(Result.SCR_TimeResolved, [], 1), ...
    Result.CONF.TypicalDayCount, numel(SCR_Nodes)).';
fprintf('SCC_Aggregated（聚合保守上界，kA；行=原始节点，列=典型日）：\n');
disp(Result.SCC_Aggregated);
fprintf('逐时SCC日内最大值（节点顺序%s，列=典型日）：\n', mat2str(SCC_Nodes.'));
disp(SCC_Hourly_Max);
fprintf('聚合SCR下界（GFL节点顺序%s，列=典型日）：\n', mat2str(SCR_Nodes.'));
disp(Result.SCR_Aggregated(SCR_Nodes, :));
fprintf('逐时SCR日内最小值（列=典型日）：\n');
disp(SCR_Hourly_Min);
fprintf(['聚合保守性：SCC最大违反量 %.6g kA（容差 %.6g），', ...
    'SCR最大违反量 %.6g（容差 %.6g），通过=%d。\n'], ...
    Result.SecurityValidation.Conservatism.SCC.MaximumViolation, ...
    Result.SecurityValidation.Conservatism.SCC.Tolerance, ...
    Result.SecurityValidation.Conservatism.SCR.MaximumViolation, ...
    Result.SecurityValidation.Conservatism.SCR.Tolerance, ...
    Result.SecurityValidation.Conservatism.Passed);
fprintf('逐时启用限值检查：通过=%d；SCC最大越限 %.6g kA，SCR最大越限 %.6g。\n', ...
    Result.SecurityValidation.Limits.Passed, ...
    Result.SecurityValidation.Limits.SCC.MaximumViolation, ...
    Result.SecurityValidation.Limits.SCR.MaximumViolation);

fprintf('GFM-ES设备投建 u_GFM_Unit：1 = 投建，0 = 不投建。\n');
disp(Result.u_GFM_Unit);

fprintf('GFM-ES候选节点日内SOC范围（按已投建额定能量归一化）：\n');
Installed_Energy = Result.CONF.GFM_Candidate_Unit_Mat* ...
    (Result.CONF.GFM_Unit_Energy_MWh(:).*reshape(Result.u_GFM_Unit( ...
    sub2ind(size(Result.u_GFM_Unit), ...
    Result.CONF.GFM_Unit_Candidate_Index(:), ...
    Result.CONF.GFM_Unit_Order(:))), [], 1));
SOC_Value = Result.E_GFM./reshape(Installed_Energy, [], 1, 1, 1);
SOC_Value(~isfinite(SOC_Value)) = NaN;
disp([min(SOC_Value, [], [2, 3, 4], 'omitnan'), ...
    max(SOC_Value, [], [2, 3, 4], 'omitnan')]);

fprintf('YALMIP optimize调用开销：%.3f s\n', Result.Diagnostics.yalmiptime);
fprintf('求解器时间：%.3f s\n', Result.Diagnostics.solvertime);
fprintf('求解流程墙钟时间（含逐时安全后处理，不含保存）：%.3f s\n', ...
    Result.Diagnostics.walltime);
if Result.Diagnostics.has_incumbent
    fprintf('最佳界：%.6f，相对间隙：%.4f%%，节点数：%.0f。\n', ...
        Result.Diagnostics.best_bound, 100*Result.Diagnostics.mip_gap, ...
        Result.Diagnostics.node_count);
end

end
