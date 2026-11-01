function Report = plot_04_security(Options)
%% 分别生成SCC、经典SCR和安全裕度图及对应表格。
% 通过Options指定结果文件、输出目录和场景；默认读取最新主规划结果。
if nargin < 1
    Options = struct();
end

%% 1. 准备绘图输入与样式
Script_Directory = fileparts(mfilename('fullpath'));
addpath(fullfile(fileparts(fileparts(fileparts(Script_Directory))), 'functions', 'utils'));
Project_Root = find_project_root(Script_Directory);
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
Options = figure_options(Options, struct('Result_File', '', 'Output_Directory', fullfile(Project_Root, ...
    'figs', 'for_debug', '04_security'), 'Scenario_Index', 1, 'Typical_Day_Index', []));
Style = figure_style('review');
Style.Visible = Options.Visible;
Style.Close_After_Save = Options.Close_After_Save;
Result_File = Options.Result_File;
Output_Directory = Options.Output_Directory;
Scenario_Index = Options.Scenario_Index;
Typical_Day_Index = Options.Typical_Day_Index;
[Data, Output_Directory] = load_figure_data(Result_File, Output_Directory, ...
    '04_security', Scenario_Index);
Data.Style = Style;

S = prepare_security_data(Data.Result);
D = Data.D;
if ~isempty(Typical_Day_Index)
    Day_Indices = Typical_Day_Index;
else
    Day_Indices = 1:D;
end
Max_SCC_Violation = S.Validation.Conservatism.SCC.MaximumViolation;
Max_SCR_Violation = S.Validation.Conservatism.SCR.MaximumViolation;

% 矩阵按[安全节点,典型日]保存；导出与绘图时按典型日逐块展开。
SCC_Day = reshape(repelem(Day_Indices(:), numel(S.SCC_Nodes)), [], 1);
SCC_Bus = repmat(S.SCC_Nodes, numel(Day_Indices), 1);
SCC_Aggregated = S.SCC_Aggregated(:, Day_Indices); SCC_Aggregated = SCC_Aggregated(:);
SCC_Hourly_Max = S.SCC_Hourly_Max(:, Day_Indices); SCC_Hourly_Max = SCC_Hourly_Max(:);
SCC_Limit = S.SCC_Limit(:, Day_Indices); SCC_Limit = SCC_Limit(:);
SCC_Aggregated_Margin = S.SCC_Aggregated_Margin(:, ...
    Day_Indices); SCC_Aggregated_Margin = SCC_Aggregated_Margin(:);
SCC_Hourly_Margin = S.SCC_Hourly_Margin(:, Day_Indices); SCC_Hourly_Margin = SCC_Hourly_Margin(:);
SCC_Conservatism = S.SCC_Conservatism_Margin(:, Day_Indices); SCC_Conservatism = SCC_Conservatism(:);
SCC_Labels = compose('D%d-B%d', SCC_Day, SCC_Bus);

SCR_Day = reshape(repelem(Day_Indices(:), numel(S.SCR_Nodes)), [], 1);
SCR_Bus = repmat(S.SCR_Nodes, numel(Day_Indices), 1);
SCR_Aggregated = S.SCR_Aggregated(:, Day_Indices); SCR_Aggregated = SCR_Aggregated(:);
SCR_Hourly_Min = S.SCR_Hourly_Min(:, Day_Indices); SCR_Hourly_Min = SCR_Hourly_Min(:);
SCR_Limit = S.SCR_Limit(:, Day_Indices); SCR_Limit = SCR_Limit(:);
SCR_Aggregated_Margin = S.SCR_Aggregated_Margin(:, ...
    Day_Indices); SCR_Aggregated_Margin = SCR_Aggregated_Margin(:);
SCR_Hourly_Margin = S.SCR_Hourly_Margin(:, Day_Indices); SCR_Hourly_Margin = SCR_Hourly_Margin(:);
SCR_Conservatism = S.SCR_Conservatism_Margin(:, Day_Indices); SCR_Conservatism = SCR_Conservatism(:);
SCR_Labels = compose('D%d-B%d', SCR_Day, SCR_Bus);

