%% Fig. 6: SCR conservatism and tightness across all Stage 2 cases.
% Each point represents one case and one representative day for the
% single-GFL-WG system.  The x-coordinate is the minimum hourly SCR
% obtained from the final schedule, while the y-coordinate is the
% corresponding aggregated SCR lower bound.  The diagonal y=x is the
% conservatism reference line.

Script_Directory = fileparts(mfilename('fullpath'));
Project_Root = find_project_root_local(Script_Directory);
Results_Directory = fullfile(Project_Root, 'results_useful', ...
    'from_laptop', 'IV-B');
Output_Directory = fullfile(Project_Root, 'figs', 'for_paper');
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
if ~isfolder(Output_Directory)
    mkdir(Output_Directory);
end

[Case_Results, Case_Files] = load_all_stage2_cases(Results_Directory);
[Case_Results, SCR_Nodes, Representative_Day_Count, Period_Count] = ...
    validate_all_cases(Case_Results, Case_Files);
Case_Count = numel(Case_Results);

[Fig6_Data, Case_Statistics] = build_scr_scatter_data( ...
    Case_Results, Case_Files, SCR_Nodes, Representative_Day_Count, ...
    Period_Count);
print_case_statistics(Fig6_Data, Case_Statistics);

Figure_Width = 3.50;
Figure_Height = 2.40;
fig = new_paper_figure(Figure_Width, Figure_Height);
layout = tiledlayout(fig, 1, 1, 'Padding', 'compact', ...
    'TileSpacing', 'compact');
ax = nexttile(layout);

hold(ax, 'on');

Case_Markers = {'o', 's', '^', 'd', 'v'};
% Use the same five case colors and marker styles as Fig. 5.
Case_Colors = [140 205 198; ... % #8CCDC6
               148 142 193; ... % #948EC1
               156 203 150; ... % #9CCB96
               108 170 196; ... % #6CAAC4
               232 164 105]/255; % #E8A469
Case_Edge_Colors = 0.68*Case_Colors;
Case_Handles = gobjects(Case_Count, 1);
for Case_Index = 1:Case_Count
    Case_Data = Fig6_Data(Fig6_Data.CaseIndex == Case_Index, :);
    Case_Handles(Case_Index) = plot(ax, Case_Data.MinimumHourlySCR, ...
        Case_Data.AggregatedSCRLowerBound, Case_Markers{Case_Index}, ...
        'LineStyle', 'none', ...
        'MarkerSize', 5.2, ...
        'MarkerFaceColor', Case_Colors(Case_Index,:), ...
        'MarkerEdgeColor', Case_Edge_Colors(Case_Index,:), ...
        'DisplayName', sprintf('Case %d', Case_Index));
    try
        Case_Handles(Case_Index).MarkerFaceAlpha = 0.72;
    catch
        % MarkerFaceAlpha is unavailable in some older MATLAB releases.
    end
end

Maximum_Plotted_Value = max([Fig6_Data.MinimumHourlySCR; ...
    Fig6_Data.AggregatedSCRLowerBound]);
if ~isfinite(Maximum_Plotted_Value) || Maximum_Plotted_Value <= 0
    error('Fig6Scatter:InvalidPlotRange', ...
        'SCR data do not define a positive finite plotting range.');
end
Padding = max(0.03*Maximum_Plotted_Value, 0.01);
Axis_Limits = [0 Maximum_Plotted_Value + Padding];
X_Axis_Limits = [2 3];
Y_Axis_Limits = [2 3];
plot(ax, Axis_Limits, Axis_Limits, '--', ...
    'Color', [0.25 0.25 0.25], 'LineWidth', 0.85, ...
    'HandleVisibility', 'off');

Visible_Diagonal_Limits = [max([X_Axis_Limits(1), Y_Axis_Limits(1), ...
    Axis_Limits(1)]), min([X_Axis_Limits(2), Y_Axis_Limits(2), ...
    Axis_Limits(2)])];
