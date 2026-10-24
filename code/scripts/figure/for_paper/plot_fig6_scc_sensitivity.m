%% Fig. 6: sensitivity of the SCC limit.
% The IV-C MAT files are read-only.  Each file is required to contain the
% final Stage-2 planning result for one SCC-limit scan point.

Script_Directory = fileparts(mfilename('fullpath'));
Project_Root = find_project_root_local(Script_Directory);
Results_Directory = fullfile(Project_Root, 'results_useful', ...
    'from_laptop', 'IV-C', 'SCC');
Output_Directory = fullfile(Project_Root, 'figs', 'for_paper');
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
if ~isfolder(Output_Directory)
    mkdir(Output_Directory);
end

Expected_Limits_kA = [7.6 6.5 6.0 5.9 5.8 5.7 5.6 5.5];
[Results, Result_Files, SCC_Limits_kA] = load_scc_stage2_results( ...
    Results_Directory, Expected_Limits_kA);

Total_Annual_Cost_MUSD = zeros(size(SCC_Limits_kA));
Configuration_Class = zeros(size(SCC_Limits_kA));
Configuration_Text = strings(size(SCC_Limits_kA));
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

Category_Position = 1:numel(SCC_Limits_kA);

% The scan points are ordered categories; tick labels retain the real
% SCC limits while adjacent categories have equal visual spacing.
plot(ax, Category_Position, Total_Annual_Cost_MUSD, '-', ...
    'Color', [0.25 0.25 0.25], 'LineWidth', 0.85, ...
    'HandleVisibility', 'off');
Marker_Definitions = {'o', 's'};
Configuration_Names = {'no GFM-ES', 'one module at bus 10'};
Configuration_Colors = [140 205 198; ... % #8CCDC6
                        148 142 193]/255; % #948EC1
