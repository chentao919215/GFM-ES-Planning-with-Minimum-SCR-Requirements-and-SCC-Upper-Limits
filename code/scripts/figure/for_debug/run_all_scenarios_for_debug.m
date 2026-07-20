%% 按风电场景和典型日批量生成调试图件。
% 输出目录结构：figs/for_debug/<scenario>/<figure category>/。
% plot_04_security 另外按典型日拆分到对应场景目录下。

script_dir = fileparts(mfilename('fullpath'));
project_root = find_project_root_local(script_dir);
debug_root = fullfile(project_root, 'figs', 'for_debug');
addpath(genpath(fullfile(project_root, 'code', 'functions')));
file_generation_cleanup = configure_simulink_file_generation(project_root); %#ok<NASGU>

% 先读取结果元数据，确定场景数量和名称。
[meta, ~] = load_figure_data('', debug_root, '', 'for_debug', 1);
scenario_count = meta.K;
scenario_names = meta.ScenarioNames;

for scenario_index = 1:scenario_count
    scenario_name = char(scenario_names{scenario_index});
    scenario_root = fullfile(debug_root, scenario_name);

    result_file = '';
    param_file = '';
    typical_day_index = [];
    output_dir = fullfile(scenario_root, '01_planning');
    run(fullfile(script_dir, 'plot_01_planning.m'));

    result_file = '';
    param_file = '';
    typical_day_index = [];
    output_dir = fullfile(scenario_root, '02_operation');
    run(fullfile(script_dir, 'plot_02_operation.m'));

    result_file = '';
    param_file = '';
    typical_day_index = [];
    output_dir = fullfile(scenario_root, '03_line_loading');
    run(fullfile(script_dir, 'plot_03_line_loading.m'));

    for typical_day_index = 1:meta.D
        result_file = '';
        param_file = '';
        output_dir = fullfile(scenario_root, '04_security', ...
            sprintf('D%02d', typical_day_index));
        run(fullfile(script_dir, 'plot_04_security.m'));
        fprintf('04_security_已完成绘图：typical_day_index = %d\n', ...
            typical_day_index);
    end
end

disp('已完成所有典型日和风电场景的调试图件生成。');

function project_root = find_project_root_local(start_dir)
% 从当前脚本目录向上查找同时包含code和simulink/models的项目根目录。
candidate = char(java.io.File(start_dir).getCanonicalPath());
while true
    if isfolder(fullfile(candidate, 'code')) && ...
        isfolder(fullfile(candidate, 'simulink', 'models'))
        project_root = candidate;
        return;
    end
    parent = fileparts(candidate);
    if strcmp(parent, candidate)
        break;
    end
    candidate = parent;
end
error('无法从目录%s找到项目根目录。', start_dir);
end
