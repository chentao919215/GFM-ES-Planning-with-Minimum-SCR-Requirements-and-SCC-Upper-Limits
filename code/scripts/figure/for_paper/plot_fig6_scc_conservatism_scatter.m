function Report = plot_fig6_scc_conservatism_scatter(Options)
%% Fig. 6：五组第二阶段结果的SCC聚合界保守性与紧致度。
% 每个点对应一个算例、典型日和SCC安全节点。
% 横轴为最终调度的逐时SCC最大值，纵轴为对应聚合上界；y=x为保守性参考线。
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

[Case_Results, Case_Files] = load_all_stage2_cases(Results_Directory);
[Case_Results, SCC_Nodes, Representative_Day_Count, Period_Count] = ...
    validate_all_cases(Case_Results, Case_Files);
Case_Count = numel(Case_Results);

[Fig6_Data, Case_Statistics] = build_scc_scatter_data( ...
    Case_Results, Case_Files, SCC_Nodes, Representative_Day_Count, ...
    Period_Count);
print_case_statistics(Fig6_Data, Case_Statistics);

Figure_Width = 3.50;
Figure_Height = 2.40;

%% 2. 绘制论文图件
fig = new_figure(2.54*[Figure_Width Figure_Height], Style);
layout = tiledlayout(fig, 1, 1, 'Padding', 'compact', ...
    'TileSpacing', 'compact');
ax = nexttile(layout);

hold(ax, 'on');

Case_Markers = {'o', 's', '^', 'd', 'v'};
% 沿用Manuscript五组算例的配色顺序。
Case_Colors = Style.Colors.Cases;
Case_Edge_Colors = 0.68*Case_Colors;
Case_Handles = gobjects(Case_Count, 1);
for Case_Index = 1:Case_Count
    Case_Data = Fig6_Data(Fig6_Data.CaseIndex == Case_Index, :);
    Case_Handles(Case_Index) = plot(ax, Case_Data.ActualMaximumSCC_kA, ...
        Case_Data.AggregatedSCCUpperBound_kA, Case_Markers{Case_Index}, ...
        'LineStyle', 'none', ...
        'MarkerSize', 5.2, ...
        'MarkerFaceColor', Case_Colors(Case_Index, :), ...
        'MarkerEdgeColor', Case_Edge_Colors(Case_Index, :), ...
        'DisplayName', sprintf('Case %d', Case_Index));

end

Maximum_Plotted_Value = max([Fig6_Data.ActualMaximumSCC_kA; ...
    Fig6_Data.AggregatedSCCUpperBound_kA]);
if ~isfinite(Maximum_Plotted_Value) || Maximum_Plotted_Value <= 0
    error('Fig6Scatter:InvalidPlotRange', ...
        'SCC data do not define a positive finite plotting range.');
end
Padding = max(0.03*Maximum_Plotted_Value, 0.01);
Axis_Limits = [0 Maximum_Plotted_Value + Padding];
plot(ax, Axis_Limits, Axis_Limits, '--', ...
    'Color', [0.25 0.25 0.25], 'LineWidth', 0.85, ...
    'HandleVisibility', 'off');

Y_Equals_X_Text = text(ax, 0.61*Axis_Limits(2), 0.55*Axis_Limits(2), '$y=x$', ...
    'Interpreter', 'latex', ...
    'FontName', 'Times New Roman', 'FontSize', 7.2, ...
    'Rotation', 45, ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'top');

hold(ax, 'off');

style_sci_axes(ax);
xlim(ax, Axis_Limits);
ylim(ax, Axis_Limits);
drawnow;
Axes_Pixels = getpixelposition(ax, true);
Data_Ranges = [diff(xlim(ax)), diff(ylim(ax))];
Y_Equals_X_Angle = atan2d( ...
    Axes_Pixels(4)/Data_Ranges(2), Axes_Pixels(3)/Data_Ranges(1));
Y_Equals_X_Text.Rotation = Y_Equals_X_Angle;
xlabel(ax, 'Maximum hourly SCC (kA)');
ylabel(ax, 'Aggregated SCC upper bound (kA)');