%% 2. 绘制指标图件
fig = new_figure(2.54*[9.0 5.0], Data.Style); ax = axes(fig);
x = 1:numel(SCC_Bus);
b = bar(ax, x, [SCC_Aggregated SCC_Hourly_Max], 0.72, ...
    'EdgeColor', 'k', 'LineWidth', 0.7);
b(1).FaceColor = Style.Colors.Aggregated;
b(2).FaceColor = Style.Colors.Periodwise;
hold(ax, 'on');
p = plot(ax, x, SCC_Limit, 'k-d', 'LineWidth', 1.2, ...
    'MarkerFaceColor', 'w', 'MarkerSize', 5);
[Min_Margin, Min_Index] = min(SCC_Aggregated_Margin);
plot(ax, Min_Index, SCC_Aggregated(Min_Index), 'ko', 'MarkerSize', 9, 'LineWidth', 1.2);
text(ax, Min_Index, SCC_Aggregated(Min_Index), sprintf('  SCC_Aggregated min margin %.3f kA', Min_Margin), ...
    'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'center', ...
    'FontName', 'Times New Roman', 'FontSize', 9);
hold(ax, 'off'); style_sci_axes(ax);
xticks(ax, x); xticklabels(ax, SCC_Labels);
xlabel(ax, 'Typical day - SCC-constrained bus'); ylabel(ax, 'Short-circuit current (kA)');
title(ax, sprintf(['Aggregate SCC upper bound vs hourly posterior maximum ', ...
    '(max violation %.3g kA)'], Max_SCC_Violation));
legend(ax, [b(:);p], {'Aggregate SCC upper bound', ...
    'Hourly posterior maximum', 'Upper limit'}, ...
    'Location', 'southoutside', 'NumColumns', 3);
save_figure_file(fig, fullfile(Output_Directory, 'SCC_level_and_limit'));

fig = new_figure(2.54*[7.5 4.8], Data.Style); ax = axes(fig);
x = 1:numel(SCR_Bus);
b = bar(ax, x, [SCR_Aggregated SCR_Hourly_Min], 0.68, ...
    'EdgeColor', 'k', 'LineWidth', 0.7);
b(1).FaceColor = Style.Colors.Aggregated;
b(2).FaceColor = Style.Colors.Aggregated;
hold(ax, 'on');
p = plot(ax, x, SCR_Limit, 'k-d', 'LineWidth', 1.2, ...
    'MarkerFaceColor', 'w', 'MarkerSize', 5);
[Min_Margin, Min_Index] = min(SCR_Hourly_Margin);
plot(ax, Min_Index, SCR_Hourly_Min(Min_Index), 'ko', 'MarkerSize', 9, 'LineWidth', 1.2);
text(ax, Min_Index, SCR_Hourly_Min(Min_Index), sprintf('  min hourly margin %.4g', Min_Margin), ...
    'VerticalAlignment', 'bottom', 'FontName', 'Times New Roman', 'FontSize', 9);
hold(ax, 'off'); style_sci_axes(ax);
xticks(ax, x); xticklabels(ax, SCR_Labels);
xlabel(ax, 'Typical day - classic-SCR-constrained GFL-WG bus');
ylabel(ax, 'Classic short-circuit ratio');
title(ax, sprintf(['Aggregate SCR lower bound vs hourly posterior minimum ', ...
    '(max violation %.3g)'], Max_SCR_Violation));
legend(ax, [b(:);p], {'Aggregate SCR lower bound', 'Hourly posterior minimum', ...
    'Lower limit'}, 'Location', 'southoutside', 'NumColumns', 3);
save_figure_file(fig, fullfile(Output_Directory, 'classic_SCR_level_and_limit'));

