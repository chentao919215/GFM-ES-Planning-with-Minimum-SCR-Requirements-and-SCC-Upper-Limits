%% IEEE-30场景随机多时段GFM-ES配置算例
% 本脚本负责参数准备、求解流程编排和完成通知。

project_root = resolve_project_root_for_script();
addpath(genpath(fullfile(project_root, 'code', 'functions')));

% 参数源脚本重新生成供程序读取的JSON文件。
run(fullfile(project_root, 'data', 'params', 'generate_multiple_snapshot_default_params.m'));

%% 1. 加载当前参数文件
param_file = fullfile(project_root, 'data', 'params', ...
    'multiple_snapshot_default_params.json');
[mpc, CONF_full, paths] = load_multiple_snapshot_case(project_root, param_file);
clear project_root param_file

%% 2. 执行当前配置的单阶段或两阶段求解
case_name = sprintf('D=%d full typical-day case', CONF_full.TypicalDayCount);
CONF_full.CaseName = case_name;
two_stage_enabled = isfield(CONF_full.Solver, 'TwoStage') && ...
    isfield(CONF_full.Solver.TwoStage, 'Enabled') && ...
    logical(CONF_full.Solver.TwoStage.Enabled);

if ~two_stage_enabled
    fprintf('\n========== %s: single-stage solve ==========\n', case_name);
    [Result, result_file] = solve_one_stage(mpc, CONF_full, paths);
    total_time = Result.solve_time;
else
    % 第一阶段优先搜索高质量可行解。
    CONF_stage1 = apply_multiple_snapshot_solver_stage( ...
        CONF_full, CONF_full.Solver.TwoStage.Stage1);
    fprintf('\n========== %s: stage 1 feasible search (limit %.0f s) ==========\n', ...
        case_name, CONF_stage1.Solver.TimeLimit);
    [Result_stage1, result_file_stage1] = ...
        solve_one_stage(mpc, CONF_stage1, paths);

    if Result_stage1.Diagnostics.mip_gap <= CONF_full.Solver.TwoStage.Stage2.MIPGap
        fprintf('%s stage 1 converged; stage 2 is skipped.\n', case_name);
        Result = Result_stage1;
        result_file = result_file_stage1;
        total_time = Result_stage1.solve_time;
    else
        % 第二阶段使用第一阶段的当前最优整数解作为热启动。
        CONF_stage2 = apply_multiple_snapshot_solver_stage( ...
            CONF_full, CONF_full.Solver.TwoStage.Stage2);
        CONF_stage2.MIPStart = ...
            build_multiple_snapshot_mip_start_from_result(Result_stage1, CONF_stage2);
        CONF_stage2.MIPStart.SourceFile = result_file_stage1;
        fprintf('\n========== %s: stage 2 optimality proof (limit %.0f s) ==========\n', ...
            case_name, CONF_stage2.Solver.TimeLimit);
        fprintf('Stage 1 result is used as the integer MIP start.\n');
        [Result, result_file] = solve_one_stage(mpc, CONF_stage2, paths);

        fprintf('\n%s two-stage solve completed.\nStage 1: %s\nStage 2: %s\n', ...
            case_name, result_file_stage1, result_file);
        total_time = Result_stage1.solve_time + Result.solve_time;
    end
end

%% 3. 发送完成通知
mail_content = sprintf(['Experiment completed at %s.\n', ...
    'Total solver time: %.3f s (%.2f min).\n', ...
    'D=%d final result: %s'], ...
    char(datetime('now')), total_time, total_time/60, ...
    CONF_full.TypicalDayCount, result_file);
mailTome('Experiment completed', mail_content);