Summary_Text = {
    sprintf('%d samples satisfy y \\geq x', height(Fig6_Data)), ...
    sprintf('mean margin = %.3f kA', Case_Statistics.MeanMargin_kA), ...
    sprintf('max margin = %.3f kA', Case_Statistics.MaxMargin_kA), ...
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
    'Fig_6_scc_conservatism_scatter');
save_figure_file(fig, Output_Base);

disp(Fig6_Data);
fprintf('Fig. 6 scatter plot saved to %s.fig\n', Output_Base);

%% 3. 返回绘图数据与文件位置
Report = struct('Data', Fig6_Data, 'Figure_File', [Output_Base '.fig']);
end

function [Case_Results, Case_Files] = load_all_stage2_cases(Results_Directory)
%% 按算例编号读取五组第二阶段结果，区分Case 4和5的相同安全开关。

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
%% 从结果配置快照读取SCC、SCR约束启用状态。
Enable_SCC = Result.CONF.Enable_SCC;
Enable_SCR = Result.CONF.Enable_SCR;
if ~islogical(Enable_SCC) || ~isscalar(Enable_SCC) || ...
        ~islogical(Enable_SCR) || ~isscalar(Enable_SCR)
    error('Fig6Scatter:InvalidSwitchMetadata', ...
        'SCC/SCR switches must be scalar logical values: %s', File_Path);
end
end

function validate_solve_status(Result, File_Path)
%% 核验结果含可用整数解，且停止状态符合绘图归档要求。
if ~isfield(Result, 'Diagnostics') || ...
        ~isfield(Result.Diagnostics, 'problem') || ...
        ~isscalar(Result.Diagnostics.problem) || ...
        Result.Diagnostics.problem ~= 0
    error('Fig6Scatter:UnsuccessfulSolve', ...
        'Stage 2 result was not solved successfully: %s', File_Path);
end
if ~isscalar(Result.Diagnostics.has_incumbent) || ...
        ~logical(Result.Diagnostics.has_incumbent)
    error('Fig6Scatter:MissingIncumbent', ...
        'Stage 2 result has no valid incumbent: %s', File_Path);
end
end

function [Case_Results, SCC_Nodes, Representative_Day_Count, Period_Count] = ...
    validate_all_cases(Case_Results, Case_Files)
%% 核验各算例的维度、节点映射及有限数值。

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
SCC_Nodes = validate_case_result(Reference_Result, Case_Files{1}, ...
    Representative_Day_Count, Period_Count, []);

for Case_Index = 2:numel(Case_Results)
    CONF = require_conf_fields(Case_Results{Case_Index}, Case_Files{Case_Index});
    if CONF.TypicalDayCount ~= Representative_Day_Count || ...
            CONF.PeriodCount ~= Period_Count
        error('Fig6Scatter:InconsistentTimeDimensions', ...
            'Case %d has time dimensions inconsistent with Case 1.', Case_Index);
    end
    Case_Nodes = validate_case_result(Case_Results{Case_Index}, ...
        Case_Files{Case_Index}, Representative_Day_Count, Period_Count, ...
        SCC_Nodes);
    if ~isequal(Case_Nodes, SCC_Nodes)
        error('Fig6Scatter:InconsistentNodeMapping', ...
            'Case %d has an SCC node mapping inconsistent with Case 1.', ...
            Case_Index);
    end
end
end

function CONF = require_conf_fields(Result, File_Path)
%% 核验结果配置快照包含当前图件所需字段。
if ~isfield(Result, 'CONF') || ~isstruct(Result.CONF)
    error('Fig6Scatter:MissingCONF', ...
        'Result has no CONF structure: %s', File_Path);
end
CONF = Result.CONF;
Required_CONF = {'Bn', 'Gn', 'TypicalDayCount', 'PeriodCount'};
Missing_CONF = Required_CONF(~isfield(CONF, Required_CONF));
if ~isempty(Missing_CONF)
    error('Fig6Scatter:MissingConfigurationFields', ...
        'CONF in %s is missing: %s.', File_Path, ...
        strjoin(Missing_CONF, ', '));
end
end