fig = new_figure(2.54*[9.0 6.2], Data.Style);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = nexttile(tl);
[~, idx] = sort(SCC_Aggregated_Margin, 'ascend');
b = bar(ax, 1:numel(idx), [SCC_Aggregated_Margin(idx) SCC_Hourly_Margin(idx)], ...
    0.72, 'EdgeColor', 'k');
b(1).FaceColor = Style.Colors.Aggregated;
b(2).FaceColor = Style.Colors.Periodwise;
style_sci_axes(ax); yline(ax, 0, 'k--');
xticks(ax, 1:numel(idx)); xticklabels(ax, SCC_Labels(idx));
xlabel(ax, 'Typical day - bus (tightest first)'); ylabel(ax, 'SCC margin (kA)');
title(ax, 'SCC upper-limit margins: limit - SCC result');
legend(ax, {'Aggregate-bound margin', 'Hourly-maximum margin'}, ...
    'Location', 'best', 'NumColumns', 2);
ax = nexttile(tl);
[~, idx] = sort(SCR_Hourly_Margin, 'ascend');
b = bar(ax, 1:numel(idx), ...
    [SCR_Aggregated_Margin(idx) SCR_Hourly_Margin(idx)], ...
    0.72, 'EdgeColor', 'k');
b(1).FaceColor = Style.Colors.Aggregated;
b(2).FaceColor = Style.Colors.Aggregated;
style_sci_axes(ax); yline(ax, 0, 'k--');
xticks(ax, 1:numel(idx)); xticklabels(ax, SCR_Labels(idx));
xlabel(ax, 'Typical day - bus (tightest first)'); ylabel(ax, 'Classic SCR margin (p.u.)');
title(ax, 'Classic SCR lower-limit margins');
legend(ax, {'Aggregate-bound margin', 'Hourly-minimum margin'}, ...
    'Location', 'best', 'NumColumns', 2);
title(tl, 'Aggregate bounds and actual hourly posterior security margins', ...
    'FontName', 'Times New Roman', 'FontSize', 12);
save_figure_file(fig, fullfile(Output_Directory, 'security_margin_ranking'));

SCC_Table = table(SCC_Day, SCC_Bus, SCC_Aggregated, SCC_Hourly_Max, SCC_Limit, ...
    SCC_Aggregated_Margin, SCC_Hourly_Margin, SCC_Conservatism, 'VariableNames', ...
    {'TypicalDay', 'Bus', 'AggregateUpperBound_kA', 'HourlyMaximum_kA', ...
    'UpperLimit_kA', 'AggregateMargin_kA', 'HourlyMargin_kA', ...
    'AggregateMinusHourlyMax_kA'});
SCR_Table = table(SCR_Day, SCR_Bus, SCR_Aggregated, SCR_Hourly_Min, SCR_Limit, ...
    SCR_Aggregated_Margin, SCR_Hourly_Margin, SCR_Conservatism, ...
    'VariableNames', {'TypicalDay', 'Bus', 'AggregateLowerBound', ...
    'HourlyMinimum', 'LowerLimit', 'AggregateMargin', 'HourlyMargin', ...
    'HourlyMinMinusAggregate'});

%% 3. 返回统计与核验结果
Report = struct();
Report.SCC = SCC_Table;
Report.ClassicSCR = SCR_Table;
Report.Validation = [validation_row('aggregate_SCC_max_violation', ...
    Max_SCC_Violation, S.Validation.Conservatism.SCC.Tolerance, 'kA', ...
    S.Validation.Conservatism.SCC.Passed); ...
    validation_row('aggregate_SCR_max_violation', ...
    Max_SCR_Violation, S.Validation.Conservatism.SCR.Tolerance, 'p.u.', ...
    S.Validation.Conservatism.SCR.Passed); ...
    validation_row('minimum_SCC_Aggregated_security_margin', min(SCC_Aggregated_Margin), ...
    0, 'kA', all(SCC_Aggregated_Margin >= -1e-6)); ...
    validation_row('minimum_hourly_SCC_security_margin', min(SCC_Hourly_Margin), ...
    0, 'kA', all(SCC_Hourly_Margin >= -1e-6)); ...
    validation_row('minimum_aggregate_SCR_security_margin', ...
    min(SCR_Aggregated_Margin), 0, 'p.u.', ...
    all(SCR_Aggregated_Margin >= -1e-6)); ...
    validation_row('minimum_hourly_SCR_security_margin', ...
    min(SCR_Hourly_Margin), 0, 'p.u.', ...
    all(SCR_Hourly_Margin >= -1e-6))];