if Visible_Diagonal_Limits(2) > Visible_Diagonal_Limits(1)
    Diagonal_Label_Position = Visible_Diagonal_Limits(1) + ...
        [0.61 0.55]*diff(Visible_Diagonal_Limits);
    Y_Equals_X_Text = text(ax, Diagonal_Label_Position(1), ...
        Diagonal_Label_Position(2), '$y=x$', ...
        'Interpreter', 'latex', ...
        'FontName', 'Times New Roman', 'FontSize', 7.2, ...
        'Rotation', 45, ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'top');
end

hold(ax, 'off');

style_sci_axes(ax);
xlim(ax, X_Axis_Limits);
ylim(ax, Y_Axis_Limits);
drawnow;
Axes_Pixels = getpixelposition(ax, true);
Data_Ranges = [diff(xlim(ax)), diff(ylim(ax))];
if exist('Y_Equals_X_Text', 'var')
    Y_Equals_X_Angle = atan2d( ...
        Axes_Pixels(4)/Data_Ranges(2), Axes_Pixels(3)/Data_Ranges(1));
    Y_Equals_X_Text.Rotation = Y_Equals_X_Angle;
end
xlabel(ax, 'Minimum hourly SCR');
ylabel(ax, 'Aggregated SCR lower bound');

Summary_Text = {
    sprintf('%d samples satisfy y \\leq x', height(Fig6_Data)), ...
    sprintf('mean margin = %.3f', Case_Statistics.MeanMargin), ...
    sprintf('max margin = %.3f', Case_Statistics.MaxMargin), ...
    sprintf('mean relative margin = %.2f%%', ...
        100*Case_Statistics.MeanRelativeMargin)};
text(ax, 0.955, 0.045, Summary_Text, 'Units', 'normalized', ...
    'Interpreter', 'tex', 'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'bottom', 'FontName', 'Times New Roman', ...
    'FontSize', 6.8, 'Color', [0.18 0.18 0.18]);

Case_Legend = cellstr(compose('Case %d', 1:Case_Count));
legend(ax, Case_Handles, Case_Legend, ...
    'Location', 'northoutside', ...
    'Orientation', 'horizontal', ...
    'NumColumns', Case_Count, ...
    'FontName', 'Times New Roman', ...
    'FontSize', 7.0, ...
    'Box', 'off');

Output_Base = fullfile(Output_Directory, ...
    'Fig_6_scr_conservatism_scatter');
save_paper_figure(fig, Output_Base);
Data_Output_Path = [Output_Base '_data.csv'];
writetable(Fig6_Data, Data_Output_Path);

disp(Fig6_Data);
fprintf('Fig. 6 scatter plot saved to %s.[fig|pdf|png]\n', Output_Base);
fprintf('Fig. 6 scatter data saved to %s\n', Data_Output_Path);

function [Case_Results, Case_Files] = load_all_stage2_cases(Results_Directory)
%% Load the five named Stage 2 cases; Cases 4 and 5 share SCC/SCR switches.

if ~isfolder(Results_Directory)
    error('Fig6Scatter:MissingResultsDirectory', ...
        'Stage 2 results directory does not exist: %s', Results_Directory);
end
Case_Count = 5;
Case_Results = cell(1, Case_Count);
Case_Files = cell(1, Case_Count);
for Case_Index = 1:Case_Count
    File_Path = fullfile(Results_Directory, ...
        sprintf('Case_%d_Stage_2.mat', Case_Index));
    if ~isfile(File_Path)
        error('Fig6Scatter:MissingStage2Result', ...
            'Stage 2 result for Case %d does not exist: %s', ...
            Case_Index, File_Path);
    end
    Loaded = load(File_Path, 'Result');
    if ~isfield(Loaded, 'Result') || ~isstruct(Loaded.Result)
        error('Fig6Scatter:MissingResult', ...
            'MAT file does not contain a Result structure: %s', File_Path);
    end
    read_result_switches(Loaded.Result, File_Path);
    validate_solve_status(Loaded.Result, File_Path);
    Case_Results{Case_Index} = Loaded.Result;
    Case_Files{Case_Index} = File_Path;
