%% IEEE-30场景随机多时段GFM-ES配置算例
% 本脚本负责参数准备、求解流程编排和完成通知。
Enable_Completion_Notification = false; % 自行配置mailTome后可启用。

%% 1. 生成并加载默认参数文件

% 定义项目根目录，用于定位参数文件。
Script_Directory = fileparts(mfilename('fullpath'));
Project_Root = fileparts(fileparts(fileparts(Script_Directory)));
% 生成最新参数文件。
run(fullfile(Project_Root, 'data', 'params', ...
    'generate_multiple_snapshot_default_params.m'));
% 读取参数文件。
Parameter_File = fullfile(Project_Root, 'data', 'params', ...
    'multiple_snapshot_default_params.json');
[mpc, CONF] = prepare_multiple_snapshot_case(Parameter_File);
Results_Directory = fullfile(Project_Root, 'results');
clear Project_Root Parameter_File

%% 2. 执行当前配置的单阶段或两阶段求解
Case_Name = sprintf('D=%d典型日算例', ...
    CONF.TypicalDayCount);
Two_Stage_Enabled = logical(CONF.Solver.Two_Stage.Enabled);
Solver_Name = CONF.solver.name;

if ~Two_Stage_Enabled
    fprintf('\n========== %s：单阶段求解 ==========\n', Case_Name);
    [Result, Result_File] = solve_one_stage(mpc, CONF, Results_Directory);
    Total_Time = Result.Diagnostics.walltime;
else
    % 第一阶段优先搜索高质量可行解。
    CONF_Stage_1 = apply_multiple_snapshot_solver_stage( ...
        CONF, CONF.Solver.Two_Stage.Stage_1);
    fprintf('\n========== %s：第一阶段可行解搜索（时限%.0f秒） ==========\n', ...
        Case_Name, CONF_Stage_1.solver.options.(Solver_Name).TimeLimit);
    [Result_Stage_1, Result_File_Stage_1] = ...
        solve_one_stage(mpc, CONF_Stage_1, Results_Directory);

    if Result_Stage_1.Diagnostics.mip_gap <= ...
            CONF.Solver.Two_Stage.Stage_2.Options.(Solver_Name).MIPGap
        fprintf('%s第一阶段已达到最终目标间隙，跳过第二阶段。\n', Case_Name);
        Result = Result_Stage_1;
        Result_File = Result_File_Stage_1;
        Total_Time = Result_Stage_1.Diagnostics.walltime;
    else
        % 第二阶段使用第一阶段的当前最优整数解作为热启动。
        CONF_Stage_2 = apply_multiple_snapshot_solver_stage( ...
            CONF, CONF.Solver.Two_Stage.Stage_2);
        CONF_Stage_2.MIPStart = ...
            build_multiple_snapshot_mip_start_from_result(Result_Stage_1, CONF_Stage_2);
        CONF_Stage_2.MIPStart.Source_File = Result_File_Stage_1;
        fprintf('\n========== %s：第二阶段最优性改进（时限%.0f秒） ==========\n', ...
            Case_Name, CONF_Stage_2.solver.options.(Solver_Name).TimeLimit);
        fprintf('使用第一阶段的整数解进行热启动。\n');
        [Result, Result_File] = solve_one_stage(mpc, CONF_Stage_2, Results_Directory);

        fprintf('\n%s两阶段求解完成。\n第一阶段：%s\n第二阶段：%s\n', ...
            Case_Name, Result_File_Stage_1, Result_File);
        Total_Time = Result_Stage_1.Diagnostics.walltime + Result.Diagnostics.walltime;
    end
end

%% 3. 发送完成通知
Mail_Content = sprintf(['算例计算完成时间：%s。\n', ...
    '规划流程总耗时：%.3f秒（%.2f分钟）。\n', ...
    'D=%d典型日算例最终结果：%s'], ...
    char(datetime('now')), Total_Time, Total_Time/60, ...
    CONF.TypicalDayCount, Result_File);
if Enable_Completion_Notification
    mailTome('算例计算完成', Mail_Content);
end
