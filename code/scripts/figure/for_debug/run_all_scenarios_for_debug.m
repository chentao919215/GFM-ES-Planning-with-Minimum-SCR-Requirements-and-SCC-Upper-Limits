function Report = run_all_scenarios_for_debug(Options)
%% 固定一个规划结果文件，按场景和典型日批量生成检查图。
if nargin < 1
    Options = struct();
end
Script_Directory = fileparts(mfilename('fullpath'));
addpath(fullfile(fileparts(fileparts(fileparts(Script_Directory))), 'functions', 'utils'));
Project_Root = find_project_root(Script_Directory);
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
Options = figure_options(Options, struct('Result_File', '', ...
    'Output_Directory', fullfile(Project_Root, 'figs', 'for_debug')));
[Meta, ~, Result_File] = load_figure_data(Options.Result_File, ...
    Options.Output_Directory, 'for_debug', 1);
Entries = {};
for Scenario_Index = 1:Meta.K
    Directory = fullfile(Options.Output_Directory, sprintf('scenario_%d', Scenario_Index));
    Point = struct('Result_File', Result_File, 'Scenario_Index', Scenario_Index, ...
        'Visible', Options.Visible, 'Close_After_Save', Options.Close_After_Save);
    Point.Output_Directory = fullfile(Directory, '01_planning');
    Entries{end+1} = plot_01_planning(Point); %#ok<AGROW>
    Point.Output_Directory = fullfile(Directory, '02_operation');
    Entries{end+1} = plot_02_operation(Point); %#ok<AGROW>
    Point.Output_Directory = fullfile(Directory, '03_line_loading');
    Entries{end+1} = plot_03_line_loading(Point); %#ok<AGROW>
    for Day = 1:Meta.D
        Point.Typical_Day_Index = Day;
        Point.Output_Directory = fullfile(Directory, '04_security', sprintf('D%02d', Day));
        Entries{end+1} = plot_04_security(Point); %#ok<AGROW>
    end
end
Report = struct('Result_File', Result_File, 'Entries', {Entries});
fprintf('Debug figures saved to %s\n', Options.Output_Directory);
end