end
end

function [Enable_SCC, Enable_SCR] = read_result_switches(Result, File_Path)
% Prefer SafetyNetwork metadata and cross-check CONF when both are present.
Sources = {};
if isfield(Result, 'SafetyNetwork') && isstruct(Result.SafetyNetwork) && ...
        all(isfield(Result.SafetyNetwork, {'Enable_SCC','Enable_SCR'}))
    Sources{end+1} = Result.SafetyNetwork;
end
if isfield(Result, 'CONF') && isstruct(Result.CONF) && ...
        all(isfield(Result.CONF, {'Enable_SCC','Enable_SCR'}))
    Sources{end+1} = Result.CONF;
end
if isempty(Sources)
    error('Fig6Scatter:MissingSwitchMetadata', ...
        'Result has no SCC/SCR switch metadata: %s', File_Path);
end
for Source_Index = 1:numel(Sources)
    Source = Sources{Source_Index};
    if ~(islogical(Source.Enable_SCC) || isnumeric(Source.Enable_SCC)) || ...
            ~isscalar(Source.Enable_SCC) || ...
            ~(islogical(Source.Enable_SCR) || isnumeric(Source.Enable_SCR)) || ...
            ~isscalar(Source.Enable_SCR) || ...
            ~isfinite(double(Source.Enable_SCC)) || ...
            ~isfinite(double(Source.Enable_SCR)) || ...
            ~ismember(double(Source.Enable_SCC), [0 1]) || ...
            ~ismember(double(Source.Enable_SCR), [0 1])
        error('Fig6Scatter:InvalidSwitchMetadata', ...
            'SCC/SCR switches must be scalar binary values: %s', File_Path);
    end
end
Enable_SCC = logical(Sources{1}.Enable_SCC);
Enable_SCR = logical(Sources{1}.Enable_SCR);
for Source_Index = 2:numel(Sources)
    if logical(Sources{Source_Index}.Enable_SCC) ~= Enable_SCC || ...
            logical(Sources{Source_Index}.Enable_SCR) ~= Enable_SCR
        error('Fig6Scatter:InconsistentSwitchMetadata', ...
            'SafetyNetwork and CONF switches disagree in %s.', File_Path);
    end
end
end

function validate_solve_status(Result, File_Path)
if ~isfield(Result, 'Diagnostics') || ...
        ~isfield(Result.Diagnostics, 'problem') || ...
        ~isscalar(Result.Diagnostics.problem) || ...
        Result.Diagnostics.problem ~= 0
    error('Fig6Scatter:UnsuccessfulSolve', ...
        'Stage 2 result was not solved successfully: %s', File_Path);
end
if isfield(Result.Diagnostics, 'has_incumbent') && ...
        (~isscalar(Result.Diagnostics.has_incumbent) || ...
        ~logical(Result.Diagnostics.has_incumbent))
    error('Fig6Scatter:MissingIncumbent', ...
        'Stage 2 result has no valid incumbent: %s', File_Path);
end
end

function [Case_Results, SCR_Nodes, Representative_Day_Count, Period_Count] = ...
        validate_all_cases(Case_Results, Case_Files)
%% Validate common dimensions, node mapping, and finite SCR data.

Reference_Result = Case_Results{1};
Reference_CONF = require_conf_fields(Reference_Result, Case_Files{1});
Representative_Day_Count = Reference_CONF.TypicalDayCount;
Period_Count = Reference_CONF.PeriodCount;
if ~isscalar(Representative_Day_Count) || Representative_Day_Count < 1 || ...
        Representative_Day_Count ~= round(Representative_Day_Count) || ...
        ~isscalar(Period_Count) || Period_Count < 1 || ...
        Period_Count ~= round(Period_Count)
    error('Fig6Scatter:InvalidTimeDimensions', ...
        'Invalid typical-day or period count in %s.', Case_Files{1});
