%% 分别生成SCC、经典SCR和安全裕度图及对应表格。
% 以下路径留空时，脚本自动使用最新结果、默认参数文件和默认输出目录。
if ~exist('Result_File', 'var'), Result_File = ''; end
if ~exist('Output_Directory', 'var'), Output_Directory = ''; end
if ~exist('Parameter_File', 'var'), Parameter_File = ''; end
if ~exist('Scenario_Index', 'var'), Scenario_Index = []; end
[Data, Output_Directory] = load_figure_data(Result_File, Output_Directory, ...
    Parameter_File, '04_security', Scenario_Index);

S = Data.Security;
D = Data.D;
if exist('Typical_Day_Index', 'var') && ~isempty(Typical_Day_Index)
    Day_Indices = Typical_Day_Index;
else
    Day_Indices = 1:D;
end
Max_SCC_Violation = S.Validation.SCC.MaximumViolation;
Max_SCR_Violation = S.Validation.SCR.MaximumViolation;

% 矩阵按[安全节点,典型日]保存；导出与绘图时按典型日逐块展开。
SCC_Day = reshape(repelem(Day_Indices(:),numel(S.SCC_Nodes)), [], 1);
SCC_Bus = repmat(S.SCC_Nodes,numel(Day_Indices),1);
SCC_1 = S.SCC_1(:,Day_Indices); SCC_1 = SCC_1(:);
SCC_Hourly_Max = S.SCC_Hourly_Max(:,Day_Indices); SCC_Hourly_Max = SCC_Hourly_Max(:);
SCC_Limit = S.SCC_Limit(:,Day_Indices); SCC_Limit = SCC_Limit(:);
SCC_1_Margin = S.SCC_1_Margin(:,Day_Indices); SCC_1_Margin = SCC_1_Margin(:);
SCC_Hourly_Margin = S.SCC_Hourly_Margin(:,Day_Indices); SCC_Hourly_Margin = SCC_Hourly_Margin(:);
SCC_Conservatism = S.SCC_Conservatism_Margin(:,Day_Indices); SCC_Conservatism = SCC_Conservatism(:);
SCC_Labels = compose('D%d-B%d',SCC_Day,SCC_Bus);

SCR_Day = reshape(repelem(Day_Indices(:),numel(S.SCR_Nodes)), [], 1);
SCR_Bus = repmat(S.SCR_Nodes,numel(Day_Indices),1);
SCR_Aggregated = S.SCR_Aggregated(:,Day_Indices); SCR_Aggregated = SCR_Aggregated(:);
SCR_Hourly_Min = S.SCR_Hourly_Min(:,Day_Indices); SCR_Hourly_Min = SCR_Hourly_Min(:);
SCR_Limit = S.SCR_Limit(:,Day_Indices); SCR_Limit = SCR_Limit(:);
SCR_Aggregated_Margin = S.SCR_Aggregated_Margin(:,Day_Indices); SCR_Aggregated_Margin = SCR_Aggregated_Margin(:);
SCR_Hourly_Margin = S.SCR_Hourly_Margin(:,Day_Indices); SCR_Hourly_Margin = SCR_Hourly_Margin(:);
SCR_Conservatism = S.SCR_Conservatism_Margin(:,Day_Indices); SCR_Conservatism = SCR_Conservatism(:);
SCR_Labels = compose('D%d-B%d',SCR_Day,SCR_Bus);

fig = new_figure([9.0 5.0]); ax = axes(fig);
x = 1:numel(SCC_Bus);
b = bar(ax, x, [SCC_1 SCC_Hourly_Max], 0.72, ...
    'EdgeColor', 'k', 'LineWidth', 0.7);
b(1).FaceColor = [0.78 0.55 0.25];
b(2).FaceColor = [0.42 0.66 0.43];
hold(ax, 'on');
p = plot(ax, x, SCC_Limit, 'k-d', 'LineWidth', 1.2, ...
    'MarkerFaceColor', 'w', 'MarkerSize', 5);
