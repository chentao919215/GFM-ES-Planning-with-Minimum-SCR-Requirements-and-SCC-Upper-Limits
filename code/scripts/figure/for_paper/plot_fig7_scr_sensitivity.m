%% Fig. 7: sensitivity of CSCR.
% The IV-C MAT files are read-only.  Each file is required to contain the
% final Stage-2 planning result for one CSCR scan point.

Script_Directory = fileparts(mfilename('fullpath'));
Project_Root = find_project_root_local(Script_Directory);
Results_Directory = fullfile(Project_Root, 'results_useful', ...
    'from_laptop', 'IV-C', 'SCR');
Output_Directory = fullfile(Project_Root, 'figs', 'for_paper');
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
if ~isfolder(Output_Directory)
    mkdir(Output_Directory);
end

Expected_CSCR = [2.3 2.6 2.7 2.8 2.9 3.0];
[Results, Result_Files, CSCR] = load_scr_stage2_results( ...
    Results_Directory, Expected_CSCR);

Total_Annual_Cost_MUSD = zeros(size(CSCR));
Configuration_Class = zeros(size(CSCR));
Configuration_Text = strings(size(CSCR));
for Point_Index = 1:numel(Results)
    Result = Results{Point_Index};
    Total_Annual_Cost_MUSD(Point_Index) = Result.Cost.Total/1e6;
    [Configuration_Class(Point_Index), Configuration_Text(Point_Index)] = ...
        read_gfm_configuration(Result, Result_Files{Point_Index});
end

Figure_Width = 3.50;
Figure_Height = 2.40;
fig = new_paper_figure(Figure_Width, Figure_Height);
layout = tiledlayout(fig, 1, 1, 'Padding', 'compact', ...
    'TileSpacing', 'compact');
ax = nexttile(layout);
style_sci_axes(ax);
hold(ax, 'on');

Category_Position = 1:numel(CSCR);
plot(ax, Category_Position, Total_Annual_Cost_MUSD, '-', ...
    'Color', [0.25 0.25 0.25], 'LineWidth', 0.85, ...
    'HandleVisibility', 'off');
Marker_Definitions = {'o', 's', '^'};
Configuration_Names = {'no GFM-ES', 'one module at bus 10', ...
    'two modules at bus 10'};
Configuration_Colors = [140 205 198; ... % #8CCDC6
                        148 142 193; ... % #948EC1
                        156 203 150]/255; % #9CCB96
Configuration_Edge_Colors = 0.68*Configuration_Colors;
Marker_Handles = gobjects(3, 1);
for Class_Index = 1:3
    Is_Class = Configuration_Class == Class_Index;
    if ~any(Is_Class)
        error('Fig7:MissingConfigurationClass', ...
            'No SCR scan point has configuration class %d.', Class_Index);
    end
    Marker_Handles(Class_Index) = plot(ax, Category_Position(Is_Class), ...
        Total_Annual_Cost_MUSD(Is_Class), Marker_Definitions{Class_Index}, ...
        'LineStyle', 'none', 'MarkerSize', 5.2, ...
        'MarkerFaceColor', Configuration_Colors(Class_Index,:), ...
        'MarkerEdgeColor', Configuration_Edge_Colors(Class_Index,:), ...
        'DisplayName', Configuration_Names{Class_Index});
    try
        Marker_Handles(Class_Index).MarkerFaceAlpha = 0.72;
    catch
        % MarkerFaceAlpha is unavailable in some older MATLAB releases.
    end
end
hold(ax, 'off');

% CSCR=3.1 has no feasible MAT result and is intentionally omitted.
xlim(ax, [0.50, numel(Category_Position)+0.50]);
ylim(ax, [0, 1.12*max(Total_Annual_Cost_MUSD)]);
xticks(ax, Category_Position);
xticklabels(ax, compose('%.1f', CSCR));
xlabel(ax, 'CSCR');
ylabel(ax, 'Total annual cost (M$/yr)');
legend(ax, Marker_Handles, Configuration_Names, ...
    'Location', 'northoutside', 'Orientation', 'horizontal', ...
    'NumColumns', 3, 'FontName', 'Times New Roman', ...
    'FontSize', 7.0, 'Box', 'off');

Output_Base = fullfile(Output_Directory, 'Fig_7_scr_sensitivity');
save_paper_figure(fig, Output_Base);

Fig7_Data = table(CSCR(:), Total_Annual_Cost_MUSD(:), ...
    Configuration_Text(:), string(Result_Files(:)), 'VariableNames', ...
    {'CSCR','TotalAnnualCost_MUSD_per_yr','GFMConfiguration', ...
    'Stage2ResultFile'});
writetable(Fig7_Data, [Output_Base '_data.csv']);
disp(Fig7_Data);
fprintf('Fig. 7 saved to %s.[fig|pdf|png]\n', Output_Base);

function [Results, Result_Files, CSCR_Values] = ...
    load_scr_stage2_results(Results_Directory, Expected_CSCR)
if ~isfolder(Results_Directory)
    error('Fig7:MissingResultsDirectory', ...
        'IV-C SCR results directory does not exist: %s', Results_Directory);
end
Files = dir(fullfile(Results_Directory, '*.mat'));
if isempty(Files)
    error('Fig7:MissingResults', ...
        'No SCR MAT results were found in %s.', Results_Directory);
end

Loaded_Results = cell(numel(Files), 1);
Loaded_CSCR = nan(numel(Files), 1);
for File_Index = 1:numel(Files)
    File_Path = fullfile(Files(File_Index).folder, Files(File_Index).name);
    Loaded = load(File_Path, 'Result');
    if ~isfield(Loaded, 'Result') || ~isstruct(Loaded.Result)
        error('Fig7:MissingResult', ...
            'MAT file does not contain a Result structure: %s', File_Path);
    end
    validate_stage2_result(Loaded.Result, File_Path);
    Loaded_Results{File_Index} = Loaded.Result;
    Loaded_CSCR(File_Index) = read_cscr(Loaded.Result, File_Path);
