function Report = plot_fig4_security_metrics(Options)
%% Fig. 4：不同安全约束算例的SCC与SCR指标。
% 按编号读取五组第二阶段结果；Case 4和5的安全开关相同，但风电场景不同。
% 结果归档仅读取，不在绘图过程中修改。
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

[Case_Results, Case_Files] = load_stage2_cases(Results_Directory);
validate_case_consistency(Case_Results, Case_Files);

Case_Count = 5;
Maximum_SCC_kA = zeros(1, Case_Count);
Minimum_SCR = zeros(1, Case_Count);
for Case_Index = 1:Case_Count
    Result = Case_Results{Case_Index};
    Maximum_SCC_kA(Case_Index) = max( ...
        Result.SCC_TimeResolved, [], 'all', 'omitnan');
    Minimum_SCR(Case_Index) = min( ...
        Result.SCR_TimeResolved, [], 'all', 'omitnan');
    if ~isfinite(Maximum_SCC_kA(Case_Index)) || ...
            ~isfinite(Minimum_SCR(Case_Index))
        error('Fig4Metrics:InvalidSecurityMetric', ...
            ['Case %d contains no finite time-resolved SCC or SCR value ', ...
            'in %s.'], Case_Index, Case_Files{Case_Index});
    end
end

[SCC_Limit_kA, SCR_Limit] = read_common_security_limits( ...
    Case_Results, Case_Files);

Figure_Width = 3.50;
Figure_Height = 2.40;

%% 2. 绘制论文图件
fig = new_figure(2.54*[Figure_Width Figure_Height], Style);
layout = tiledlayout(fig, 1, 1, 'Padding', 'compact', ...
    'TileSpacing', 'compact');
ax = nexttile(layout);
style_sci_axes(ax);
hold(ax, 'on');

Case_Positions = 1:Case_Count;
Bar_Offset = 0.17;
Bar_Width = 0.28;
SCC_Color = Style.Colors.SCC;
SCR_Color = Style.Colors.SCR;
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
    {'Maximum SCC', SCC_Limit_Legend, ...
    'Minimum SCR', SCR_Limit_Legend}, ...
    'Location', 'northoutside', 'Orientation', 'horizontal', ...
    'NumColumns', 2, 'FontName', 'Times New Roman', 'FontSize', 7.5, ...
    'Interpreter', 'latex', 'Box', 'off');

Output_Base = fullfile(Output_Directory, 'Fig_4_security_metrics');
save_figure_file(fig, Output_Base);

Fig4_Data = table((1:Case_Count).', Maximum_SCC_kA(:), Minimum_SCR(:), ...
    string(Case_Files(:)), 'VariableNames', ...
    {'Case', 'MaximumTimeResolvedSCC_kA', 'MinimumTimeResolvedSCR', ...
    'Stage2ResultFile'});
disp(Fig4_Data);
fprintf('Fig. 4 saved to %s.fig\n', Output_Base);

%% 3. 返回绘图数据与文件位置
Report = struct('Data', Fig4_Data, 'Figure_File', [Output_Base '.fig']);
end

function [Case_Results, Case_Files] = load_stage2_cases(Results_Directory)
%% 按算例编号读取五组第二阶段结果；Case 4和5可具有相同开关。

if ~isfolder(Results_Directory)
    error('Fig4Metrics:MissingResultsDirectory', ...
        'Stage 2 results directory does not exist: %s', Results_Directory);
