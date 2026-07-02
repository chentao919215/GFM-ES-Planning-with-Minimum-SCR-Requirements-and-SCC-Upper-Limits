%% IEEE-30多时刻GFM-ES配置算例
% 先按当前两阶段配置求解D=1普通典型日，再以其最终整数解热启动D=3算例。
% 任一算例的第一阶段若已直接收敛，则跳过该算例的第二阶段。
project_root = resolve_project_root_for_script();
addpath(genpath(fullfile(project_root, 'code', 'functions')));

% 参数源脚本会重新生成供程序读取的JSON文件。
run(fullfile(project_root, 'data', 'params', 'generate_multiple_snapshot_default_params.m'));

%% 1. 加载完整D=3算例并构造D=1普通典型日算例
param_file = fullfile(project_root, 'data', 'params', 'multiple_snapshot_default_params.json');
[mpc, CONF_D3, paths] = load_multiple_snapshot_case(project_root, param_file);
if CONF_D3.TypicalDayCount ~= 3
    error('主脚本要求参数文件包含3个典型日，当前TypicalDayCount=%d。', ...
        CONF_D3.TypicalDayCount);
end

CONF_D1 = build_single_typical_day_case(CONF_D3);
[CONF_D1, MIPStartInfo] = attach_latest_multiple_snapshot_mip_start( ...
    CONF_D1, paths.results_dir);
if MIPStartInfo.used
    fprintf('D=1算例已加载历史整数热启动：%s\n', MIPStartInfo.result_file);
elseif CONF_D1.UseLatestMIPStart
    fprintf('D=1算例未加载历史整数热启动：%s\n', MIPStartInfo.reason);
end

%% 2. 求解D=1普通典型日算例
[Result_D1, result_file_D1, solve_time_D1] = solve_case( ...
    mpc, CONF_D1, paths, 'D=1普通典型日');

%% 3. 使用D=1最终结果热启动并求解D=3完整算例
% D=1的逐时整数状态复制到三个典型日，规划状态和聚合安全状态直接继承。
CONF_D3.MIPStart = build_multiple_snapshot_mip_start_from_result( ...
    Result_D1, CONF_D3);
CONF_D3.MIPStart.SourceFile = result_file_D1;
fprintf('\nD=3算例已采用D=1最终结果作为整数热启动：%s\n', result_file_D1);
[Result, result_file, solve_time_D3] = solve_case( ...
    mpc, CONF_D3, paths, 'D=3完整典型日');

total_time = solve_time_D1 + solve_time_D3;

mail_content = sprintf(['Experiment completed at %s.\n', ...
    'Total solver time: %.3f s (%.2f min).\n', ...
    'D=1 final result: %s\nD=3 final result: %s'], ...
    char(datetime('now')), total_time, total_time/60, ...
    result_file_D1, result_file);
send_optional_completion_mail('Experiment completed', mail_content);

function CONF_D1 = build_single_typical_day_case(CONF_D3)
%% 从D=3算例中提取第一个普通典型日，并按全年365天重新设置运行权重。

CONF_D1 = CONF_D3;
CONF_D1.TypicalDayCount = 1;
CONF_D1.TypicalDayWeights_Days = sum(CONF_D3.TypicalDayWeights_Days);
CONF_D1.OperatingWeights_Hours = ...
    CONF_D1.TypicalDayWeights_Days*CONF_D1.PeriodDurations_Hours.';
CONF_D1.P_Load_Profile = CONF_D3.P_Load_Profile(:,1,:);
CONF_D1.P_GFL_Available_Profile = CONF_D3.P_GFL_Available_Profile(:,1,:);

% 历史热启动由D=1算例单独匹配，避免沿用D=3维度的整数初值。
if isfield(CONF_D1, 'MIPStart')
    CONF_D1 = rmfield(CONF_D1, 'MIPStart');
end

end

function [Result, result_file, total_time] = solve_case(mpc, CONF, paths, case_name)
%% 按当前配置执行单阶段或两阶段求解，并在第一阶段收敛时提前结束。

