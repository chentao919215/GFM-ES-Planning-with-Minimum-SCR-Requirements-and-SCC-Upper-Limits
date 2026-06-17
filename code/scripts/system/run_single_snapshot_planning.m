%% IEEE-30单时刻GFM-ES配置算例
% GFL投建状态由/data/params中的参数脚本给定，脚本只负责组织运行流程。
project_root = resolve_project_root_for_script();
addpath(genpath(fullfile(project_root, 'code', 'functions')));

% generate_single_snapshot_default_params.m脚本用于生成参数文件。
run(fullfile(project_root, 'data', 'params', 'generate_single_snapshot_default_params.m'));

%% 1. 加载算例与参数
% param_file:指定读取的参数文件（默认存放在/data/params文件夹下）。
param_file = fullfile(project_root, 'data', 'params', 'single_snapshot_default_params.json');
[mpc, CONF, paths] = load_single_snapshot_case(project_root,param_file);

%% 2. 调用单时刻优化模型
tic;

[SCC_0,SCC_1,P_Line,theta,P_G,P_GFL,P_GFM,SCR,Z_val,...
    u_GFL,u_G,Cost_CON,Cost_GEN,Cost_Total,Diagnostics,...
    u_GFM_Mod,P_GFM_Mod] = solve_single_snapshot_planning(mpc,CONF);

time = toc;

%% 3. 归档求解结果
Result = package_single_snapshot_result(SCC_0,SCC_1,P_Line,theta,P_G,P_GFL,P_GFM,...
    SCR,Z_val,u_GFL,u_G,Cost_CON,Cost_GEN,Cost_Total,time,CONF,Diagnostics,...
    u_GFM_Mod,P_GFM_Mod);

%% 4. 保存并汇总结果
result_file = save_single_snapshot_result(Result, paths.results_dir);
print_single_snapshot_summary(Result, result_file);
send_optional_completion_mail('Experiment completed', ['Experiment completed at ', char(datetime('now'))]);
