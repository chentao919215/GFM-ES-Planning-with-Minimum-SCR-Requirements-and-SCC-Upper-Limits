%% Fig. 3: security metrics under different security constraints.
% The five Stage 2 cases are loaded by their explicit case numbers because
% Cases 4 and 5 share SCC/SCR switches but use different wind scenarios.
% Simulation result files are loaded read-only and are never modified here.

Script_Directory = fileparts(mfilename('fullpath'));
Project_Root = find_project_root_local(Script_Directory);
Results_Directory = fullfile(Project_Root, 'results_useful', ...
    'from_laptop', 'IV-B');
Output_Directory = fullfile(Project_Root, 'figs', 'for_paper');
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
if ~isfolder(Output_Directory)
    mkdir(Output_Directory);
end

[Case_Results, Case_Files] = load_stage2_cases(Results_Directory);
validate_case_consistency(Case_Results, Case_Files);

Case_Count = 5;
Maximum_SCC_kA = zeros(1,Case_Count);
Minimum_SCR = zeros(1,Case_Count);
for Case_Index = 1:Case_Count
    Result = Case_Results{Case_Index};
    Maximum_SCC_kA(Case_Index) = max( ...
        Result.SCC_TimeResolved, [], 'all', 'omitnan');
    Minimum_SCR(Case_Index) = min( ...
        Result.SCR_TimeResolved, [], 'all', 'omitnan');
    if ~isfinite(Maximum_SCC_kA(Case_Index)) || ...
            ~isfinite(Minimum_SCR(Case_Index))
        error('Fig3Metrics:InvalidSecurityMetric', ...
            ['Case %d contains no finite time-resolved SCC or SCR value ', ...
            'in %s.'], Case_Index, Case_Files{Case_Index});
    end
end

[SCC_Limit_kA, SCR_Limit] = read_common_security_limits( ...
    Case_Results, Case_Files);

Figure_Width = 3.50;
Figure_Height = 2.40;
fig = new_paper_figure(Figure_Width, Figure_Height);
layout = tiledlayout(fig, 1, 1, 'Padding', 'compact', ...
    'TileSpacing', 'compact');
ax = nexttile(layout);
style_sci_axes(ax);
hold(ax, 'on');

Case_Positions = 1:Case_Count;
Bar_Offset = 0.17;
Bar_Width = 0.28;
SCC_Color = [89 142 187]/255;  % #598EBB
SCR_Color = [108 170 196]/255; % #6CAAC4
SCC_Limit_Legend = ['$I^{\mathrm{limit}}=' ...
    sprintf('%.2f', SCC_Limit_kA) '\,\mathrm{kA}$'];
SCR_Limit_Legend = ['$\mathrm{CSCR}=' ...
    sprintf('%.2f', SCR_Limit) '$'];

yyaxis(ax, 'left');
SCC_Bars = bar(ax, Case_Positions-Bar_Offset, Maximum_SCC_kA, ...
    Bar_Width, 'FaceColor', SCC_Color, 'EdgeColor', 'k', ...
    'LineWidth', 0.7, 'DisplayName', 'Maximum SCC');
SCC_Y_Label = ylabel(ax, '$I_{\max}^{\mathrm{SC}}$ (kA)', ...
    'Interpreter', 'latex', 'Color', SCC_Color);
SCC_Y_Max = max([Maximum_SCC_kA SCC_Limit_kA]);
ylim(ax, [0 1.25*SCC_Y_Max]);
SCC_Limit_Line = yline(ax, SCC_Limit_kA, '--', ...
    'Color', SCC_Color, 'LineWidth', 1.2, ...
    'DisplayName', SCC_Limit_Legend);