end
Case_Count = 5;
Case_Results = cell(1, Case_Count);
Case_Files = cell(1, Case_Count);
for Case_Index = 1:Case_Count
    File_Path = fullfile(Results_Directory, ...
        sprintf('Case_%d_Stage_2.mat', Case_Index));
    if ~isfile(File_Path)
        error('Fig4Metrics:MissingStage2Result', ...
            'Stage 2 result for Case %d does not exist: %s', ...
            Case_Index, File_Path);
    end
    Loaded = load(File_Path, 'Result');
    if ~isfield(Loaded, 'Result') || ~isstruct(Loaded.Result)
        error('Fig4Metrics:MissingResult', ...
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
%% 从结果配置快照读取SCC、SCR约束启用状态。
Enable_SCC = Result.CONF.Enable_SCC;
Enable_SCR = Result.CONF.Enable_SCR;
if ~islogical(Enable_SCC) || ~isscalar(Enable_SCC) || ...
        ~islogical(Enable_SCR) || ~isscalar(Enable_SCR)
    error('Fig4Metrics:InvalidSwitchMetadata', ...
        'SCC/SCR switches must be scalar logical values: %s', File_Path);
end
end

function validate_result(Result, File_Path)
%% 核验求解状态及图件所需字段。

Required_Fields = {'SCC_TimeResolved', 'SCR_TimeResolved', 'SCC_Aggregated', ...
    'u_G', 'u_G_SCC', 'CONF', 'SecurityValidation', ...
    'Diagnostics'};
Missing = Required_Fields(~isfield(Result, Required_Fields));
if ~isempty(Missing)
    error('Fig4Metrics:MissingFields', 'Result in %s is missing: %s.', ...
        File_Path, strjoin(Missing, ', '));
end
if ~isfield(Result.Diagnostics, 'problem') || ...
        ~isscalar(Result.Diagnostics.problem) || Result.Diagnostics.problem ~= 0
    error('Fig4Metrics:UnsuccessfulSolve', ...
        'Stage 2 result was not solved successfully: %s', File_Path);
end
if ~isscalar(Result.Diagnostics.has_incumbent) || ...
        ~logical(Result.Diagnostics.has_incumbent)
    error('Fig4Metrics:MissingIncumbent', ...
        'Stage 2 result has no valid incumbent: %s', File_Path);
end

C = Result.CONF;
Required_CONF = {'PeriodCount', 'TypicalDayCount', 'Bn'};
Missing_CONF = Required_CONF(~isfield(C, Required_CONF));
if ~isempty(Missing_CONF)
    error('Fig4Metrics:MissingConfigurationFields', ...
        'CONF in %s is missing: %s.', File_Path, ...
        strjoin(Missing_CONF, ', '));
end
S = Result.CONF;
Required_Network = {'SCC_Constraint_Original_Nodes', ...
    'Safety_GFL_Original_Nodes'};
Missing_Network = Required_Network(~isfield(S, Required_Network));
if ~isempty(Missing_Network)
    error('Fig4Metrics:MissingNodeMapping', ...
        'CONF in %s is missing: %s.', File_Path, ...
        strjoin(Missing_Network, ', '));
end
SCC_Nodes = S.SCC_Constraint_Original_Nodes(:);
SCR_Nodes = S.Safety_GFL_Original_Nodes(:);
if isempty(SCC_Nodes) || isempty(SCR_Nodes) || ...
        any(~isfinite(SCC_Nodes)) || any(~isfinite(SCR_Nodes))
    error('Fig4Metrics:InvalidNodeMapping', ...
        'Security-node mapping is empty or invalid in %s.', File_Path);
end
if ~size_matches(Result.SCC_TimeResolved, ...
        [C.PeriodCount C.TypicalDayCount numel(SCC_Nodes)]) || ...
        ~size_matches(Result.SCR_TimeResolved, ...
        [C.PeriodCount C.TypicalDayCount numel(SCR_Nodes)]) || ...
        ~size_matches(Result.SCC_Aggregated, [C.Bn C.TypicalDayCount])
    error('Fig4Metrics:DimensionMismatch', ...
        'Security-result dimensions do not match saved metadata in %s.', ...
        File_Path);
end
if any(~isfinite(Result.SCC_TimeResolved), 'all') || ...
        any(~isfinite(Result.SCR_TimeResolved), 'all') || ...
        any(~isfinite(Result.SCC_Aggregated(SCC_Nodes, :)), 'all')
    error('Fig4Metrics:NonfiniteSecurityData', ...
        'Required security results contain nonfinite values in %s.', File_Path);
end
end

function validate_case_consistency(Case_Results, Case_Files)
%% 核验各算例的安全节点映射及数组维度一致。

Reference = Case_Results{1};
Reference_SCC_Nodes = ...
    Reference.CONF.SCC_Constraint_Original_Nodes(:);
Reference_SCR_Nodes = ...
    Reference.CONF.Safety_GFL_Original_Nodes(:);
for Case_Index = 2:numel(Case_Results)
    Result = Case_Results{Case_Index};
    Same_Mapping = isequal(Reference_SCC_Nodes, ...
        Result.CONF.SCC_Constraint_Original_Nodes(:)) && ...
        isequal(Reference_SCR_Nodes, ...
        Result.CONF.Safety_GFL_Original_Nodes(:));
    Same_Dimensions = isequal(size(Reference.SCC_TimeResolved), ...
        size(Result.SCC_TimeResolved)) && ...
        isequal(size(Reference.SCR_TimeResolved), ...
        size(Result.SCR_TimeResolved)) && ...
        Reference.CONF.PeriodCount == Result.CONF.PeriodCount && ...
        Reference.CONF.TypicalDayCount == Result.CONF.TypicalDayCount;
    if ~Same_Mapping || ~Same_Dimensions
        error('Fig4Metrics:InconsistentCases', ...
            ['Security-node mapping or data dimensions differ between ', ...
            'Case 1 (%s) and Case %d (%s).'], ...
            Case_Files{1}, Case_Index, Case_Files{Case_Index});
    end
end
end

function [SCC_Limit_kA, SCR_Limit] = read_common_security_limits( ...
    Case_Results, Case_Files)
%% 从Result.CONF读取限值，各算例的同类指标采用同一标量限值。

Case_Count = numel(Case_Results);
SCC_Limits = zeros(1, Case_Count);
SCR_Limits = zeros(1, Case_Count);
for Case_Index = 1:Case_Count
    Result = Case_Results{Case_Index};
    C = Result.CONF;
    SCC_Nodes = Result.CONF.SCC_Constraint_Original_Nodes(:);
    Node_Limits = C.I_limit_kA_Node(SCC_Nodes);
    if any(~isfinite(Node_Limits)) || ...
            max(abs(Node_Limits-Node_Limits(1))) > 1e-10
        error('Fig4Metrics:NonuniformSCCLimit', ...
            'Fig. 4 requires one common SCC limit in %s.', ...
            Case_Files{Case_Index});
    end
    if ~isfield(C, 'SCR_min') || ~isscalar(C.SCR_min) || ...
            ~isfinite(C.SCR_min)
        error('Fig4Metrics:MissingSCRLimit', ...
            'SCR_min is missing or invalid in %s.', Case_Files{Case_Index});
    end
    SCC_Limits(Case_Index) = Node_Limits(1);
    SCR_Limits(Case_Index) = C.SCR_min;
end
if max(abs(SCC_Limits-SCC_Limits(1))) > 1e-10 || ...
        max(abs(SCR_Limits-SCR_Limits(1))) > 1e-10
    error('Fig4Metrics:InconsistentLimits', ...
        'Security thresholds are not identical across the four cases.');
end
SCC_Limit_kA = SCC_Limits(1);
SCR_Limit = SCR_Limits(1);
end

function Matches = size_matches(Value, Expected)
%% 比较数组维度，补齐MATLAB省略的尾部单维。
Actual = size(Value);
Actual(end+1:numel(Expected)) = 1;
Matches = isequal(Actual(1:numel(Expected)), Expected);
end
