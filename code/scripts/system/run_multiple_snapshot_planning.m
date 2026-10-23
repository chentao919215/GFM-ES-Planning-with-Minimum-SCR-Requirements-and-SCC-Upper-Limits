%% IEEE-30场景随机多时段GFM-ES配置算例
% 本脚本负责参数准备、求解流程编排和完成通知。

Project_Root = resolve_project_root_for_script();
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));

%% 1. 准备并加载当前参数文件
if exist('Parameter_File', 'var') && ~isempty(Parameter_File)
    % 外部指定参数时直接读取，不覆盖用户提供的JSON文件。
    Parameter_File = char(Parameter_File);
    assert(isfile(Parameter_File), '参数文件不存在：%s', Parameter_File);
else
    % 未指定参数时，由参数源脚本重新生成默认JSON文件。
    run(fullfile(Project_Root, 'data', 'params', ...
        'generate_multiple_snapshot_default_params.m'));
    Parameter_File = fullfile(Project_Root, 'data', 'params', ...
        'multiple_snapshot_default_params.json');
end
[mpc, CONF, paths] = load_multiple_snapshot_case(Project_Root, Parameter_File);
clear Project_Root Parameter_File

%% 2. 执行当前配置的单阶段或两阶段求解
Case_Name = sprintf('D=%d full typical-day case', ...
    CONF.Multiple_Snapshot.Time.Typical_Day_Count);
Two_Stage_Enabled = logical(CONF.Solver.Two_Stage.Enabled);

if ~Two_Stage_Enabled
    fprintf('\n========== %s: single-stage solve ==========\n', Case_Name);
    [Result, Result_File] = solve_one_stage(mpc, CONF, paths);
    Total_Time = Result.solve_time;
else
    % 第一阶段优先搜索高质量可行解。
    CONF_Stage_1 = apply_multiple_snapshot_solver_stage( ...
        CONF, CONF.Solver.Two_Stage.Stage_1);
    fprintf('\n========== %s: stage 1 feasible search (limit %.0f s) ==========\n', ...
        Case_Name, CONF_Stage_1.Solver.Time_Limit);
    [Result_Stage_1, Result_File_Stage_1] = ...
        solve_one_stage(mpc, CONF_Stage_1, paths);

    if Result_Stage_1.Diagnostics.mip_gap <= CONF.Solver.Two_Stage.Stage_2.MIP_Gap
        fprintf('%s stage 1 converged; stage 2 is skipped.\n', Case_Name);
        Result = Result_Stage_1;
        Result_File = Result_File_Stage_1;
        Total_Time = Result_Stage_1.solve_time;
    else
        % 第二阶段使用第一阶段的当前最优整数解作为热启动。
        CONF_Stage_2 = apply_multiple_snapshot_solver_stage( ...
            CONF, CONF.Solver.Two_Stage.Stage_2);
        CONF_Stage_2.Solver.MIP_Start = ...
            build_multiple_snapshot_mip_start_from_result(Result_Stage_1, CONF_Stage_2);
        CONF_Stage_2.Solver.MIP_Start.Source_File = Result_File_Stage_1;
        fprintf('\n========== %s: stage 2 optimality proof (limit %.0f s) ==========\n', ...
            Case_Name, CONF_Stage_2.Solver.Time_Limit);
        fprintf('Stage 1 result is used as the integer MIP start.\n');
        [Result, Result_File] = solve_one_stage(mpc, CONF_Stage_2, paths);

        fprintf('\n%s two-stage solve completed.\nStage 1: %s\nStage 2: %s\n', ...
            Case_Name, Result_File_Stage_1, Result_File);
        Total_Time = Result_Stage_1.solve_time + Result.solve_time;
    end
end

%% 3. 发送完成通知
Mail_Content = sprintf(['Experiment completed at %s.\n', ...
    'Total planning workflow time: %.3f s (%.2f min).\n', ...
    'D=%d final result: %s'], ...
    char(datetime('now')), Total_Time, Total_Time/60, ...
    CONF.Multiple_Snapshot.Time.Typical_Day_Count, Result_File);
mailTome('Experiment completed', Mail_Content);