end
SCR_Nodes = validate_case_result(Reference_Result, Case_Files{1}, ...
    Representative_Day_Count, Period_Count, []);

if numel(SCR_Nodes) ~= 1
    error('Fig6Scatter:ExpectedSingleGFL', ...
        ['The SCR scatter script expects the current single-GFL-WG ', ...
        'system, but %d time-resolved SCR nodes were found.'], ...
        numel(SCR_Nodes));
end

for Case_Index = 2:numel(Case_Results)
    CONF = require_conf_fields(Case_Results{Case_Index}, Case_Files{Case_Index});
    if CONF.TypicalDayCount ~= Representative_Day_Count || ...
            CONF.PeriodCount ~= Period_Count
        error('Fig6Scatter:InconsistentTimeDimensions', ...
            'Case %d has time dimensions inconsistent with Case 1.', Case_Index);
    end
    Case_Nodes = validate_case_result(Case_Results{Case_Index}, ...
        Case_Files{Case_Index}, Representative_Day_Count, Period_Count, ...
        SCR_Nodes);
    if ~isequal(Case_Nodes, SCR_Nodes)
        error('Fig6Scatter:InconsistentNodeMapping', ...
            'Case %d has an SCR node mapping inconsistent with Case 1.', ...
            Case_Index);
    end
end
end

function CONF = require_conf_fields(Result, File_Path)
if ~isfield(Result, 'CONF') || ~isstruct(Result.CONF)
    error('Fig6Scatter:MissingCONF', ...
        'Result has no CONF structure: %s', File_Path);
end
CONF = Result.CONF;
Required_CONF = {'Bn','Gn','TypicalDayCount','PeriodCount'};
Missing_CONF = Required_CONF(~isfield(CONF, Required_CONF));
if ~isempty(Missing_CONF)
    error('Fig6Scatter:MissingConfigurationFields', ...
        'CONF in %s is missing: %s.', File_Path, ...
        strjoin(Missing_CONF, ', '));
end
end

function SCR_Nodes = validate_case_result(Result, File_Path, ...
        Representative_Day_Count, Period_Count, Expected_Nodes)
Required_Fields = {'SCR_TimeResolved','SCR','CONF','SafetyNetwork', ...
    'SecurityValidation'};
Missing = Required_Fields(~isfield(Result, Required_Fields));
if ~isempty(Missing)
    error('Fig6Scatter:MissingFields', 'Result in %s is missing: %s.', ...
        File_Path, strjoin(Missing, ', '));
end

S = Result.SafetyNetwork;
if ~isfield(S, 'SCRTimeResolvedOriginalNodes') || ...
        ~isfield(S, 'SCRColumnOriginalNodes')
    error('Fig6Scatter:MissingNodeMapping', ...
        'Result has no SCR node mappings: %s', File_Path);
end
SCR_Nodes = S.SCRTimeResolvedOriginalNodes(:);
SCR_Column_Nodes = S.SCRColumnOriginalNodes(:);
CONF = Result.CONF;
if isempty(SCR_Nodes) || any(~isfinite(SCR_Nodes)) || ...
        any(SCR_Nodes ~= round(SCR_Nodes)) || ...
        any(SCR_Nodes < 1 | SCR_Nodes > CONF.Bn) || ...
        numel(unique(SCR_Nodes)) ~= numel(SCR_Nodes) || ...
        ~isequal(SCR_Column_Nodes, SCR_Nodes)
    error('Fig6Scatter:InvalidNodeMapping', ...
        'SCR-node mappings are invalid or inconsistent: %s', File_Path);
end
if ~isempty(Expected_Nodes) && ~isequal(SCR_Nodes, Expected_Nodes)
    error('Fig6Scatter:InconsistentNodeMapping', ...
        'SCR-node mapping is inconsistent: %s', File_Path);
end

Expected_SCR_Size = [Period_Count Representative_Day_Count numel(SCR_Nodes)];
if ~size_matches(Result.SCR_TimeResolved, Expected_SCR_Size) || ...
        ~size_matches(Result.SCR, [CONF.Bn Representative_Day_Count])
    error('Fig6Scatter:DimensionMismatch', ...
        'SCR dimensions are invalid in %s.', File_Path);
