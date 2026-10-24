%% Fig. 4. Unit commitment schedules of selected SGs under Case 2, Case 4, and Case 5 on Day 2.
% The figure shows only the commitment states of SGs connected to buses 2
% and 23. Stage 2 result files are read without modifying or resolving them.

Script_Directory = fileparts(mfilename('fullpath'));
Project_Root = find_project_root_local(Script_Directory);
Results_Directory = fullfile(Project_Root, 'results_useful', ...
    'from_laptop', 'IV-B');
Parameter_File = fullfile(Project_Root, 'data', 'params', ...
    'multiple_snapshot_default_params.json');
Output_Directory = fullfile(Project_Root, 'figs', 'for_paper');
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
if ~isfolder(Output_Directory)
    mkdir(Output_Directory);
end

if ~isfile(Parameter_File)
    error('Fig4UC:MissingParameterFile', ...
        'Network parameter file does not exist: %s', Parameter_File);
end
Params = read_json_file(Parameter_File);
if ~isfield(Params, 'Network') || ~isfield(Params.Network, 'mpc') || ...
        ~isfield(Params.Network.mpc, 'gen') || ...
        size(Params.Network.mpc.gen, 2) < 1
    error('Fig4UC:MissingGeneratorNetworkData', ...
        'Network parameters do not contain MATPOWER generator bus data.');
end

% MATPOWER gen column 1 is GEN_BUS; use it to map bus IDs to UC rows.
Generator_Buses = Params.Network.mpc.gen(:,1);
if any(~isfinite(Generator_Buses)) || ...
        any(Generator_Buses ~= round(Generator_Buses))
    error('Fig4UC:InvalidGeneratorBusData', ...
        'Generator bus IDs must be finite integers.');
end
Selected_Buses = [2;23];
Selected_Generator_Indices = zeros(size(Selected_Buses));
for Bus_Index = 1:numel(Selected_Buses)
    Generator_Index = find(Generator_Buses == Selected_Buses(Bus_Index));
    if isempty(Generator_Index)
        error('Fig4UC:MissingSelectedGenerator', ...
            'No synchronous generator is connected to bus %d.', ...
            Selected_Buses(Bus_Index));
    elseif numel(Generator_Index) > 1
        error('Fig4UC:MultipleSelectedGenerators', ...
            ['Expected one synchronous generator at bus %d, found %d. ', ...
            'The requested bus-to-generator mapping is ambiguous.'], ...
            Selected_Buses(Bus_Index), numel(Generator_Index));
    end
    Selected_Generator_Indices(Bus_Index) = Generator_Index;
end
fprintf('Selected SG mapping: ');
for Bus_Index = 1:numel(Selected_Buses)
    fprintf('Bus %d -> SG index %d', Selected_Buses(Bus_Index), ...
        Selected_Generator_Indices(Bus_Index));
    if Bus_Index < numel(Selected_Buses)
        fprintf('; ');
    else
        fprintf('\n');
    end
end

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
        error('Fig4UC:MissingStage2Result', ...
            'Stage 2 result for Case %d does not exist: %s', ...
            Case_Number, File_Path);
    end
    Loaded = load(File_Path, 'Result');
    if ~isfield(Loaded, 'Result') || ~isstruct(Loaded.Result)
        error('Fig4UC:MissingResultStructure', ...
            'MAT file does not contain a Result structure: %s', File_Path);
    end
    Result = Loaded.Result;
    UC_Matrices{Case_Index} = extract_day_uc(Result, File_Path, ...
        size(Params.Network.mpc.gen,1), Selected_Generator_Indices, ...
        Day_Index, Expected_Period_Count);
    Case_Files{Case_Index} = File_Path;
    fprintf(['Loaded Case %d from %s; Day %d selected UC matrix is ', ...
        '%d-by-%d and binary: yes.\n'], Case_Number, File_Path, ...
        Day_Index, size(UC_Matrices{Case_Index},1), ...
        size(UC_Matrices{Case_Index},2));
end

% Report the actual selected-unit hours where the deterministic and
% stochastic security-constrained cases differ.
Case_4_Position = find(Case_Numbers == 4, 1);
Case_5_Position = find(Case_Numbers == 5, 1);
Case_4_vs_5_Difference = UC_Matrices{Case_4_Position} ~= ...
    UC_Matrices{Case_5_Position};
