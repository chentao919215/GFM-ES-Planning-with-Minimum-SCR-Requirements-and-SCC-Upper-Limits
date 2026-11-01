function Report = plot_fig5_selected_uc_schedules(Options)
%% Fig. 5：Case 2、4、5在典型日2的指定同步机启停状态。
% 仅展示节点2和23处同步机的UC状态，使用已归档的第二阶段结果。
if nargin < 1
    Options = struct();
end

%% 1. 读取并核验论文算例输入
Script_Directory = fileparts(mfilename('fullpath'));
addpath(fullfile(fileparts(fileparts(fileparts(Script_Directory))), ...
    'functions', 'utils'));
Project_Root = find_project_root(Script_Directory);
Results_Directory = fullfile(Project_Root, 'results_for_case', 'IV-B');
Output_Directory = fullfile(Project_Root, 'figs', 'for_paper');
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
Options = figure_options(Options, struct('Input_Directory', Results_Directory, 'Output_Directory', ...
    Output_Directory));
Style = figure_style('paper');
Style.Visible = Options.Visible;
Style.Close_After_Save = Options.Close_After_Save;
Results_Directory = Options.Input_Directory;
Output_Directory = Options.Output_Directory;

if ~isfolder(Output_Directory)
    mkdir(Output_Directory);
end

Selected_Buses = [2 23];
Case_Numbers = [2 4 5];
Day_Index = 2;
Expected_Period_Count = 24;
UC_Matrices = cell(size(Case_Numbers));
Case_Files = cell(size(Case_Numbers));
for Case_Index = 1:numel(Case_Numbers)
    Case_Number = Case_Numbers(Case_Index);
    File_Path = fullfile(Results_Directory, ...
        sprintf('Case_%d_Stage_2.mat', Case_Number));
    if ~isfile(File_Path)
        error('Fig5UC:MissingStage2Result', ...
            'Stage 2 result for Case %d does not exist: %s', ...
            Case_Number, File_Path);
    end
    Loaded = load(File_Path, 'Result');
    if ~isfield(Loaded, 'Result') || ~isstruct(Loaded.Result)
        error('Fig5UC:MissingResultStructure', ...
            'MAT file does not contain a Result structure: %s', File_Path);
    end
    Result = Loaded.Result;
    UC_Matrices{Case_Index} = extract_day_uc(Result, File_Path, ...
        Selected_Buses, ...
        Day_Index, Expected_Period_Count);
    Case_Files{Case_Index} = File_Path;
    fprintf(['Loaded Case %d from %s; Day %d selected UC matrix is ', ...
        '%d-by-%d and binary: yes.\n'], Case_Number, File_Path, ...
        Day_Index, size(UC_Matrices{Case_Index}, 1), ...
        size(UC_Matrices{Case_Index}, 2));
end

% 输出确定性与随机安全约束算例在所选机组和时段上的实际差异。
Case_4_Position = find(Case_Numbers == 4, 1);
Case_5_Position = find(Case_Numbers == 5, 1);
Case_4_vs_5_Difference = UC_Matrices{Case_4_Position} ~= ...
    UC_Matrices{Case_5_Position};