end
if any(~isfinite(Result.SCR_TimeResolved(:))) || ...
        any(~isfinite(Result.SCR(SCR_Nodes,:)), 'all')
    error('Fig6Scatter:NonfiniteData', ...
        'Result contains nonfinite SCR data: %s', File_Path);
end

if ~isfield(Result.SecurityValidation, 'SCR') || ...
        ~isstruct(Result.SecurityValidation.SCR) || ...
        ~isfield(Result.SecurityValidation.SCR, 'Tolerance') || ...
        ~isscalar(Result.SecurityValidation.SCR.Tolerance) || ...
        ~isfinite(Result.SecurityValidation.SCR.Tolerance) || ...
        Result.SecurityValidation.SCR.Tolerance < 0
    error('Fig6Scatter:MissingTolerance', ...
        'SCR validation tolerance is missing or invalid in %s.', File_Path);
end
end

function [Fig6_Data, Case_Statistics] = build_scr_scatter_data( ...
        Case_Results, Case_Files, SCR_Nodes, Representative_Day_Count, ...
        Period_Count)
%% Construct one paired sample for each case and representative day.

Case_Count = numel(Case_Results);
Sample_Count = Case_Count*Representative_Day_Count;
Case_Index_Column = zeros(Sample_Count, 1);
Day_Column = zeros(Sample_Count, 1);
Original_Node_Column = zeros(Sample_Count, 1);
Minimum_Period_Column = zeros(Sample_Count, 1);
Minimum_Hourly_Column = zeros(Sample_Count, 1);
Aggregated_Lower_Column = zeros(Sample_Count, 1);
Delta_Column = zeros(Sample_Count, 1);
Relative_Column = nan(Sample_Count, 1);
Write_Index = 0;

for Case_Index = 1:Case_Count
    Result = Case_Results{Case_Index};
    Tolerance = Result.SecurityValidation.SCR.Tolerance;
    Original_Node = SCR_Nodes(1);
    Hourly_SCR = reshape(Result.SCR_TimeResolved, ...
        Period_Count, Representative_Day_Count, 1);
    for Day_Index = 1:Representative_Day_Count
        [Minimum_Hourly_SCR, Minimum_Period] = ...
            min(Hourly_SCR(:, Day_Index, 1), [], 1, 'omitnan');
        Aggregated_SCR = Result.SCR(Original_Node, Day_Index);
        Delta = Minimum_Hourly_SCR - Aggregated_SCR;
        if ~isfinite(Minimum_Hourly_SCR) || ~isfinite(Aggregated_SCR) || ...
                ~isfinite(Delta) || Minimum_Hourly_SCR <= 0
            error('Fig6Scatter:NonfiniteSample', ...
                ['Case %d, representative day %d, original node %d ', ...
                'contains an invalid SCR sample in %s.'], Case_Index, ...
                Day_Index, Original_Node, Case_Files{Case_Index});
        end
        if Delta < -Tolerance
            error('Fig6Scatter:ConservatismViolation', ...
                ['Case %d, representative day %d, original node %d ', ...
                'violates SCR conservatism: aggregate=%.12g, ', ...
                'hourly minimum=%.12g, delta=%.12g, tolerance=%.12g ', ...
                '(%s).'], Case_Index, Day_Index, Original_Node, ...
                Aggregated_SCR, Minimum_Hourly_SCR, Delta, Tolerance, ...
                Case_Files{Case_Index});
        end
        Write_Index = Write_Index + 1;
        Case_Index_Column(Write_Index) = Case_Index;
        Day_Column(Write_Index) = Day_Index;
        Original_Node_Column(Write_Index) = Original_Node;
        Minimum_Period_Column(Write_Index) = Minimum_Period;
        Minimum_Hourly_Column(Write_Index) = Minimum_Hourly_SCR;
        Aggregated_Lower_Column(Write_Index) = Aggregated_SCR;
        Delta_Column(Write_Index) = Delta;
        Relative_Column(Write_Index) = Delta/Minimum_Hourly_SCR;
    end