fprintf('Case 4 vs. Case 5 selected UC differences on Day %d:\n', Day_Index);
if ~any(Case_4_vs_5_Difference, 'all')
    fprintf('No differences for buses %s.\n', mat2str(Selected_Buses.'));
else
    for Bus_Index = 1:numel(Selected_Buses)
        Different_Hours = find(Case_4_vs_5_Difference(Bus_Index,:));
        if ~isempty(Different_Hours)
            fprintf('Bus %d (SG index %d): hours %s.\n', ...
                Selected_Buses(Bus_Index), ...
                Selected_Generator_Indices(Bus_Index), ...
                mat2str(Different_Hours));
        end
    end
end

Figure_Width = 3.50;
Figure_Height = 2.45;
fig = new_paper_figure(Figure_Width, Figure_Height);
layout = tiledlayout(fig, numel(Case_Numbers), 1, ...
    'Padding', 'compact', 'TileSpacing', 'compact');
Offline_Color = [108 170 196]/255; % #6CAAC4, Fig. 3 SCR color
Online_Color = [89 142 187]/255;   % #598EBB, Fig. 3 SCC color
Grid_Color = [0.77 0.80 0.83];
Hour_Ticks = [1 4 8 12 16 20 24];
Axes = gobjects(numel(Case_Numbers),1);
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

Legend_Handles = gobjects(2,1);
Legend_Handles(1) = patch(Axes(1), nan, nan, Offline_Color, ...
    'EdgeColor', Grid_Color);
Legend_Handles(2) = patch(Axes(1), nan, nan, Online_Color, ...
    'EdgeColor', Online_Color);
legend(Axes(1), Legend_Handles, {'Offline (0)','Online (1)'}, ...
    'Location', 'northoutside', 'Orientation', 'horizontal', ...
    'NumColumns', 2, 'FontName', 'Times New Roman', ...
    'FontSize', 7.5, 'Box', 'off');

Output_Base = fullfile(Output_Directory, ...
    'Fig_4_Selected_UC_Schedules_Day2');
save_paper_figure(fig, Output_Base);
fprintf('Fig. 4 exported to %s.[pdf|png|fig]\n', Output_Base);

function UC_Selected = extract_day_uc(Result, File_Path, Generator_Count, ...
    Selected_Generator_Indices, Day_Index, Expected_Period_Count)
%% Validate and extract the shared UC state for one typical day.

Required_Fields = {'u_G','CONF','Dimensions','Diagnostics'};
Missing_Fields = Required_Fields(~isfield(Result, Required_Fields));
if ~isempty(Missing_Fields)
    error('Fig4UC:MissingResultFields', ...
        'Result in %s is missing: %s.', File_Path, ...
        strjoin(Missing_Fields, ', '));
end
C = Result.CONF;
Required_CONF_Fields = {'Gn','TypicalDayCount','PeriodCount'};
Missing_CONF_Fields = Required_CONF_Fields(~isfield(C,Required_CONF_Fields));
if ~isempty(Missing_CONF_Fields)
    error('Fig4UC:MissingResultConfiguration', ...
        'CONF in %s is missing: %s.', File_Path, ...
        strjoin(Missing_CONF_Fields, ', '));
end
if C.Gn ~= Generator_Count || C.TypicalDayCount < Day_Index || ...
        C.PeriodCount ~= Expected_Period_Count
    error('Fig4UC:UnexpectedResultDimensions', ...
        ['Result in %s has Gn=%d, TypicalDayCount=%d, PeriodCount=%d; ', ...
        'expected Gn=%d, at least %d typical days, and %d periods.'], ...
        File_Path, C.Gn, C.TypicalDayCount, C.PeriodCount, ...
        Generator_Count, Day_Index, Expected_Period_Count);
end

Expected_UC_Dimensions = {'generator','typical_day','period'};
if ~isfield(Result.Dimensions, 'SharedUC') || ...
        ~isequal(reshape(cellstr(string(Result.Dimensions.SharedUC)),1,[]), ...
        Expected_UC_Dimensions)
    error('Fig4UC:UnexpectedUCDimensionOrder', ...
        'Shared UC dimensions in %s are not [generator, typical_day, period].', ...
        File_Path);
end
if ~isfield(Result.Diagnostics, 'problem') || ...
        ~isscalar(Result.Diagnostics.problem) || Result.Diagnostics.problem ~= 0
    error('Fig4UC:UnsuccessfulSolve', ...
        'Stage 2 result was not solved successfully: %s', File_Path);
end
if isfield(Result.Diagnostics, 'has_incumbent') && ...
        (~isscalar(Result.Diagnostics.has_incumbent) || ...
        ~logical(Result.Diagnostics.has_incumbent))
    error('Fig4UC:MissingIncumbent', ...
        'Stage 2 result has no incumbent solution: %s', File_Path);
end

Expected_Size = [Generator_Count C.TypicalDayCount C.PeriodCount];
if ~size_matches(Result.u_G, Expected_Size)
    error('Fig4UC:UCDimensionMismatch', ...
        'u_G dimensions in %s do not match saved UC metadata.', File_Path);
end
UC_Day = reshape(Result.u_G(:,Day_Index,:), ...
    Generator_Count, Expected_Period_Count);
if any(~isfinite(UC_Day(:))) || ...
        any(UC_Day(:) ~= 0 & UC_Day(:) ~= 1)
    error('Fig4UC:NonbinaryUC', ...
        'Day %d u_G values in %s are not binary.', Day_Index, File_Path);
end
UC_Selected = UC_Day(Selected_Generator_Indices,:);
if ~isequal(size(UC_Selected), [numel(Selected_Generator_Indices), ...
        Expected_Period_Count])
    error('Fig4UC:SelectedUCDimensionMismatch', ...
        'Selected Day %d UC matrix in %s is not %d-by-%d.', ...
        Day_Index, File_Path, numel(Selected_Generator_Indices), ...
        Expected_Period_Count);
end

end

function Matches = size_matches(Value, Expected)
Actual = size(Value);
Actual(end+1:numel(Expected)) = 1;
Matches = isequal(Actual(1:numel(Expected)), Expected);
end

function fig = new_paper_figure(Figure_Width, Figure_Height)
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', ...
    'Position', [1 1 Figure_Width Figure_Height], ...
    'PaperUnits', 'inches', ...
    'PaperPosition', [0 0 Figure_Width Figure_Height], ...
    'PaperSize', [Figure_Width Figure_Height], ...
    'PaperPositionMode', 'manual');
end

function save_paper_figure(fig, Output_Base)
%% Save FIG, vector PDF, and high-resolution PNG with temporary files.

set(fig, 'Color', 'w', 'InvertHardcopy', 'off');
drawnow;
Output_Directory = fileparts(Output_Base);
Target_Paths = {[Output_Base '.fig'], [Output_Base '.pdf'], ...
    [Output_Base '.png']};
Temp_Paths = {[tempname(Output_Directory) '.fig'], ...
    [tempname(Output_Directory) '.pdf'], ...
    [tempname(Output_Directory) '.png']};
Cleanup_Temp_Files = onCleanup(@() delete_temp_files(Temp_Paths));

set(fig, 'Visible', 'on');
savefig(fig, Temp_Paths{1});
set(fig, 'Renderer', 'painters');
print(fig, Temp_Paths{2}, '-dpdf', '-vector');
print(fig, Temp_Paths{3}, '-dpng', '-r600');
for File_Index = 1:numel(Target_Paths)
    [Success, Message] = movefile(Temp_Paths{File_Index}, ...
        Target_Paths{File_Index}, 'f');
    if ~Success
        error('Fig4UC:ExportFailure', ...
            'Cannot replace figure file %s: %s', ...
            Target_Paths{File_Index}, Message);
    end
end
set(fig, 'Visible', 'off');
close(fig);
end

function delete_temp_files(File_Paths)
for File_Index = 1:numel(File_Paths)
    if isfile(File_Paths{File_Index})
        delete(File_Paths{File_Index});
    end
end
end

function Project_Root = find_project_root_local(Start_Directory)
Candidate = char(java.io.File(Start_Directory).getCanonicalPath());
while true
    if isfolder(fullfile(Candidate, 'code')) && ...
            isfolder(fullfile(Candidate, 'simulink', 'models'))
        Project_Root = Candidate;
        return;
    end
    Parent = fileparts(Candidate);
    if strcmp(Parent, Candidate)
        break;
    end
    Candidate = Parent;
end
error('Fig4UC:ProjectRootNotFound', ...
    'Cannot find the project root from %s.', Start_Directory);
end
