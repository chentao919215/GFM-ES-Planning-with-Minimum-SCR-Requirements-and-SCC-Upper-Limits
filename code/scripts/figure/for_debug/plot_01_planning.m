%% 分别生成规划配置、容量和成本分解图及对应表格。
% 以下路径留空时，脚本自动使用最新结果、默认参数文件和默认输出目录。
if ~exist('result_file', 'var'), result_file = ''; end
if ~exist('output_dir', 'var'), output_dir = ''; end
if ~exist('param_file', 'var'), param_file = ''; end
if ~exist('scenario_index', 'var'), scenario_index = []; end
[Data, output_dir] = load_figure_data(result_file, output_dir, ...
    param_file, '01_planning', scenario_index);

buses = Data.CandidateBuses;
modules = Data.ModulesPerCandidate;

fig = new_figure([7.0 4.2]);
ax = axes(fig);
b = bar(ax, 1:numel(buses), modules, 0.66, ...
    'FaceColor', [0.30 0.48 0.68], 'EdgeColor', 'k', 'LineWidth', 0.8);
style_sci_axes(ax);
xticks(ax, 1:numel(buses)); xticklabels(ax, compose('%d', buses));
xlabel(ax, 'Candidate bus'); ylabel(ax, 'Installed module count');
title(ax, 'GFM-ES module allocation');
ylim(ax, [0, max(1, max(modules)+0.35)]);
for k = find(modules(:).' > 0)
    text(ax, k, modules(k)+0.05, sprintf('%d', round(modules(k))), ...
        'HorizontalAlignment', 'center', 'FontName', 'Times New Roman', ...
        'FontSize', 10, 'FontWeight', 'bold');
end
save_figure_file(fig, fullfile(output_dir, 'GFM_ES_module_allocation'));

fig = new_figure([7.0 6.2]);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile(tl);
bar(ax1, 1:numel(buses), Data.InstalledPowerMW, 0.66, ...
    'FaceColor', [0.28 0.50 0.72], 'EdgeColor', 'k');
style_sci_axes(ax1); ylabel(ax1, 'Power capacity (MW)');
title(ax1, 'Installed GFM-ES power capacity');
xticks(ax1, 1:numel(buses)); xticklabels(ax1, compose('%d', buses));
ax2 = nexttile(tl);
bar(ax2, 1:numel(buses), Data.InstalledEnergyMWh, 0.66, ...
    'FaceColor', [0.72 0.46 0.22], 'EdgeColor', 'k');
style_sci_axes(ax2); ylabel(ax2, 'Energy capacity (MWh)');
xlabel(ax2, 'Candidate bus'); title(ax2, 'Installed GFM-ES energy capacity');
xticks(ax2, 1:numel(buses)); xticklabels(ax2, compose('%d', buses));
save_figure_file(fig, fullfile(output_dir, 'GFM_ES_installed_capacity'));

Cost = Data.Cost;
if abs(Cost.DecompositionError) > Cost.Tolerance || ...
        abs(Cost.ObjectiveError) > Cost.Tolerance
    warning('ver2_5:CostMismatch', ['Cost decomposition mismatch: ', ...
        'sum-total = %.6g, sum-objective = %.6g (tolerance %.6g).'], ...
        Cost.DecompositionError, Cost.ObjectiveError, Cost.Tolerance);
end
fig = new_figure([8.0 4.8]);
ax = axes(fig);
b = bar(ax, Cost.Values/1e6, 0.68, 'FaceColor', 'flat', ...
    'EdgeColor', 'k', 'LineWidth', 0.8);
b.CData = [0.22 0.42 0.64; 0.73 0.47 0.18; 0.48 0.60 0.36; ...
    0.55 0.45 0.60; 0.75 0.75 0.75];
style_sci_axes(ax);
xticks(ax, 1:numel(Cost.Names)); xticklabels(ax, Cost.Names);
xtickangle(ax, 18); ylabel(ax, 'Annual cost (million $)');
title(ax, 'Annual objective cost breakdown');
for k = 1:numel(Cost.Values)
    text(ax, k, Cost.Values(k)/1e6, ...
        sprintf('%.3f (%.1f%%)', Cost.Values(k)/1e6, Cost.Percent(k)), ...
        'Rotation', 0, 'VerticalAlignment', 'bottom', ...
        'HorizontalAlignment', 'center', 'FontName', 'Times New Roman', ...
        'FontSize', 9);
end
ylim(ax, [0, max(Cost.Values/1e6)*1.35+eps]);
save_figure_file(fig, fullfile(output_dir, 'objective_cost_breakdown'));

planning_table = table(buses, modules, Data.InstalledPowerMW, ...
    Data.InstalledEnergyMWh, 'VariableNames', ...
    {'CandidateBus','InstalledModules','PowerCapacity_MW','EnergyCapacity_MWh'});
cost_table = table(Cost.Names, Cost.Values, Cost.Percent, ...
    'VariableNames', {'Component','AnnualCost','PercentOfTotal'});

Report = struct();
Report.PlanningTable = planning_table;
Report.CostTable = cost_table;
Report.Validation = [validation_row('cost_decomposition_error', ...
    Cost.DecompositionError, Cost.Tolerance, 'absolute annual cost'); ...
    validation_row('cost_objective_error', Cost.ObjectiveError, ...
    Cost.Tolerance, 'absolute annual cost')];

disp('01_planning_已完成绘图');

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

function row = validation_row(name, value, tolerance, unit)
row = table(string(name), value, abs(value), tolerance, ...
    string(unit), abs(value) <= tolerance, 'VariableNames', ...
    {'Check','Value','AbsoluteValue','Tolerance','Unit','Passed'});
end