function SCC_Nodes = validate_case_result(Result, File_Path, ...
    Representative_Day_Count, Period_Count, Expected_Nodes)
%% 核验单个算例的节点映射、指标规模及有限数据。
Required_Fields = {'SCC_TimeResolved', 'SCC_Aggregated', 'SCR_TimeResolved', 'SCR_Aggregated', ...
    'u_G', 'u_G_SCC', 'CONF', 'SecurityValidation'};
Missing = Required_Fields(~isfield(Result, Required_Fields));
if ~isempty(Missing)
    error('Fig6Scatter:MissingFields', 'Result in %s is missing: %s.', ...
        File_Path, strjoin(Missing, ', '));
end

S = Result.CONF;
if ~isfield(S, 'SCC_Constraint_Original_Nodes')
    error('Fig6Scatter:MissingNodeMapping', ...
        'Result has no SCC time-resolved node mapping: %s', File_Path);
end
SCC_Nodes = S.SCC_Constraint_Original_Nodes(:);
if ~isfield(S, 'Safety_GFL_Original_Nodes')
    error('Fig6Scatter:MissingSCRNodeMapping', ...
        'Result has no SCR time-resolved node mapping: %s', File_Path);
end
SCR_Nodes = S.Safety_GFL_Original_Nodes(:);
CONF = Result.CONF;
if isempty(SCC_Nodes) || any(~isfinite(SCC_Nodes)) || ...
        any(SCC_Nodes ~= round(SCC_Nodes)) || ...
        any(SCC_Nodes < 1 | SCC_Nodes > CONF.Bn) || ...
        numel(unique(SCC_Nodes)) ~= numel(SCC_Nodes)
    error('Fig6Scatter:InvalidNodeMapping', ...
        'SCC-node mapping is invalid: %s', File_Path);
end
if isempty(SCR_Nodes) || any(~isfinite(SCR_Nodes)) || ...
        any(SCR_Nodes ~= round(SCR_Nodes)) || ...
        any(SCR_Nodes < 1 | SCR_Nodes > CONF.Bn) || ...
        numel(unique(SCR_Nodes)) ~= numel(SCR_Nodes)
    error('Fig6Scatter:InvalidSCRNodeMapping', ...
        'SCR-node mapping is invalid: %s', File_Path);
end
if ~isempty(Expected_Nodes) && ~isequal(SCC_Nodes, Expected_Nodes)
    error('Fig6Scatter:InconsistentNodeMapping', ...
        'SCC-node mapping is inconsistent: %s', File_Path);
end

Expected_SCC_Size = [Period_Count Representative_Day_Count numel(SCC_Nodes)];
if ~size_matches(Result.SCC_TimeResolved, Expected_SCC_Size) || ...
        ~size_matches(Result.SCC_Aggregated, [CONF.Bn Representative_Day_Count]) || ...
        ~size_matches(Result.SCR_TimeResolved, ...
        [Period_Count Representative_Day_Count numel(SCR_Nodes)]) || ...
        ~size_matches(Result.SCR_Aggregated, [CONF.Bn Representative_Day_Count]) || ...
        ~size_matches(Result.u_G, [CONF.Gn Representative_Day_Count Period_Count]) || ...
        ~size_matches(Result.u_G_SCC, [CONF.Gn Representative_Day_Count])
    error('Fig6Scatter:DimensionMismatch', ...
        'SCC or commitment dimensions are invalid in %s.', File_Path);
end
if any(~isfinite(Result.SCC_TimeResolved), 'all') || ...
        any(~isfinite(Result.SCC_Aggregated(SCC_Nodes, :)), 'all') || ...
        any(~isfinite(Result.SCR_TimeResolved), 'all') || ...
        any(~isfinite(Result.SCR_Aggregated(SCR_Nodes, :)), 'all') || ...
        any(~isfinite(Result.u_G), 'all') || ...
        any(~isfinite(Result.u_G_SCC), 'all')
    error('Fig6Scatter:NonfiniteData', ...
        'Result contains nonfinite SCC or commitment data: %s', File_Path);
end