[Min_Margin, Min_Index] = min(SCC_1_Margin);
plot(ax, Min_Index, SCC_1(Min_Index), 'ko', 'MarkerSize', 9, 'LineWidth', 1.2);
text(ax, Min_Index, SCC_1(Min_Index), sprintf('  SCC_1 min margin %.3f kA', Min_Margin), ...
    'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'center', ...
    'FontName', 'Times New Roman', 'FontSize', 9);
hold(ax, 'off'); style_sci_axes(ax);
xticks(ax, x); xticklabels(ax, SCC_Labels);
xlabel(ax, 'Typical day - SCC-constrained bus'); ylabel(ax, 'Short-circuit current (kA)');
title(ax, sprintf(['Aggregate SCC upper bound vs hourly posterior maximum ', ...
    '(max violation %.3g kA)'], Max_SCC_Violation));
legend(ax, [b(:);p], {'Aggregate SCC upper bound', ...
    'Hourly posterior maximum','Upper limit'}, ...
    'Location', 'southoutside', 'NumColumns', 3);
save_figure_file(fig, fullfile(Output_Directory, 'SCC_level_and_limit'));

fig = new_figure([7.5 4.8]); ax = axes(fig);
x = 1:numel(SCR_Bus);
b = bar(ax, x, [SCR_Aggregated SCR_Hourly_Min], 0.68, ...
    'EdgeColor', 'k', 'LineWidth', 0.7);
b(1).FaceColor = [0.34 0.54 0.72];
b(2).FaceColor = [0.78 0.55 0.25];
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
ylabel(ax, 'Classic short-circuit ratio (p.u.)');
title(ax, sprintf(['Aggregate SCR lower bound vs hourly posterior minimum ', ...
    '(max violation %.3g)'], Max_SCR_Violation));
legend(ax, [b(:);p], {'Aggregate SCR lower bound','Hourly posterior minimum', ...
    'Lower limit'}, 'Location', 'southoutside', 'NumColumns', 3);
save_figure_file(fig, fullfile(Output_Directory, 'classic_SCR_level_and_limit'));

fig = new_figure([9.0 6.2]);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = nexttile(tl);
[~,idx] = sort(SCC_1_Margin, 'ascend');
b = bar(ax, 1:numel(idx), [SCC_1_Margin(idx) SCC_Hourly_Margin(idx)], ...
    0.72, 'EdgeColor', 'k');
b(1).FaceColor = [0.78 0.55 0.25];
b(2).FaceColor = [0.42 0.66 0.43];
style_sci_axes(ax); yline(ax, 0, 'k--');
xticks(ax, 1:numel(idx)); xticklabels(ax, SCC_Labels(idx));
xlabel(ax, 'Typical day - bus (tightest first)'); ylabel(ax, 'SCC margin (kA)');
title(ax, 'SCC upper-limit margins: limit - SCC result');
legend(ax, {'Aggregate-bound margin','Hourly-maximum margin'}, ...
    'Location', 'best', 'NumColumns', 2);
ax = nexttile(tl);
[~,idx] = sort(SCR_Hourly_Margin, 'ascend');
b = bar(ax, 1:numel(idx), ...
    [SCR_Aggregated_Margin(idx) SCR_Hourly_Margin(idx)], ...
    0.72, 'EdgeColor', 'k');
b(1).FaceColor = [0.34 0.54 0.72];
b(2).FaceColor = [0.78 0.55 0.25];
style_sci_axes(ax); yline(ax, 0, 'k--');
xticks(ax, 1:numel(idx)); xticklabels(ax, SCR_Labels(idx));
xlabel(ax, 'Typical day - bus (tightest first)'); ylabel(ax, 'Classic SCR margin (p.u.)');
title(ax, 'Classic SCR lower-limit margins');
legend(ax, {'Aggregate-bound margin','Hourly-minimum margin'}, ...
    'Location', 'best', 'NumColumns', 2);
title(tl, 'Aggregate bounds and actual hourly posterior security margins', ...
    'FontName', 'Times New Roman', 'FontSize', 12);
save_figure_file(fig, fullfile(Output_Directory, 'security_margin_ranking'));

