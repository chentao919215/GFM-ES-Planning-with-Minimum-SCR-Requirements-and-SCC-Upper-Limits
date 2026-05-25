%% IEEE-30 单时刻 GFM-ES 配置算例
% GFL 投建状态由 data/params 中的参数文件给定，脚本只负责组织运行流程。
project_root = resolve_project_root_for_script();
addpath(genpath(fullfile(project_root, 'code', 'functions')));

%% 1. 加载算例与参数
[mpc, CONF, paths] = load_single_snapshot_case(project_root);

%% 2. 调用单时刻优化模型
tic;

[SCC_0,SCC_1,P_Line,theta,P_G,P_GFL,P_GFM,SCR,Z_val,...
    u_GFL,u_GFM,u_G,Cost_CON,Cost_GEN,Cost_Total,Diagnostics] = solve_single_snapshot_planning(mpc,CONF);

time = toc;

%% 3. 归档求解结果
Result = package_single_snapshot_result(SCC_0,SCC_1,P_Line,theta,P_G,P_GFL,P_GFM,...
    SCR,Z_val,u_GFL,u_GFM,u_G,Cost_CON,Cost_GEN,Cost_Total,time,CONF,Diagnostics);

%% 4. 保存并汇总结果
result_file = save_single_snapshot_result(Result, paths.results_dir);
print_single_snapshot_summary(Result, result_file);
send_optional_completion_mail('Experiment completed', ['Experiment completed at ', char(datetime('now'))]);

function project_root = resolve_project_root_for_script()
%RESOLVE_PROJECT_ROOT_FOR_SCRIPT 为不同 MATLAB 运行方式定位项目根目录。

explicit_root = getenv('PROJECT_2_ROOT');

candidates = {};
script_file = mfilename('fullpath');
if ~isempty(script_file)
    candidates{end+1} = fileparts(fileparts(fileparts(script_file)));
end

candidates{end+1} = pwd;
candidates{end+1} = fullfile(pwd, '..');
candidates{end+1} = fullfile(pwd, '..', '..');
if ~isempty(explicit_root)
    candidates{end+1} = explicit_root;
end

for k = 1:numel(candidates)
    candidate = candidates{k};
    if is_project_root(candidate)
        project_root = char(java.io.File(candidate).getCanonicalPath());
        return;
    end
end

error('无法定位项目根目录。请确认项目位于 %s，或从项目目录/脚本文件运行。', explicit_root);
end

function tf = is_project_root(candidate)
%IS_PROJECT_ROOT 判断候选目录是否为本项目根目录。

tf = isfolder(fullfile(candidate, 'code', 'functions')) && ...
     isfolder(fullfile(candidate, 'data', 'params')) && ...
     isfile(fullfile(candidate, 'data', 'params', 'single_snapshot_default_params.json'));
end