end

Fig6_Data = table(Case_Index_Column, Day_Column, Original_Node_Column, ...
    Minimum_Period_Column, Minimum_Hourly_Column, Aggregated_Lower_Column, ...
    Delta_Column, Relative_Column, 'VariableNames', ...
    {'CaseIndex','RepresentativeDay','OriginalNode', ...
    'MinimumHourlyPeriod','MinimumHourlySCR', ...
    'AggregatedSCRLowerBound','DeltaSCR','RelativeMargin'});

Case_Statistics = struct();
Case_Statistics.Sample_Count = height(Fig6_Data);
Case_Statistics.MeanMargin = mean(Fig6_Data.DeltaSCR, 'omitnan');
Case_Statistics.MaxMargin = max(Fig6_Data.DeltaSCR, [], 'omitnan');
Case_Statistics.MeanRelativeMargin = ...
    mean(Fig6_Data.RelativeMargin, 'omitnan');
Case_Statistics.Case_Counts = zeros(Case_Count,1);
Case_Statistics.Case_MeanMargin = zeros(Case_Count,1);
Case_Statistics.Case_MaxMargin = zeros(Case_Count,1);
for Case_Index = 1:Case_Count
    Is_Case = Fig6_Data.CaseIndex == Case_Index;
    Case_Statistics.Case_Counts(Case_Index) = nnz(Is_Case);
    Case_Statistics.Case_MeanMargin(Case_Index) = ...
        mean(Fig6_Data.DeltaSCR(Is_Case), 'omitnan');
    Case_Statistics.Case_MaxMargin(Case_Index) = ...
        max(Fig6_Data.DeltaSCR(Is_Case), [], 'omitnan');
end
if Write_Index ~= Sample_Count
    error('Fig6Scatter:InternalSampleCountError', ...
        'Expected %d samples but constructed %d.', Sample_Count, Write_Index);
end
end

function print_case_statistics(Fig6_Data, Case_Statistics)
fprintf('Fig. 6 SCR conservatism statistics:\n');
fprintf('  Total samples: %d\n', Case_Statistics.Sample_Count);
for Case_Index = 1:numel(Case_Statistics.Case_Counts)
    fprintf(['  Case %d: %d samples, mean margin %.6g, ', ...
        'max margin %.6g\n'], Case_Index, ...
        Case_Statistics.Case_Counts(Case_Index), ...
        Case_Statistics.Case_MeanMargin(Case_Index), ...
        Case_Statistics.Case_MaxMargin(Case_Index));
end
fprintf('  Mean absolute margin: %.6g\n', Case_Statistics.MeanMargin);
fprintf('  Maximum absolute margin: %.6g\n', Case_Statistics.MaxMargin);
fprintf('  Mean relative margin: %.6g%%\n', ...
    100*Case_Statistics.MeanRelativeMargin);
if height(Fig6_Data) == 0
    error('Fig6Scatter:EmptyData', 'No scatter samples were constructed.');
end
end

function Matches = size_matches(Value, Expected)
Actual = size(Value);
Actual(end+1:numel(Expected)) = 1;
Matches = isequal(Actual(1:numel(Expected)), Expected) && ...
    all(Actual(numel(Expected)+1:end) == 1);
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
    replace_file(Temp_Paths{File_Index}, Target_Paths{File_Index});
end
set(fig, 'Visible', 'off');
close(fig);
end

function replace_file(Source_Path, Target_Path)
[Success, Message] = movefile(Source_Path, Target_Path, 'f');
if ~Success
    error('Fig6Scatter:ExportFailure', ...
        'Cannot replace figure file %s: %s', Target_Path, Message);
end
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
error('Fig6Scatter:ProjectRootNotFound', ...
    'Cannot find the project root from %s.', Start_Directory);
end