fprintf('Case 4 vs. Case 5 selected UC differences on Day %d:\n', Day_Index);
if ~any(Case_4_vs_5_Difference, 'all')
    fprintf('No differences for buses %s.\n', mat2str(Selected_Buses.'));
else
    for Bus_Index = 1:numel(Selected_Buses)
        Different_Hours = find(Case_4_vs_5_Difference(Bus_Index, :));
        if ~isempty(Different_Hours)
            fprintf('Bus %d: hours %s.\n', ...
                Selected_Buses(Bus_Index), ...
                mat2str(Different_Hours));
        end
    end
end

Figure_Width = 3.50;
Figure_Height = 2.45;

%% 2. 绘制论文图件
fig = new_figure(2.54*[Figure_Width Figure_Height], Style);
layout = tiledlayout(fig, numel(Case_Numbers), 1, ...
    'Padding', 'compact', 'TileSpacing', 'compact');
Offline_Color = Style.Colors.Offline;
Online_Color = Style.Colors.Online;
Grid_Color = [0.77 0.80 0.83];
Hour_Ticks = [1 4 8 12 16 20 24];
Axes = gobjects(numel(Case_Numbers), 1);
for Case_Index = 1:numel(Case_Numbers)
    Axes(Case_Index) = nexttile(layout);
    ax = Axes(Case_Index);
    imagesc(ax, 1:Expected_Period_Count, 1:numel(Selected_Buses), ...
        UC_Matrices{Case_Index});
    colormap(ax, [Offline_Color;Online_Color]);
    clim(ax, [0 1]);
    style_sci_axes(ax);
    grid(ax, 'off');
    set(ax, 'YDir', 'reverse', 'YTick', 1:numel(Selected_Buses), ...
        'YTickLabel', compose('Bus %d', Selected_Buses), ...
        'XTick', Hour_Ticks, 'XTickLabel', string(Hour_Ticks), ...
        'FontSize', 7.5, 'TickLength', [0.005 0.005]);
    xlim(ax, [0.5 Expected_Period_Count+0.5]);
    ylim(ax, [0.5 numel(Selected_Buses)+0.5]);
    title(ax, sprintf('Case %d', Case_Numbers(Case_Index)), ...
        'FontName', 'Times New Roman', 'FontSize', 8.5, ...
        'FontWeight', 'normal');
    for Hour_Boundary = 0.5:1:Expected_Period_Count+0.5
        xline(ax, Hour_Boundary, '-', 'Color', Grid_Color, ...
            'LineWidth', 0.30, 'HandleVisibility', 'off');
    end
    for Bus_Boundary = 0.5:1:numel(Selected_Buses)+0.5
        yline(ax, Bus_Boundary, '-', 'Color', Grid_Color, ...
            'LineWidth', 0.35, 'HandleVisibility', 'off');
    end
end
xlabel(Axes(end), 'Time (\it{h}\rm)', 'FontName', 'Times New Roman', ...
    'FontSize', 8);

Legend_Handles = gobjects(2, 1);
Legend_Handles(1) = patch(Axes(1), nan, nan, Offline_Color, ...
    'EdgeColor', Grid_Color);
Legend_Handles(2) = patch(Axes(1), nan, nan, Online_Color, ...
    'EdgeColor', Online_Color);
legend(Axes(1), Legend_Handles, {'Offline (0)', 'Online (1)'}, ...
    'Location', 'northoutside', 'Orientation', 'horizontal', ...
    'NumColumns', 2, 'FontName', 'Times New Roman', ...
    'FontSize', 7.5, 'Box', 'off');

Output_Base = fullfile(Output_Directory, ...
    'Fig_5_Selected_UC_Schedules_Day2');
save_figure_file(fig, Output_Base);
fprintf('Fig. 5 exported to %s.fig\n', Output_Base);

%% 3. 返回绘图数据与文件位置
Report = struct('UC', {UC_Matrices}, 'Case_Numbers', Case_Numbers, ...
    'Day_Index', Day_Index, 'Figure_File', [Output_Base '.fig']);
end

function UC_Selected = extract_day_uc(Result, File_Path, Selected_Buses, ...
    Day_Index, Expected_Period_Count)
%% 核验并提取指定典型日内跨场景共享的机组启停状态。

Required_Fields = {'u_G', 'CONF', 'Diagnostics'};
Missing_Fields = Required_Fields(~isfield(Result, Required_Fields));
if ~isempty(Missing_Fields)
    error('Fig5UC:MissingResultFields', ...
        'Result in %s is missing: %s.', File_Path, ...
        strjoin(Missing_Fields, ', '));
end
C = Result.CONF;
Required_CONF_Fields = {'Gn', 'TypicalDayCount', 'PeriodCount', 'Generator_Buses'};
Missing_CONF_Fields = Required_CONF_Fields(~isfield(C, Required_CONF_Fields));
if ~isempty(Missing_CONF_Fields)
    error('Fig5UC:MissingResultConfiguration', ...
        'CONF in %s is missing: %s.', File_Path, ...
        strjoin(Missing_CONF_Fields, ', '));
end
Generator_Count = numel(C.Generator_Buses);
if C.Gn ~= Generator_Count || C.TypicalDayCount < Day_Index || ...
        C.PeriodCount ~= Expected_Period_Count
    error('Fig5UC:UnexpectedResultDimensions', ...
        'Saved generator mapping or time dimensions are invalid: %s', File_Path);
end
Selected_Generator_Indices = zeros(size(Selected_Buses));
for k = 1:numel(Selected_Buses)
    Index = find(C.Generator_Buses == Selected_Buses(k));
    if numel(Index) ~= 1
        error('Fig5UC:SelectedGeneratorMapping', ...
            'Expected one generator at bus %d: %s', Selected_Buses(k), File_Path);
    end
    Selected_Generator_Indices(k) = Index;
end
if ~isfield(Result.Diagnostics, 'problem') || ...
        ~isscalar(Result.Diagnostics.problem) || Result.Diagnostics.problem ~= 0
    error('Fig5UC:UnsuccessfulSolve', ...
        'Stage 2 result was not solved successfully: %s', File_Path);
end
if ~isscalar(Result.Diagnostics.has_incumbent) || ...
        ~logical(Result.Diagnostics.has_incumbent)
    error('Fig5UC:MissingIncumbent', ...
        'Stage 2 result has no incumbent solution: %s', File_Path);
end

Expected_Size = [Generator_Count C.TypicalDayCount C.PeriodCount];
if ~size_matches(Result.u_G, Expected_Size)
    error('Fig5UC:UCDimensionMismatch', ...
        'u_G dimensions in %s do not match saved UC metadata.', File_Path);
end
UC_Day = reshape(Result.u_G(:, Day_Index, :), ...
    Generator_Count, Expected_Period_Count);
if any(~isfinite(UC_Day(:))) || ...
        any(UC_Day(:) ~= 0 & UC_Day(:) ~= 1)
    error('Fig5UC:NonbinaryUC', ...
        'Day %d u_G values in %s are not binary.', Day_Index, File_Path);
end
UC_Selected = UC_Day(Selected_Generator_Indices, :);
if ~isequal(size(UC_Selected), [numel(Selected_Generator_Indices), ...
        Expected_Period_Count])
    error('Fig5UC:SelectedUCDimensionMismatch', ...
        'Selected Day %d UC matrix in %s is not %d-by-%d.', ...
        Day_Index, File_Path, numel(Selected_Generator_Indices), ...
        Expected_Period_Count);
end

end

function Matches = size_matches(Value, Expected)
%% 比较数组维度，补齐MATLAB省略的尾部单维。
Actual = size(Value);
Actual(end+1:numel(Expected)) = 1;
Matches = isequal(Actual(1:numel(Expected)), Expected);
end
