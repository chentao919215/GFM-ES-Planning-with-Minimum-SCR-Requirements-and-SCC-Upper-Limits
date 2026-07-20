%% 分别生成SCC、经典SCR和安全裕度图及对应表格。
% 以下路径留空时，脚本自动使用最新结果、默认参数文件和默认输出目录。
if ~exist('result_file', 'var'), result_file = ''; end
if ~exist('output_dir', 'var'), output_dir = ''; end
if ~exist('param_file', 'var'), param_file = ''; end
if ~exist('scenario_index', 'var'), scenario_index = []; end
[Data, output_dir] = load_figure_data(result_file, output_dir, ...
    param_file, '04_security', scenario_index);

S = Data.Security;
D = Data.D;
if exist('typical_day_index', 'var') && ~isempty(typical_day_index)
    day_indices = typical_day_index;
else
    day_indices = 1:D;
end
max_scc_err = max(S.SCCRelativeErrorPct(:), [], 'omitnan');
max_scr_err = max(S.SCRRelativeErrorPct(:), [], 'omitnan');

% 矩阵按[安全节点,典型日]保存；导出与绘图时按典型日逐块展开。
scc_day = reshape(repelem(day_indices(:),numel(S.SCCNodes)), [], 1);
scc_bus = repmat(S.SCCNodes,numel(day_indices),1);
scc_optimization = S.SCCOptimization(:,day_indices); scc_optimization = scc_optimization(:);
scc_exact = S.SCCExact(:,day_indices); scc_exact = scc_exact(:);
scc_limit = S.SCCLimit(:,day_indices); scc_limit = scc_limit(:);
scc_margin = S.SCCMargin(:,day_indices); scc_margin = scc_margin(:);
scc_error = S.SCCRelativeErrorPct(:,day_indices); scc_error = scc_error(:);
scc_labels = compose('D%d-B%d',scc_day,scc_bus);

scr_day = reshape(repelem(day_indices(:),numel(S.SCRNodes)), [], 1);
scr_bus = repmat(S.SCRNodes,numel(day_indices),1);
scr_optimization = S.SCROptimization(:,day_indices); scr_optimization = scr_optimization(:);
scr_exact = S.SCRExact(:,day_indices); scr_exact = scr_exact(:);
scr_limit = S.SCRLimit(:,day_indices); scr_limit = scr_limit(:);
scr_margin = S.SCRMargin(:,day_indices); scr_margin = scr_margin(:);
scr_error = S.SCRRelativeErrorPct(:,day_indices); scr_error = scr_error(:);
scr_labels = compose('D%d-B%d',scr_day,scr_bus);

fig = new_figure([9.0 5.0]); ax = axes(fig);
x = 1:numel(scc_bus);
b = bar(ax, x, [scc_optimization scc_exact], 0.72, ...
    'EdgeColor', 'k', 'LineWidth', 0.7);
b(1).FaceColor = [0.34 0.54 0.72];
b(2).FaceColor = [0.78 0.55 0.25];
hold(ax, 'on');
p = plot(ax, x, scc_limit, 'k-d', 'LineWidth', 1.2, ...
    'MarkerFaceColor', 'w', 'MarkerSize', 5);
[min_margin, min_idx] = min(scc_margin);
plot(ax, min_idx, scc_exact(min_idx), 'ko', 'MarkerSize', 9, 'LineWidth', 1.2);
text(ax, min_idx, scc_exact(min_idx), sprintf('  min margin %.3f kA', min_margin), ...
    'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'center', ...
    'FontName', 'Times New Roman', 'FontSize', 9);
hold(ax, 'off'); style_sci_axes(ax);
xticks(ax, x); xticklabels(ax, scc_labels);
xlabel(ax, 'Typical day - SCC-constrained bus'); ylabel(ax, 'Short-circuit current (kA)');
title(ax, sprintf(['SCC security in daily aggregated conservative states ', ...
    '(max post-hoc error %.2e%%)'], max_scc_err));
legend(ax, [b(:);p], {'Optimization reconstruction','Post-hoc direct inversion', ...
    'Upper limit'}, 'Location', 'southoutside', 'NumColumns', 3);
save_figure_file(fig, fullfile(output_dir, 'SCC_level_and_limit'));

fig = new_figure([7.5 4.8]); ax = axes(fig);
x = 1:numel(scr_bus);
b = bar(ax, x, [scr_optimization scr_exact], 0.68, ...
    'EdgeColor', 'k', 'LineWidth', 0.7);
b(1).FaceColor = [0.34 0.54 0.72];
b(2).FaceColor = [0.78 0.55 0.25];
hold(ax, 'on');
p = plot(ax, x, scr_limit, 'k-d', 'LineWidth', 1.2, ...
    'MarkerFaceColor', 'w', 'MarkerSize', 5);
