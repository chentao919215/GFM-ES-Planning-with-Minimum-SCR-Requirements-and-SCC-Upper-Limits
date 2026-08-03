%% 分别生成SCC、经典SCR和安全裕度图及对应表格。
% 以下路径留空时，脚本自动使用最新结果、默认参数文件和默认输出目录。
if ~exist('result_file', 'var'), Result_File = ''; end
if ~exist('output_dir', 'var'), Output_Directory = ''; end
if ~exist('param_file', 'var'), Parameter_File = ''; end
if ~exist('scenario_index', 'var'), Scenario_Index = []; end
[Data, Output_Directory] = load_figure_data(Result_File, Output_Directory, ...
    Parameter_File, '04_security', Scenario_Index);

S = Data.Security;
D = Data.D;
if exist('typical_day_index', 'var') && ~isempty(Typical_Day_Index)
    Day_Indices = Typical_Day_Index;
else
    Day_Indices = 1:D;
end
Max_SCC_Error = max(S.SCCRelativeErrorPct(:), [], 'omitnan');
Max_SCR_Error = max(S.SCRRelativeErrorPct(:), [], 'omitnan');

% 矩阵按[安全节点,典型日]保存；导出与绘图时按典型日逐块展开。
SCC_Day = reshape(repelem(Day_Indices(:),numel(S.SCCNodes)), [], 1);
SCC_Bus = repmat(S.SCCNodes,numel(Day_Indices),1);
SCC_Optimization = S.SCCOptimization(:,Day_Indices); SCC_Optimization = SCC_Optimization(:);
SCC_Exact = S.SCCExact(:,Day_Indices); SCC_Exact = SCC_Exact(:);
SCC_Limit = S.SCCLimit(:,Day_Indices); SCC_Limit = SCC_Limit(:);
SCC_Margin = S.SCCMargin(:,Day_Indices); SCC_Margin = SCC_Margin(:);
SCC_Error = S.SCCRelativeErrorPct(:,Day_Indices); SCC_Error = SCC_Error(:);
SCC_Labels = compose('D%d-B%d',SCC_Day,SCC_Bus);

SCR_Day = reshape(repelem(Day_Indices(:),numel(S.SCRNodes)), [], 1);
SCR_Bus = repmat(S.SCRNodes,numel(Day_Indices),1);
SCR_Optimization = S.SCROptimization(:,Day_Indices); SCR_Optimization = SCR_Optimization(:);
SCR_Exact = S.SCRExact(:,Day_Indices); SCR_Exact = SCR_Exact(:);
SCR_Limit = S.SCRLimit(:,Day_Indices); SCR_Limit = SCR_Limit(:);
SCR_Margin = S.SCRMargin(:,Day_Indices); SCR_Margin = SCR_Margin(:);
SCR_Error = S.SCRRelativeErrorPct(:,Day_Indices); SCR_Error = SCR_Error(:);
SCR_Labels = compose('D%d-B%d',SCR_Day,SCR_Bus);

fig = new_figure([9.0 5.0]); ax = axes(fig);
x = 1:numel(SCC_Bus);
b = bar(ax, x, [SCC_Optimization SCC_Exact], 0.72, ...
    'EdgeColor', 'k', 'LineWidth', 0.7);
b(1).FaceColor = [0.34 0.54 0.72];
b(2).FaceColor = [0.78 0.55 0.25];
hold(ax, 'on');
p = plot(ax, x, SCC_Limit, 'k-d', 'LineWidth', 1.2, ...
    'MarkerFaceColor', 'w', 'MarkerSize', 5);
[Min_Margin, Min_Index] = min(SCC_Margin);
plot(ax, Min_Index, SCC_Exact(Min_Index), 'ko', 'MarkerSize', 9, 'LineWidth', 1.2);
text(ax, Min_Index, SCC_Exact(Min_Index), sprintf('  min margin %.3f kA', Min_Margin), ...
    'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'center', ...
    'FontName', 'Times New Roman', 'FontSize', 9);
hold(ax, 'off'); style_sci_axes(ax);
xticks(ax, x); xticklabels(ax, SCC_Labels);
xlabel(ax, 'Typical day - SCC-constrained bus'); ylabel(ax, 'Short-circuit current (kA)');
title(ax, sprintf(['SCC security in daily aggregated conservative states ', ...
    '(max post-hoc error %.2e%%)'], Max_SCC_Error));
legend(ax, [b(:);p], {'Optimization reconstruction','Post-hoc direct inversion', ...
    'Upper limit'}, 'Location', 'southoutside', 'NumColumns', 3);
save_figure_file(fig, fullfile(Output_Directory, 'SCC_level_and_limit'));

fig = new_figure([7.5 4.8]); ax = axes(fig);
x = 1:numel(SCR_Bus);
b = bar(ax, x, [SCR_Optimization SCR_Exact], 0.68, ...
    'EdgeColor', 'k', 'LineWidth', 0.7);
