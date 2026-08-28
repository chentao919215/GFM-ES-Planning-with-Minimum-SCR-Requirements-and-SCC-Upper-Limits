%% 按风电场景和典型日批量生成调试图件。
% 输出目录结构：figs/for_debug/<scenario>/<figure category>/。
% plot_04_security 另外按典型日拆分到对应场景目录下。

Script_Directory = fileparts(mfilename('fullpath'));
Project_Root = find_project_root_local(Script_Directory);
Debug_Root = fullfile(Project_Root, 'figs', 'for_debug');
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
File_Generation_Cleanup = configure_simulink_file_generation(Project_Root);

% 先读取结果元数据，确定场景数量和名称。
[meta, ~] = load_figure_data('', Debug_Root, '', 'for_debug', 1);
Scenario_Count = meta.K;
Scenario_Names = meta.Scenario_Names;

for Scenario_Index = 1:Scenario_Count
    Scenario_Name = char(Scenario_Names{Scenario_Index});
    Scenario_Root = fullfile(Debug_Root, Scenario_Name);

    Result_File = '';
    Parameter_File = '';
    Typical_Day_Index = [];
    Output_Directory = fullfile(Scenario_Root, '01_planning');
    run(fullfile(Script_Directory, 'plot_01_planning.m'));

    Result_File = '';
    Parameter_File = '';
    Typical_Day_Index = [];
    Output_Directory = fullfile(Scenario_Root, '02_operation');
    run(fullfile(Script_Directory, 'plot_02_operation.m'));

    Result_File = '';
    Parameter_File = '';
    Typical_Day_Index = [];
    Output_Directory = fullfile(Scenario_Root, '03_line_loading');
    run(fullfile(Script_Directory, 'plot_03_line_loading.m'));

    for Typical_Day_Index = 1:meta.D
        Result_File = '';
        Parameter_File = '';
        Output_Directory = fullfile(Scenario_Root, '04_security', ...
            sprintf('D%02d', Typical_Day_Index));
        run(fullfile(Script_Directory, 'plot_04_security.m'));
        fprintf('04_security_已完成绘图：typical_day_index = %d\n', ...
            Typical_Day_Index);
    end
end

disp('已完成所有典型日和风电场景的调试图件生成。');

function Project_Root = find_project_root_local(Start_Directory)
% 从当前脚本目录向上查找同时包含code和simulink/models的项目根目录。
candidate = char(java.io.File(Start_Directory).getCanonicalPath());
while true
    if isfolder(fullfile(candidate, 'code')) && ...
        isfolder(fullfile(candidate, 'simulink', 'models'))
        Project_Root = candidate;
        return;
    end
    parent = fileparts(candidate);
    if strcmp(parent, candidate)
        break;
    end
    candidate = parent;
end
error('无法从目录%s找到项目根目录。', Start_Directory);
end