Binary_Tolerance = 1e-6;
if any(abs(Result.u_G-round(Result.u_G)) > Binary_Tolerance, 'all')
    error('Fig6Scatter:NonbinaryCommitment', ...
        'Hourly SG commitment is not binary in %s.', File_Path);
end
if any(abs(Result.u_G_SCC-round(Result.u_G_SCC)) > Binary_Tolerance, 'all')
    error('Fig6Scatter:NonbinaryUnionState', ...
        'Aggregate SG union state is not binary in %s.', File_Path);
end
if ~isfield(Result.SecurityValidation.Conservatism, 'SCC') || ...
        ~isstruct(Result.SecurityValidation.Conservatism.SCC) || ...
        ~isfield(Result.SecurityValidation.Conservatism.SCC, 'Tolerance') || ...
        ~isscalar(Result.SecurityValidation.Conservatism.SCC.Tolerance) || ...
        ~isfinite(Result.SecurityValidation.Conservatism.SCC.Tolerance) || ...
        Result.SecurityValidation.Conservatism.SCC.Tolerance < 0
    error('Fig6Scatter:MissingTolerance', ...
        'SCC validation tolerance is missing or invalid in %s.', File_Path);
end
end

function [Fig6_Data, Case_Statistics] = build_scc_scatter_data( ...
    Case_Results, Case_Files, SCC_Nodes, Representative_Day_Count, ...
    Period_Count)
%% 每个算例、典型日和安全节点组合生成一对SCC样本。

Node_Count = numel(SCC_Nodes);
Case_Count = numel(Case_Results);
Sample_Count = Case_Count*Representative_Day_Count*Node_Count;
Case_Index_Column = zeros(Sample_Count, 1);
Day_Column = zeros(Sample_Count, 1);
Original_Node_Column = zeros(Sample_Count, 1);
Time_Node_Column = zeros(Sample_Count, 1);
Actual_Maximum_Column = zeros(Sample_Count, 1);
Aggregated_Upper_Column = zeros(Sample_Count, 1);
Delta_Column = zeros(Sample_Count, 1);
Relative_Column = nan(Sample_Count, 1);
Write_Index = 0;

for Case_Index = 1:Case_Count
    Result = Case_Results{Case_Index};
    Tolerance_kA = Result.SecurityValidation.Conservatism.SCC.Tolerance;
    for Day_Index = 1:Representative_Day_Count
        for Node_Index = 1:Node_Count
            Hourly_SCC = Result.SCC_TimeResolved(:, Day_Index, Node_Index);
            Actual_Max_kA = max(Hourly_SCC, [], 'omitnan');
            Original_Node = SCC_Nodes(Node_Index);
            Aggregated_Upper_kA = Result.SCC_Aggregated(Original_Node, Day_Index);
            Delta_kA = Aggregated_Upper_kA - Actual_Max_kA;
            if ~isfinite(Actual_Max_kA) || ~isfinite(Aggregated_Upper_kA) || ...
                    ~isfinite(Delta_kA)
                error('Fig6Scatter:NonfiniteSample', ...
                    ['Case %d, representative day %d, original node %d ', ...
                    'contains a nonfinite SCC sample in %s.'], Case_Index, ...
                    Day_Index, Original_Node, Case_Files{Case_Index});
            end
            if Delta_kA < -Tolerance_kA
                error('Fig6Scatter:ConservatismViolation', ...
                    ['Case %d, representative day %d, original node %d ', ...
                    'violates SCC conservatism: aggregate=%.12g kA, ', ...
                    'hourly maximum=%.12g kA, delta=%.12g kA, ', ...
                    'tolerance=%.12g kA (%s).'], Case_Index, Day_Index, ...
                    Original_Node, Aggregated_Upper_kA, Actual_Max_kA, ...
                    Delta_kA, Tolerance_kA, Case_Files{Case_Index});
            end
            Write_Index = Write_Index + 1;
            Case_Index_Column(Write_Index) = Case_Index;
            Day_Column(Write_Index) = Day_Index;
            Original_Node_Column(Write_Index) = Original_Node;
            Time_Node_Column(Write_Index) = Node_Index;
            Actual_Maximum_Column(Write_Index) = Actual_Max_kA;
            Aggregated_Upper_Column(Write_Index) = Aggregated_Upper_kA;
            Delta_Column(Write_Index) = Delta_kA;
            if Actual_Max_kA > 0
                Relative_Column(Write_Index) = Delta_kA/Actual_Max_kA;
            end
        end
    end