end

if numel(unique(round(Loaded_CSCR, 10))) ~= numel(Loaded_CSCR)
    error('Fig7:DuplicateCSCR', 'Duplicate CSCR values were found.');
end
if numel(Loaded_CSCR) ~= numel(Expected_CSCR) || ...
        any(sort(Loaded_CSCR(:)) ~= sort(Expected_CSCR(:)))
    error('Fig7:UnexpectedScanPoints', ...
        'IV-C SCR files do not match the requested scan points.');
end

[CSCR_Values, Order] = sort(Loaded_CSCR, 'ascend');
Results = Loaded_Results(Order);
Result_Files = cellfun(@(f) fullfile(Results_Directory, f), ...
    {Files(Order).name}, 'UniformOutput', false);
end

function Value = read_cscr(Result, File_Path)
if ~isfield(Result.CONF, 'SCR_min') || ~isscalar(Result.CONF.SCR_min) || ...
        ~isfinite(Result.CONF.SCR_min)
    error('Fig7:MissingCSCR', 'CSCR is missing or invalid in %s.', File_Path);
end
Value = Result.CONF.SCR_min;
end

function [Class, Text] = read_gfm_configuration(Result, File_Path)
if ~isfield(Result, 'u_GFM_Mod') || ~isfield(Result.CONF, ...
        'GFM_Module_Candidates')
    error('Fig7:MissingGFMConfiguration', ...
        'GFM-ES configuration fields are missing from %s.', File_Path);
end
Module_State = Result.u_GFM_Mod;
if any(~isfinite(Module_State), 'all') || ...
        any(abs(Module_State-round(Module_State)) > 1e-6, 'all')
    error('Fig7:InvalidGFMConfiguration', ...
        'GFM-ES module state is not binary in %s.', File_Path);
end
Module_State = round(Module_State);
Candidate_Buses = Result.CONF.GFM_Module_Candidates(:);
if size(Module_State, 1) ~= numel(Candidate_Buses)
    error('Fig7:GFMConfigurationDimensionMismatch', ...
        'GFM-ES state and candidate-bus dimensions disagree in %s.', File_Path);
end
Module_Counts = sum(Module_State, 2);
Bus_10 = find(Candidate_Buses == 10);
if isempty(Bus_10)
    error('Fig7:MissingBus10Candidate', ...
        'Candidate bus 10 is missing from %s.', File_Path);
end
if all(Module_Counts == 0)
    Class = 1;
    Text = "no GFM-ES";
elseif nnz(Module_Counts) == 1 && Module_Counts(Bus_10) == 1
    Class = 2;
    Text = "one module at bus 10";
elseif nnz(Module_Counts) == 1 && Module_Counts(Bus_10) == 2
    Class = 3;
    Text = "two modules at bus 10";
else
    error('Fig7:UnexpectedGFMConfiguration', ...
        'Unsupported SCR configuration in %s: %s.', File_Path, ...
        mat2str(Module_Counts.'));
end
end

function validate_stage2_result(Result, File_Path)
if ~isfield(Result, 'Cost') || ~isfield(Result.Cost, 'Total') || ...
        ~isscalar(Result.Cost.Total) || ~isfinite(Result.Cost.Total)
    error('Fig7:MissingCost', 'Total cost is missing or invalid in %s.', File_Path);
end
if ~isfield(Result, 'Diagnostics') || Result.Diagnostics.problem ~= 0
    error('Fig7:UnsuccessfulSolve', ...
        'Result is not a successful Stage-2 solve: %s', File_Path);
end
if ~isfield(Result, 'CONF') || ~isfield(Result.CONF, 'SolveStage') || ...
        ~contains(lower(string(Result.CONF.SolveStage)), 'optimality')
    error('Fig7:NotStage2', 'Result is not marked as Stage 2: %s', File_Path);
end
end

function fig = new_paper_figure(Figure_Width, Figure_Height)
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', ...
    'Position', [1 1 Figure_Width Figure_Height], ...
    'PaperUnits', 'inches', 'PaperPosition', [0 0 Figure_Width Figure_Height], ...
    'PaperSize', [Figure_Width Figure_Height], 'PaperPositionMode', 'manual');
end

function save_paper_figure(fig, Output_Base)
set(fig, 'Color', 'w', 'InvertHardcopy', 'off');
drawnow;
Output_Directory = fileparts(Output_Base);
Target_Paths = {[Output_Base '.fig'], [Output_Base '.pdf'], [Output_Base '.png']};
Temp_Paths = {[tempname(Output_Directory) '.fig'], ...
    [tempname(Output_Directory) '.pdf'], [tempname(Output_Directory) '.png']};
Cleanup_Temp_Files = onCleanup(@() delete_temp_files(Temp_Paths)); %#ok<NASGU>
set(fig, 'Visible', 'on');
savefig(fig, Temp_Paths{1});
set(fig, 'Renderer', 'painters');
print(fig, Temp_Paths{2}, '-dpdf', '-vector');
print(fig, Temp_Paths{3}, '-dpng', '-r600');
for File_Index = 1:numel(Target_Paths)
    [Success, Message] = movefile(Temp_Paths{File_Index}, ...
        Target_Paths{File_Index}, 'f');
    if ~Success
        error('Fig7:ExportFailure', 'Cannot write %s: %s', ...
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
error('Fig7:ProjectRootNotFound', ...
    'Cannot find the project root from %s.', Start_Directory);
end