end

function row = validation_row(name, value, tolerance, unit, passed)
%% 将一个检查量、容差和单位整理为摘要表的一行。
if nargin < 5
    passed = abs(value) <= tolerance;
end
row = table(string(name), value, abs(value), tolerance, string(unit), ...
    logical(passed), 'VariableNames', ...
    {'Check', 'Value', 'AbsoluteValue', 'Tolerance', 'Unit', 'Passed'});
end

function Security = prepare_security_data(R)
%% 将已归档的安全指标整理为[安全节点,典型日]，不重新求解网络。
C = R.CONF;
D = C.TypicalDayCount;
assert_size(R.SCC_Aggregated, [C.Bn D], 'SCC_Aggregated');
assert_size(R.SCR_Aggregated, [C.Bn D], 'SCR_Aggregated');
assert_size(R.SCC_TimeResolved, ...
    [C.PeriodCount D numel(C.SCC_Constraint_Original_Nodes)], 'SCC_TimeResolved');
assert_size(R.SCR_TimeResolved, ...
    [C.PeriodCount D numel(C.Safety_GFL_Original_Nodes)], 'SCR_TimeResolved');
Security.SCC_Nodes = R.CONF.SCC_Constraint_Original_Nodes(:);
Security.SCC_Aggregated = R.SCC_Aggregated(Security.SCC_Nodes, :);
Security.SCC_Hourly_Max = reshape(max(R.SCC_TimeResolved, [], 1), ...
    D, numel(Security.SCC_Nodes)).';
Security.SCC_Limit = repmat(C.I_limit_kA_Node(Security.SCC_Nodes), 1, D);
Security.SCC_Aggregated_Margin = Security.SCC_Limit-Security.SCC_Aggregated;
Security.SCC_Hourly_Margin = Security.SCC_Limit-Security.SCC_Hourly_Max;
Security.SCC_Conservatism_Margin = ...
    Security.SCC_Aggregated-Security.SCC_Hourly_Max;

Security.SCR_Nodes = R.CONF.Safety_GFL_Original_Nodes(:);
Security.SCR_Aggregated = R.SCR_Aggregated(Security.SCR_Nodes, :);
Security.SCR_Hourly_Min = reshape(min(R.SCR_TimeResolved, [], 1), ...
    D, numel(Security.SCR_Nodes)).';
if isscalar(C.SCR_min)
    Security.SCR_Limit = repmat(C.SCR_min, numel(Security.SCR_Nodes), D);
else
    Security.SCR_Limit = repmat(C.SCR_min(Security.SCR_Nodes), 1, D);
end
Security.SCR_Aggregated_Margin = Security.SCR_Aggregated-Security.SCR_Limit;
Security.SCR_Hourly_Margin = Security.SCR_Hourly_Min-Security.SCR_Limit;
Security.SCR_Conservatism_Margin = ...
    Security.SCR_Hourly_Min-Security.SCR_Aggregated;
Security.Validation = R.SecurityValidation;
end

function assert_size(value, expected, Field_Name)
%% 核验数组维度，允许MATLAB省略尾部单维。
actual = size(value);
actual(end+1:numel(expected)) = 1;
if ~isequal(actual(1:numel(expected)), expected)
    error('%s has size %s; expected %s.', Field_Name, ...
        mat2str(size(value)), mat2str(expected));
end
end