SCC_Table = table(SCC_Day,SCC_Bus,SCC_1,SCC_Hourly_Max,SCC_Limit, ...
    SCC_1_Margin,SCC_Hourly_Margin,SCC_Conservatism,'VariableNames', ...
    {'TypicalDay','Bus','AggregateUpperBound_kA','HourlyMaximum_kA', ...
    'UpperLimit_kA','AggregateMargin_kA','HourlyMargin_kA', ...
    'AggregateMinusHourlyMax_kA'});
SCR_Table = table(SCR_Day,SCR_Bus,SCR_Aggregated,SCR_Hourly_Min,SCR_Limit, ...
    SCR_Aggregated_Margin,SCR_Hourly_Margin,SCR_Conservatism, ...
    'VariableNames', {'TypicalDay','Bus','AggregateLowerBound', ...
    'HourlyMinimum','LowerLimit','AggregateMargin','HourlyMargin', ...
    'HourlyMinMinusAggregate'});
Report = struct();
Report.SCC_Definition = S.SCC_Definition;
Report.SCC = SCC_Table;
Report.ClassicSCR = SCR_Table;
Report.SCR_Definition = S.SCR_Definition;
Report.Validation = [validation_row('aggregate_SCC_max_violation', ...
    Max_SCC_Violation, S.Validation.SCC.Tolerance, 'kA', ...
    S.Validation.SCC.Passed); ...
    validation_row('aggregate_SCR_max_violation', ...
    Max_SCR_Violation, S.Validation.SCR.Tolerance, 'p.u.', ...
    S.Validation.SCR.Passed); ...
    validation_row('minimum_SCC_1_security_margin', min(SCC_1_Margin), ...
    0, 'kA', all(SCC_1_Margin >= -1e-6)); ...
    validation_row('minimum_hourly_SCC_security_margin', min(SCC_Hourly_Margin), ...
    0, 'kA', all(SCC_Hourly_Margin >= -1e-6)); ...
    validation_row('minimum_aggregate_SCR_security_margin', ...
    min(SCR_Aggregated_Margin), 0, 'p.u.', ...
    all(SCR_Aggregated_Margin >= -1e-6)); ...
    validation_row('minimum_hourly_SCR_security_margin', ...
    min(SCR_Hourly_Margin), 0, 'p.u.', ...
    all(SCR_Hourly_Margin >= -1e-6))];

function fig = new_figure(Size_Inches)
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', ...
    'Position', [1 1 Size_Inches]);
end

function save_figure_file(fig, File_Path)
set(fig, 'Color', 'w', 'InvertHardcopy', 'off');
drawnow;
if ~endsWith(File_Path, '.fig', 'IgnoreCase', true)
    File_Path = [File_Path '.fig'];
end
set(fig, 'Visible', 'on');
Png_Path = strrep(File_Path, '.fig', '.png');
Output_Directory = fileparts(File_Path);
Temp_Fig_Path = [tempname(Output_Directory) '.fig'];
Temp_Png_Path = [tempname(Output_Directory) '.png'];
Cleanup_Temp_Files = onCleanup(@() delete_temp_files( ...
    {Temp_Fig_Path, Temp_Png_Path})); %#ok<NASGU>

% 先写临时文件，再替换目标文件，避免旧FIG文件状态影响savefig。
savefig(fig, Temp_Fig_Path);
exportgraphics(fig, Temp_Png_Path, 'Resolution', 600, ...
    'BackgroundColor', 'white');
replace_file(Temp_Fig_Path, File_Path);
replace_file(Temp_Png_Path, Png_Path);
set(fig, 'Visible', 'off');
close(fig);
end

function replace_file(Source_Path, Target_Path)
[Success, Message] = movefile(Source_Path, Target_Path, 'f');
if ~Success
    error('无法替换图件文件%s：%s', Target_Path, Message);
end
end

function delete_temp_files(File_Paths)
for k = 1:numel(File_Paths)
    if isfile(File_Paths{k})
        delete(File_Paths{k});
    end
end
end

function row = validation_row(name, value, tolerance, unit, passed)
if nargin < 5
    passed = abs(value) <= tolerance;
end
row = table(string(name), value, abs(value), tolerance, string(unit), ...
    logical(passed), 'VariableNames', ...
    {'Check','Value','AbsoluteValue','Tolerance','Unit','Passed'});
end