end

Fig6_Data = table(Case_Index_Column, Day_Column, Original_Node_Column, ...
    Time_Node_Column, Actual_Maximum_Column, Aggregated_Upper_Column, ...
    Delta_Column, Relative_Column, 'VariableNames', ...
    {'CaseIndex', 'RepresentativeDay', 'OriginalNode', ...
    'TimeResolvedNodeIndex', 'ActualMaximumSCC_kA', ...
    'AggregatedSCCUpperBound_kA', 'DeltaSCC_kA', 'RelativeMargin'});

Finite_Relative = isfinite(Fig6_Data.RelativeMargin);
Case_Statistics = struct();
Case_Statistics.Sample_Count = height(Fig6_Data);
Case_Statistics.MeanMargin_kA = mean(Fig6_Data.DeltaSCC_kA, 'omitnan');
Case_Statistics.MaxMargin_kA = max(Fig6_Data.DeltaSCC_kA, [], 'omitnan');
if any(Finite_Relative)
    Case_Statistics.MeanRelativeMargin = ...
        mean(Fig6_Data.RelativeMargin(Finite_Relative), 'omitnan');
else
    Case_Statistics.MeanRelativeMargin = NaN;
end
Case_Statistics.Case_Counts = zeros(Case_Count, 1);
Case_Statistics.Case_MeanMargin_kA = zeros(Case_Count, 1);
Case_Statistics.Case_MaxMargin_kA = zeros(Case_Count, 1);
for Case_Index = 1:Case_Count
    Is_Case = Fig6_Data.CaseIndex == Case_Index;
    Case_Statistics.Case_Counts(Case_Index) = nnz(Is_Case);
    Case_Statistics.Case_MeanMargin_kA(Case_Index) = ...
        mean(Fig6_Data.DeltaSCC_kA(Is_Case), 'omitnan');
    Case_Statistics.Case_MaxMargin_kA(Case_Index) = ...
        max(Fig6_Data.DeltaSCC_kA(Is_Case), [], 'omitnan');
end
if Write_Index ~= Sample_Count
    error('Fig6Scatter:InternalSampleCountError', ...
        'Expected %d samples but constructed %d.', Sample_Count, Write_Index);
end
if Period_Count < 1
    error('Fig6Scatter:InvalidPeriodCount', ...
        'Period count must be positive.');
end
end

function print_case_statistics(Fig6_Data, Case_Statistics)
%% 输出各算例聚合界与逐时极值的差值统计。
fprintf('Fig. 6 SCC conservatism statistics:\n');
fprintf('  Total samples: %d\n', Case_Statistics.Sample_Count);
for Case_Index = 1:numel(Case_Statistics.Case_Counts)
    fprintf(['  Case %d: %d samples, mean margin %.6g kA, ', ...
        'max margin %.6g kA\n'], Case_Index, ...
        Case_Statistics.Case_Counts(Case_Index), ...
        Case_Statistics.Case_MeanMargin_kA(Case_Index), ...
        Case_Statistics.Case_MaxMargin_kA(Case_Index));
end
fprintf('  Mean absolute margin: %.6g kA\n', ...
    Case_Statistics.MeanMargin_kA);
fprintf('  Maximum absolute margin: %.6g kA\n', ...
    Case_Statistics.MaxMargin_kA);
fprintf('  Mean relative margin: %.6g%%\n', ...
    100*Case_Statistics.MeanRelativeMargin);
if height(Fig6_Data) == 0
    error('Fig6Scatter:EmptyData', 'No scatter samples were constructed.');
end
end

function Matches = size_matches(Value, Expected)
%% 比较数组维度，补齐MATLAB省略的尾部单维。
Actual = size(Value);
Actual(end+1:numel(Expected)) = 1;
Matches = isequal(Actual(1:numel(Expected)), Expected) && ...
    all(Actual(numel(Expected)+1:end) == 1);
end