CONF.CaseName = case_name;
two_stage_enabled = isfield(CONF.Solver, 'TwoStage') && ...
    isfield(CONF.Solver.TwoStage, 'Enabled') && ...
    logical(CONF.Solver.TwoStage.Enabled);

if ~two_stage_enabled
    fprintf('\n========== %s：单阶段求解 ==========\n', case_name);
    [Result, result_file] = solve_one_stage(mpc, CONF, paths);
    total_time = Result.solve_time;
    return;
end

% 第一阶段优先寻找高质量可行解，并保留调用方提供的D=1或历史热启动。
CONF_stage1 = apply_multiple_snapshot_solver_stage( ...
    CONF, CONF.Solver.TwoStage.Stage1);
fprintf('\n========== %s第一阶段：可行解搜索（时限 %.0f s）==========\n', ...
    case_name, CONF_stage1.Solver.TimeLimit);
[Result_stage1, result_file_stage1] = solve_one_stage( ...
    mpc, CONF_stage1, paths);

if Result_stage1.Diagnostics.problem == 0
    % 第一阶段已满足求解器收敛判据，无需重复执行最优性证明阶段。
    fprintf('%s第一阶段已直接收敛，跳过第二阶段。\n', case_name);
    Result = Result_stage1;
    result_file = result_file_stage1;
    total_time = Result_stage1.solve_time;
    return;
end

% 第一阶段未直接收敛时，采用其当前最优可行整数解热启动第二阶段。
CONF_stage2 = apply_multiple_snapshot_solver_stage( ...
    CONF, CONF.Solver.TwoStage.Stage2);
CONF_stage2.MIPStart = build_multiple_snapshot_mip_start_from_result( ...
    Result_stage1, CONF_stage2);
CONF_stage2.MIPStart.SourceFile = result_file_stage1;
fprintf('\n========== %s第二阶段：最优性证明（时限 %.0f s）==========\n', ...
    case_name, CONF_stage2.Solver.TimeLimit);
fprintf('已采用%s第一阶段最优可行解作为整数热启动。\n', case_name);
[Result, result_file] = solve_one_stage(mpc, CONF_stage2, paths);

fprintf('\n%s两阶段求解完成。\n第一阶段结果：%s\n第二阶段结果：%s\n', ...
    case_name, result_file_stage1, result_file);
total_time = Result_stage1.solve_time + Result.solve_time;

end

function [Result, result_file] = solve_one_stage(mpc, CONF, paths)
%% 执行一次求解、归档并打印摘要。
tic;
[SCC_0,SCC_1,P_Line,theta,P_G,P_GFL,P_GFM,SCR,Z_SCC,Z_SCR, ...
    u_GFL,u_G,u_G_SCC,u_G_SCR,Cost_CON,Cost_GEN,Cost_Total,Diagnostics, ...
    u_GFM_Mod,P_GFM_Dis,P_GFM_Ch,E_GFM,u_GFM_Ch,P_GFL_Curt,Cost_Curt, ...
    u_G_Start,u_G_Stop,Cost_UC] = ...
    solve_multiple_snapshot_planning(mpc, CONF);
solve_time = toc;

Result = package_multiple_snapshot_result(SCC_0,SCC_1,P_Line,theta,P_G,P_GFL,P_GFM, ...
    SCR,Z_SCC,Z_SCR,u_GFL,u_G,u_G_SCC,u_G_SCR,Cost_CON,Cost_GEN,Cost_Total, ...
    solve_time,CONF,Diagnostics,u_GFM_Mod,P_GFM_Dis,P_GFM_Ch,E_GFM,u_GFM_Ch, ...
    P_GFL_Curt,Cost_Curt,u_G_Start,u_G_Stop,Cost_UC);
if isfield(CONF, 'SolveStage')
    Result.SolveStage = CONF.SolveStage;
else
    Result.SolveStage = 'single-stage';
end

result_file = save_multiple_snapshot_result(Result, paths.results_dir);
print_multiple_snapshot_summary(Result, result_file);
end