Configuration_Edge_Colors = 0.68*Configuration_Colors;
Marker_Handles = gobjects(2, 1);
for Class_Index = 1:2
    Is_Class = Configuration_Class == Class_Index;
    if ~any(Is_Class)
        error('Fig6:MissingConfigurationClass', ...
            'No SCC scan point has configuration class %d.', Class_Index);
    end
    Marker_Handles(Class_Index) = plot(ax, ...
        Category_Position(Is_Class), Total_Annual_Cost_MUSD(Is_Class), ...
        Marker_Definitions{Class_Index}, 'LineStyle', 'none', ...
        'MarkerSize', 5.2, ...
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

xlim(ax, [0.50, numel(Category_Position)+0.50]);
ylim(ax, [0, 1.12*max(Total_Annual_Cost_MUSD)]);
xticks(ax, Category_Position);
xticklabels(ax, compose('%.1f', SCC_Limits_kA));
xlabel(ax, 'SCC limit (kA)');
ylabel(ax, 'Total annual cost (M$/yr)');
legend(ax, Marker_Handles, Configuration_Names, ...
    'Location', 'northoutside', 'Orientation', 'horizontal', ...
    'NumColumns', 2, 'FontName', 'Times New Roman', ...
    'FontSize', 7.0, 'Box', 'off');

Output_Base = fullfile(Output_Directory, 'Fig_6_scc_sensitivity');
save_paper_figure(fig, Output_Base);

Fig6_Data = table(SCC_Limits_kA(:), Total_Annual_Cost_MUSD(:), ...
    Configuration_Text(:), string(Result_Files(:)), 'VariableNames', ...
    {'SCCLimit_kA','TotalAnnualCost_MUSD_per_yr', ...
    'GFMConfiguration','Stage2ResultFile'});
writetable(Fig6_Data, [Output_Base '_data.csv']);
disp(Fig6_Data);
fprintf('Fig. 6 saved to %s.[fig|pdf|png]\n', Output_Base);

function [Results, Result_Files, Limits_kA] = ...
    load_scc_stage2_results(Results_Directory, Expected_Limits_kA)
if ~isfolder(Results_Directory)
    error('Fig6:MissingResultsDirectory', ...
        'IV-C SCC results directory does not exist: %s', Results_Directory);
end
Files = dir(fullfile(Results_Directory, '*.mat'));
if isempty(Files)
    error('Fig6:MissingResults', ...
        'No SCC MAT results were found in %s.', Results_Directory);
end

Loaded_Results = cell(numel(Files), 1);
Loaded_Limits = nan(numel(Files), 1);
for File_Index = 1:numel(Files)
    File_Path = fullfile(Files(File_Index).folder, Files(File_Index).name);
    Loaded = load(File_Path, 'Result');
    if ~isfield(Loaded, 'Result') || ~isstruct(Loaded.Result)
        error('Fig6:MissingResult', ...
            'MAT file does not contain a Result structure: %s', File_Path);
    end
    validate_stage2_result(Loaded.Result, File_Path);
    Loaded_Results{File_Index} = Loaded.Result;
    Loaded_Limits(File_Index) = read_scc_limit(Loaded.Result, File_Path);
end

if numel(unique(round(Loaded_Limits, 10))) ~= numel(Loaded_Limits)
    error('Fig6:DuplicateLimit', 'Duplicate SCC limits were found.');
end
if numel(Loaded_Limits) ~= numel(Expected_Limits_kA) || ...
        any(sort(Loaded_Limits(:), 'descend') ~= ...
        sort(Expected_Limits_kA(:), 'descend'))
    error('Fig6:UnexpectedScanPoints', ...
        'IV-C SCC files do not match the requested scan points.');
end

[Limits_kA, Order] = sort(Loaded_Limits, 'descend');
Results = Loaded_Results(Order);
Result_Files = cellfun(@(f) fullfile(Results_Directory, f), ...
    {Files(Order).name}, 'UniformOutput', false);
end

function Limit_kA = read_scc_limit(Result, File_Path)
C = Result.CONF;
if isfield(C, 'I_limit_kA_Node')
    Values = C.I_limit_kA_Node(:);
elseif isfield(C, 'I_limit_kA')
    Values = C.I_limit_kA(:);
else
    error('Fig6:MissingSCCLimit', ...
        'SCC limit is missing from %s.', File_Path);
end
if isempty(Values) || any(~isfinite(Values)) || ...
        max(abs(Values-Values(1))) > 1e-10
    error('Fig6:InvalidSCCLimit', ...
        'SCC limit is not one common finite scalar in %s.', File_Path);
end
Limit_kA = Values(1);
end

function [Class, Text] = read_gfm_configuration(Result, File_Path)
if ~isfield(Result, 'u_GFM_Mod') || ~isfield(Result.CONF, ...
        'GFM_Module_Candidates')
    error('Fig6:MissingGFMConfiguration', ...
        'GFM-ES configuration fields are missing from %s.', File_Path);
end
Module_State = Result.u_GFM_Mod;
if any(~isfinite(Module_State), 'all') || ...
        any(abs(Module_State-round(Module_State)) > 1e-6, 'all')
    error('Fig6:InvalidGFMConfiguration', ...
        'GFM-ES module state is not binary in %s.', File_Path);
end
Module_State = round(Module_State);
Candidate_Buses = Result.CONF.GFM_Module_Candidates(:);
if size(Module_State, 1) ~= numel(Candidate_Buses)
    error('Fig6:GFMConfigurationDimensionMismatch', ...
        'GFM-ES state and candidate-bus dimensions disagree in %s.', File_Path);
end
Module_Counts = sum(Module_State, 2);
Bus_10 = find(Candidate_Buses == 10);
if isempty(Bus_10)
    error('Fig6:MissingBus10Candidate', ...
        'Candidate bus 10 is missing from %s.', File_Path);
end
if all(Module_Counts == 0)
    Class = 1;
    Text = "no GFM-ES";
elseif nnz(Module_Counts) == 1 && Module_Counts(Bus_10) == 1
    Class = 2;
    Text = "one module at bus 10";
else
    error('Fig6:UnexpectedGFMConfiguration', ...
        'Unsupported SCC configuration in %s: %s.', File_Path, ...
        mat2str(Module_Counts.'));
end
end

function validate_stage2_result(Result, File_Path)
if ~isfield(Result, 'Cost') || ~isfield(Result.Cost, 'Total') || ...
        ~isscalar(Result.Cost.Total) || ~isfinite(Result.Cost.Total)
    error('Fig6:MissingCost', 'Total cost is missing or invalid in %s.', File_Path);
end
if ~isfield(Result, 'Diagnostics') || Result.Diagnostics.problem ~= 0
    error('Fig6:UnsuccessfulSolve', ...
        'Result is not a successful Stage-2 solve: %s', File_Path);
end
if ~isfield(Result, 'CONF') || ~isfield(Result.CONF, 'SolveStage') || ...
        ~contains(lower(string(Result.CONF.SolveStage)), 'optimality')
    error('Fig6:NotStage2', 'Result is not marked as Stage 2: %s', File_Path);
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
        error('Fig6:ExportFailure', 'Cannot write %s: %s', ...
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
error('Fig6:ProjectRootNotFound', ...
    'Cannot find the project root from %s.', Start_Directory);
end
