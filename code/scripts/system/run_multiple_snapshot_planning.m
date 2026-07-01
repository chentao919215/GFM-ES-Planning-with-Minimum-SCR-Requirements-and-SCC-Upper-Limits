%% IEEE-30多时刻GFM-ES配置算例
% 默认采用两阶段求解：600秒寻找可行解，再以该解热启动3600秒最优性证明。
project_root = resolve_project_root_for_script();
addpath(genpath(fullfile(project_root, 'code', 'functions')));

% 参数源脚本会重新生成供程序读取的JSON文件。
run(fullfile(project_root, 'data', 'params', 'generate_multiple_snapshot_default_params.m'));

%% 1. 加载算例、参数与可选历史热启动
param_file = fullfile(project_root, 'data', 'params', 'multiple_snapshot_default_params.json');
[mpc, CONF, paths] = load_multiple_snapshot_case(project_root, param_file);
[CONF, MIPStartInfo] = attach_latest_multiple_snapshot_mip_start(CONF, paths.results_dir);
if MIPStartInfo.used
    fprintf('已加载历史整数热启动：%s\n', MIPStartInfo.result_file);
elseif CONF.UseLatestMIPStart
    fprintf('未加载历史整数热启动：%s\n', MIPStartInfo.reason);
end

two_stage_enabled = isfield(CONF.Solver, 'TwoStage') && ...
    isfield(CONF.Solver.TwoStage, 'Enabled') && ...
    logical(CONF.Solver.TwoStage.Enabled);

if two_stage_enabled
    %% 2. 第一阶段：优先寻找高质量可行解
    CONF_stage1 = apply_multiple_snapshot_solver_stage( ...
        CONF, CONF.Solver.TwoStage.Stage1);
    fprintf('\n========== 第一阶段：可行解搜索（时限 %.0f s）==========\n', ...
        CONF_stage1.Solver.TimeLimit);
    [Result_stage1, result_file_stage1] = solve_one_stage(mpc, CONF_stage1, paths);

    %% 3. 第二阶段：使用第一阶段整数解强化最优性证明
    CONF_stage2 = apply_multiple_snapshot_solver_stage( ...
        CONF, CONF.Solver.TwoStage.Stage2);
    CONF_stage2.MIPStart = build_multiple_snapshot_mip_start_from_result( ...
        Result_stage1, CONF_stage2);
    fprintf('\n========== 第二阶段：最优性证明（时限 %.0f s）==========\n', ...
        CONF_stage2.Solver.TimeLimit);
    fprintf('已直接采用第一阶段最优可行解作为整数热启动。\n');
    [Result, result_file] = solve_one_stage(mpc, CONF_stage2, paths);

    fprintf('\n两阶段求解完成。\n第一阶段结果：%s\n第二阶段结果：%s\n', ...
        result_file_stage1, result_file);
    total_time = Result_stage1.solve_time + Result.solve_time;
else
    %% 兼容单阶段模式
    [Result, result_file] = solve_one_stage(mpc, CONF, paths);
    total_time = Result.solve_time;
end

mail_content = sprintf(['Experiment completed at %s.\n', ...
    'Total solver time: %.3f s (%.2f min).\nFinal result: %s'], ...
    char(datetime('now')), total_time, total_time/60, result_file);
send_optional_completion_mail('Experiment completed', mail_content);

function [Result, result_file] = solve_one_stage(mpc, CONF, paths)
%% 执行一次求解、归档并打印摘要。
tic;
[SCC_0,SCC_1,P_Line,theta,P_G,P_GFL,P_GFM,SCR,Z_SCC,Z_SCR, ...
    u_GFL,u_G,u_G_SCC,u_G_SCR,Cost_CON,Cost_GEN,Cost_Total,Diagnostics, ...
    u_GFM_Mod,P_GFM_Dis,P_GFM_Ch,E_GFM,u_GFM_Ch,P_GFL_Curt,Cost_Curt] = ...
    solve_multiple_snapshot_planning(mpc, CONF);
solve_time = toc;

Result = package_multiple_snapshot_result(SCC_0,SCC_1,P_Line,theta,P_G,P_GFL,P_GFM, ...
    SCR,Z_SCC,Z_SCR,u_GFL,u_G,u_G_SCC,u_G_SCR,Cost_CON,Cost_GEN,Cost_Total, ...
    solve_time,CONF,Diagnostics,u_GFM_Mod,P_GFM_Dis,P_GFM_Ch,E_GFM,u_GFM_Ch, ...
    P_GFL_Curt,Cost_Curt);
if isfield(CONF, 'SolveStage')
    Result.SolveStage = CONF.SolveStage;
else
    Result.SolveStage = 'single-stage';
end

result_file = save_multiple_snapshot_result(Result, paths.results_dir);
print_multiple_snapshot_summary(Result, result_file);
end