for Case_Index = 1:Case_Count
    text(ax, Case_Positions(Case_Index)-Bar_Offset, ...
        Maximum_SCC_kA(Case_Index)+0.025*SCC_Y_Max, ...
        sprintf('%.2f', Maximum_SCC_kA(Case_Index)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'FontName', 'Times New Roman', 'FontSize', 7.5, ...
        'Color', 0.65*SCC_Color);
end

yyaxis(ax, 'right');
SCR_Bars = bar(ax, Case_Positions+Bar_Offset, Minimum_SCR, ...
    Bar_Width, 'FaceColor', SCR_Color, 'EdgeColor', 'k', ...
    'LineWidth', 0.7, 'DisplayName', 'Minimum SCR');
SCR_Y_Label = ylabel(ax, '$\mathrm{SCR}_{\min}$', ...
    'Interpreter', 'latex', 'Color', SCR_Color);
SCR_Y_Max = max([Minimum_SCR SCR_Limit]);
ylim(ax, [0 1.40*SCR_Y_Max]);
SCR_Limit_Line = yline(ax, SCR_Limit, '--', ...
    'Color', SCR_Color, 'LineWidth', 1.2, ...
    'DisplayName', SCR_Limit_Legend);
for Case_Index = 1:Case_Count
    text(ax, Case_Positions(Case_Index)+Bar_Offset, ...
        Minimum_SCR(Case_Index)+0.025*SCR_Y_Max, ...
        sprintf('%.2f', Minimum_SCR(Case_Index)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'FontName', 'Times New Roman', 'FontSize', 7.5, ...
        'Color', 0.65*SCR_Color);
end

hold(ax, 'off');
ax.YAxis(1).Color = SCC_Color;
ax.YAxis(2).Color = SCR_Color;
SCC_Y_Label.Color = SCC_Color;
SCR_Y_Label.Color = SCR_Color;
xlim(ax, [0.50 Case_Count+0.50]);
xticks(ax, Case_Positions);
xticklabels(ax, compose('Case %d', Case_Positions));
legend(ax, [SCC_Bars SCC_Limit_Line SCR_Bars SCR_Limit_Line], ...
    {'Maximum SCC',SCC_Limit_Legend, ...
    'Minimum SCR',SCR_Limit_Legend}, ...
    'Location', 'northoutside', 'Orientation', 'horizontal', ...
    'NumColumns', 2, 'FontName', 'Times New Roman', 'FontSize', 7.5, ...
    'Interpreter', 'latex', 'Box', 'off');

Output_Base = fullfile(Output_Directory, 'Fig_3_security_metrics');
save_paper_figure(fig, Output_Base);

Fig3_Data = table((1:Case_Count).', Maximum_SCC_kA(:), Minimum_SCR(:), ...
    string(Case_Files(:)), 'VariableNames', ...
    {'Case','MaximumTimeResolvedSCC_kA','MinimumTimeResolvedSCR', ...
    'Stage2ResultFile'});
disp(Fig3_Data);
fprintf('Fig. 3 saved to %s.[fig|pdf|png]\n', Output_Base);

function [Case_Results, Case_Files] = load_stage2_cases(Results_Directory)
%% Load the five named Stage 2 cases; Cases 4 and 5 may share switch values.

if ~isfolder(Results_Directory)
    error('Fig3Metrics:MissingResultsDirectory', ...
        'Stage 2 results directory does not exist: %s', Results_Directory);
end
Case_Count = 5;
Case_Results = cell(1,Case_Count);
Case_Files = cell(1,Case_Count);
for Case_Index = 1:Case_Count
    File_Path = fullfile(Results_Directory, ...
        sprintf('Case_%d_Stage_2.mat',Case_Index));
    if ~isfile(File_Path)
        error('Fig3Metrics:MissingStage2Result', ...
            'Stage 2 result for Case %d does not exist: %s', ...
            Case_Index, File_Path);
    end
    Loaded = load(File_Path, 'Result');
    if ~isfield(Loaded, 'Result') || ~isstruct(Loaded.Result)
        error('Fig3Metrics:MissingResult', ...
            'MAT file does not contain a Result structure: %s', File_Path);
    end
    Result = Loaded.Result;
    read_result_switches(Result, File_Path);
    validate_result(Result, File_Path);
    Case_Results{Case_Index} = Result;
    Case_Files{Case_Index} = File_Path;
end
end

function [Enable_SCC, Enable_SCR] = read_result_switches(Result, File_Path)
%% Read both metadata copies and reject inconsistent or nonlogical flags.

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
    error('Fig3Metrics:MissingSwitchMetadata', ...
        'Result has no SCC/SCR switch metadata: %s', File_Path);
end
for Source_Index = 1:numel(Sources)
    Source = Sources{Source_Index};
    if ~islogical(Source.Enable_SCC) || ~isscalar(Source.Enable_SCC) || ...
            ~islogical(Source.Enable_SCR) || ~isscalar(Source.Enable_SCR)
        error('Fig3Metrics:InvalidSwitchMetadata', ...
            'SCC/SCR switches must be scalar logical values: %s', File_Path);
    end
end
Enable_SCC = Sources{1}.Enable_SCC;
Enable_SCR = Sources{1}.Enable_SCR;
for Source_Index = 2:numel(Sources)
    if Sources{Source_Index}.Enable_SCC ~= Enable_SCC || ...
            Sources{Source_Index}.Enable_SCR ~= Enable_SCR
        error('Fig3Metrics:InconsistentSwitchMetadata', ...
            'SafetyNetwork and CONF switches disagree in %s.', File_Path);
    end
end
end

function validate_result(Result, File_Path)
%% Check solve status and the fields needed by both paper figures.

Required_Fields = {'SCC_TimeResolved','SCR_TimeResolved','SCC_1', ...
    'u_G','u_G_SCC','CONF','SafetyNetwork','SecurityValidation', ...
    'Diagnostics'};
Missing = Required_Fields(~isfield(Result, Required_Fields));
if ~isempty(Missing)
    error('Fig3Metrics:MissingFields', 'Result in %s is missing: %s.', ...
        File_Path, strjoin(Missing, ', '));
end
if ~isfield(Result.Diagnostics, 'problem') || ...
        ~isscalar(Result.Diagnostics.problem) || Result.Diagnostics.problem ~= 0
    error('Fig3Metrics:UnsuccessfulSolve', ...
        'Stage 2 result was not solved successfully: %s', File_Path);
end
if isfield(Result.Diagnostics, 'has_incumbent') && ...
        (~isscalar(Result.Diagnostics.has_incumbent) || ...
        ~logical(Result.Diagnostics.has_incumbent))
    error('Fig3Metrics:MissingIncumbent', ...
        'Stage 2 result has no valid incumbent: %s', File_Path);
end

C = Result.CONF;
Required_CONF = {'PeriodCount','TypicalDayCount','Bn'};
Missing_CONF = Required_CONF(~isfield(C, Required_CONF));
if ~isempty(Missing_CONF)
    error('Fig3Metrics:MissingConfigurationFields', ...
        'CONF in %s is missing: %s.', File_Path, ...
        strjoin(Missing_CONF, ', '));
end
S = Result.SafetyNetwork;
Required_Network = {'SCCTimeResolvedOriginalNodes', ...
    'SCRTimeResolvedOriginalNodes'};
Missing_Network = Required_Network(~isfield(S, Required_Network));
if ~isempty(Missing_Network)
    error('Fig3Metrics:MissingNodeMapping', ...
        'SafetyNetwork in %s is missing: %s.', File_Path, ...
        strjoin(Missing_Network, ', '));
end
SCC_Nodes = S.SCCTimeResolvedOriginalNodes(:);
SCR_Nodes = S.SCRTimeResolvedOriginalNodes(:);
if isempty(SCC_Nodes) || isempty(SCR_Nodes) || ...
        any(~isfinite(SCC_Nodes)) || any(~isfinite(SCR_Nodes))
    error('Fig3Metrics:InvalidNodeMapping', ...
        'Security-node mapping is empty or invalid in %s.', File_Path);
end
if ~size_matches(Result.SCC_TimeResolved, ...
        [C.PeriodCount C.TypicalDayCount numel(SCC_Nodes)]) || ...
        ~size_matches(Result.SCR_TimeResolved, ...
        [C.PeriodCount C.TypicalDayCount numel(SCR_Nodes)]) || ...
        ~size_matches(Result.SCC_1, [C.Bn C.TypicalDayCount])
    error('Fig3Metrics:DimensionMismatch', ...
        'Security-result dimensions do not match saved metadata in %s.', ...
        File_Path);
end
if any(~isfinite(Result.SCC_TimeResolved), 'all') || ...
        any(~isfinite(Result.SCR_TimeResolved), 'all') || ...
        any(~isfinite(Result.SCC_1(SCC_Nodes,:)), 'all')
    error('Fig3Metrics:NonfiniteSecurityData', ...
        'Required security results contain nonfinite values in %s.', File_Path);
end
end

function validate_case_consistency(Case_Results, Case_Files)
%% Require common security mappings and array dimensions across all cases.

Reference = Case_Results{1};
Reference_SCC_Nodes = ...
    Reference.SafetyNetwork.SCCTimeResolvedOriginalNodes(:);
Reference_SCR_Nodes = ...
    Reference.SafetyNetwork.SCRTimeResolvedOriginalNodes(:);
for Case_Index = 2:numel(Case_Results)
    Result = Case_Results{Case_Index};
    Same_Mapping = isequal(Reference_SCC_Nodes, ...
        Result.SafetyNetwork.SCCTimeResolvedOriginalNodes(:)) && ...
        isequal(Reference_SCR_Nodes, ...
        Result.SafetyNetwork.SCRTimeResolvedOriginalNodes(:));
    Same_Dimensions = isequal(size(Reference.SCC_TimeResolved), ...
        size(Result.SCC_TimeResolved)) && ...
        isequal(size(Reference.SCR_TimeResolved), ...
        size(Result.SCR_TimeResolved)) && ...
        Reference.CONF.PeriodCount == Result.CONF.PeriodCount && ...
        Reference.CONF.TypicalDayCount == Result.CONF.TypicalDayCount;
    if ~Same_Mapping || ~Same_Dimensions
    error('Fig3Metrics:InconsistentCases', ...
            ['Security-node mapping or data dimensions differ between ', ...
            'Case 1 (%s) and Case %d (%s).'], ...
            Case_Files{1}, Case_Index, Case_Files{Case_Index});
    end
end
end

function [SCC_Limit_kA, SCR_Limit] = read_common_security_limits( ...
    Case_Results, Case_Files)
%% Read thresholds from Result.CONF and require one common scalar per metric.

Case_Count = numel(Case_Results);
SCC_Limits = zeros(1,Case_Count);
SCR_Limits = zeros(1,Case_Count);
for Case_Index = 1:Case_Count
    Result = Case_Results{Case_Index};
    C = Result.CONF;
    SCC_Nodes = Result.SafetyNetwork.SCCTimeResolvedOriginalNodes(:);
    if isfield(C, 'I_limit_kA_Node')
        Node_Limits = C.I_limit_kA_Node(SCC_Nodes);
    elseif isfield(C, 'I_limit_kA')
        if isscalar(C.I_limit_kA)
            Node_Limits = C.I_limit_kA;
        else
            Node_Limits = C.I_limit_kA(SCC_Nodes);
        end
    else
        error('Fig3Metrics:MissingSCCLimit', ...
            'SCC limit is missing from %s.', Case_Files{Case_Index});
    end
    Node_Limits = Node_Limits(:);
    if any(~isfinite(Node_Limits)) || ...
            max(abs(Node_Limits-Node_Limits(1))) > 1e-10
        error('Fig3Metrics:NonuniformSCCLimit', ...
            'Fig. 3 requires one common SCC limit in %s.', ...
            Case_Files{Case_Index});
    end
    if ~isfield(C, 'SCR_min') || ~isscalar(C.SCR_min) || ...
            ~isfinite(C.SCR_min)
        error('Fig3Metrics:MissingSCRLimit', ...
            'SCR_min is missing or invalid in %s.', Case_Files{Case_Index});
    end
    SCC_Limits(Case_Index) = Node_Limits(1);
    SCR_Limits(Case_Index) = C.SCR_min;
end
if max(abs(SCC_Limits-SCC_Limits(1))) > 1e-10 || ...
        max(abs(SCR_Limits-SCR_Limits(1))) > 1e-10
    error('Fig3Metrics:InconsistentLimits', ...
        'Security thresholds are not identical across the four cases.');
end
SCC_Limit_kA = SCC_Limits(1);
SCR_Limit = SCR_Limits(1);
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
%% Reuse the project's atomic FIG/PNG export and add a vector PDF export.

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
    error('Fig3Metrics:ExportFailure', ...
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
error('Fig3Metrics:ProjectRootNotFound', ...
    'Cannot find the project root from %s.', Start_Directory);
end