[min_margin, min_idx] = min(scr_margin);
plot(ax, min_idx, scr_exact(min_idx), 'ko', 'MarkerSize', 9, 'LineWidth', 1.2);
text(ax, min_idx, scr_exact(min_idx), sprintf('  min margin %.4g', min_margin), ...
    'VerticalAlignment', 'bottom', 'FontName', 'Times New Roman', 'FontSize', 9);
hold(ax, 'off'); style_sci_axes(ax);
xticks(ax, x); xticklabels(ax, scr_labels);
xlabel(ax, 'Typical day - classic-SCR-constrained GFL-WG bus');
ylabel(ax, 'Classic short-circuit ratio (p.u.)');
title(ax, sprintf(['Classic SCR in daily aggregated conservative states ', ...
    '(max post-hoc error %.2e%%)'], max_scr_err));
legend(ax, [b(:);p], {'Optimization reconstruction','Post-hoc direct inversion', ...
    'Lower limit'}, 'Location', 'southoutside', 'NumColumns', 3);
save_figure_file(fig, fullfile(output_dir, 'classic_SCR_level_and_limit'));

fig = new_figure([9.0 6.2]);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = nexttile(tl);
[v,idx] = sort(scc_margin, 'ascend');
bar(ax, 1:numel(v), v, 0.68, 'FaceColor', [0.35 0.54 0.70], 'EdgeColor', 'k');
style_sci_axes(ax); yline(ax, 0, 'k--');
xticks(ax, 1:numel(v)); xticklabels(ax, scc_labels(idx));
xlabel(ax, 'Typical day - bus (tightest first)'); ylabel(ax, 'SCC margin (kA)');
title(ax, 'SCC upper-limit margin: limit - post-hoc value');
ax = nexttile(tl);
[v,idx] = sort(scr_margin, 'ascend');
bar(ax, 1:numel(v), v, 0.68, 'FaceColor', [0.76 0.53 0.24], 'EdgeColor', 'k');
style_sci_axes(ax); yline(ax, 0, 'k--');
xticks(ax, 1:numel(v)); xticklabels(ax, scr_labels(idx));
xlabel(ax, 'Typical day - bus (tightest first)'); ylabel(ax, 'Classic SCR margin (p.u.)');
title(ax, 'Classic SCR lower-limit margin: post-hoc value - limit');
title(tl, 'Security margins in daily aggregated conservative states', ...
    'FontName', 'Times New Roman', 'FontSize', 12);
save_figure_file(fig, fullfile(output_dir, 'security_margin_ranking'));

scc_table = table(scc_day,scc_bus,scc_optimization,scc_exact,scc_limit, ...
    scc_margin,scc_error,'VariableNames', ...
    {'TypicalDay','Bus','Optimization_kA','PostHoc_kA','UpperLimit_kA', ...
    'Margin_kA','RelativeError_pct'});
scr_table = table(scr_day,scr_bus,scr_optimization,scr_exact,scr_limit, ...
    scr_margin,scr_error,'VariableNames', ...
    {'TypicalDay','Bus','OptimizationClassicSCR','PostHocClassicSCR','LowerLimit', ...
    'Margin','RelativeError_pct'});
Report = struct();
Report.SCC = scc_table;
Report.ClassicSCR = scr_table;
Report.Validation = [validation_row('SCC_max_posthoc_relative_error', ...
    max_scc_err, 0.1, 'percent'); ...
    validation_row('classic_SCR_max_posthoc_relative_error', ...
    max_scr_err, 0.1, 'percent'); ...
    validation_row('minimum_SCC_security_margin', min(scc_margin), ...
    0, 'kA', all(scc_margin >= -1e-6)); ...
    validation_row('minimum_classic_SCR_security_margin', min(scr_margin), ...
        0, 'p.u.', all(scr_margin >= -1e-6))];

function fig = new_figure(size_inches)
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', ...
    'Position', [1 1 size_inches], ...
    'CreateFcn', 'set(gcbf,''Visible'',''on'');');
end

function save_figure_file(fig, file_path)
set(fig, 'Color', 'w', 'InvertHardcopy', 'off');
drawnow;
if ~endsWith(file_path, '.fig', 'IgnoreCase', true)
    file_path = [file_path '.fig'];
end
set(fig, 'Visible', 'on');
savefig(fig, file_path);
png_path = strrep(file_path, '.fig', '.png');
if exist('exportgraphics', 'file') ~= 0 || exist('exportgraphics', 'builtin') ~= 0
    exportgraphics(fig, png_path, 'Resolution', 600, 'BackgroundColor', 'white');
else
    set(fig, 'PaperPositionMode', 'auto');
    print(fig, png_path, '-dpng', '-r600');
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