b(1).FaceColor = [0.34 0.54 0.72];
b(2).FaceColor = [0.78 0.55 0.25];
hold(ax, 'on');
p = plot(ax, x, SCR_Limit, 'k-d', 'LineWidth', 1.2, ...
    'MarkerFaceColor', 'w', 'MarkerSize', 5);
[Min_Margin, Min_Index] = min(SCR_Margin);
plot(ax, Min_Index, SCR_Exact(Min_Index), 'ko', 'MarkerSize', 9, 'LineWidth', 1.2);
text(ax, Min_Index, SCR_Exact(Min_Index), sprintf('  min margin %.4g', Min_Margin), ...
    'VerticalAlignment', 'bottom', 'FontName', 'Times New Roman', 'FontSize', 9);
hold(ax, 'off'); style_sci_axes(ax);
xticks(ax, x); xticklabels(ax, SCR_Labels);
xlabel(ax, 'Typical day - classic-SCR-constrained GFL-WG bus');
ylabel(ax, 'Classic short-circuit ratio (p.u.)');
title(ax, sprintf(['Classic SCR in daily aggregated conservative states ', ...
    '(max post-hoc error %.2e%%)'], Max_SCR_Error));
legend(ax, [b(:);p], {'Optimization reconstruction','Post-hoc direct inversion', ...
    'Lower limit'}, 'Location', 'southoutside', 'NumColumns', 3);
save_figure_file(fig, fullfile(Output_Directory, 'classic_SCR_level_and_limit'));

fig = new_figure([9.0 6.2]);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = nexttile(tl);
[v,idx] = sort(SCC_Margin, 'ascend');
bar(ax, 1:numel(v), v, 0.68, 'FaceColor', [0.35 0.54 0.70], 'EdgeColor', 'k');
style_sci_axes(ax); yline(ax, 0, 'k--');
xticks(ax, 1:numel(v)); xticklabels(ax, SCC_Labels(idx));
xlabel(ax, 'Typical day - bus (tightest first)'); ylabel(ax, 'SCC margin (kA)');
title(ax, 'SCC upper-limit margin: limit - post-hoc value');
ax = nexttile(tl);
[v,idx] = sort(SCR_Margin, 'ascend');
bar(ax, 1:numel(v), v, 0.68, 'FaceColor', [0.76 0.53 0.24], 'EdgeColor', 'k');
style_sci_axes(ax); yline(ax, 0, 'k--');
xticks(ax, 1:numel(v)); xticklabels(ax, SCR_Labels(idx));
xlabel(ax, 'Typical day - bus (tightest first)'); ylabel(ax, 'Classic SCR margin (p.u.)');
title(ax, 'Classic SCR lower-limit margin: post-hoc value - limit');
title(tl, 'Security margins in daily aggregated conservative states', ...
    'FontName', 'Times New Roman', 'FontSize', 12);
save_figure_file(fig, fullfile(Output_Directory, 'security_margin_ranking'));

SCC_Table = table(SCC_Day,SCC_Bus,SCC_Optimization,SCC_Exact,SCC_Limit, ...
    SCC_Margin,SCC_Error,'VariableNames', ...
    {'TypicalDay','Bus','Optimization_kA','PostHoc_kA','UpperLimit_kA', ...
    'Margin_kA','RelativeError_pct'});
SCR_Table = table(SCR_Day,SCR_Bus,SCR_Optimization,SCR_Exact,SCR_Limit, ...
    SCR_Margin,SCR_Error,'VariableNames', ...
    {'TypicalDay','Bus','OptimizationClassicSCR','PostHocClassicSCR','LowerLimit', ...
    'Margin','RelativeError_pct'});
Report = struct();
Report.SCC = SCC_Table;
Report.ClassicSCR = SCR_Table;
Report.Validation = [validation_row('SCC_max_posthoc_relative_error', ...
    Max_SCC_Error, 0.1, 'percent'); ...
    validation_row('classic_SCR_max_posthoc_relative_error', ...
    Max_SCR_Error, 0.1, 'percent'); ...
    validation_row('minimum_SCC_security_margin', min(SCC_Margin), ...
    0, 'kA', all(SCC_Margin >= -1e-6)); ...
    validation_row('minimum_classic_SCR_security_margin', min(SCR_Margin), ...
        0, 'p.u.', all(SCR_Margin >= -1e-6))];

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
savefig(fig, File_Path);
set(fig, 'Visible', 'off');
Png_Path = strrep(File_Path, '.fig', '.png');
exportgraphics(fig, Png_Path, 'Resolution', 600, 'BackgroundColor', 'white');
close(fig);
end

function row = validation_row(name, value, tolerance, unit, passed)
if nargin < 5
    passed = abs(value) <= tolerance;
end
row = table(string(name), value, abs(value), tolerance, string(unit), ...
    logical(passed), 'VariableNames', ...
    {'Check','Value','AbsoluteValue','Tolerance','Unit','Passed'});
end
