%% 分别生成规划配置、容量和成本分解图及对应表格。
% 以下路径留空时，脚本自动使用最新结果、默认参数文件和默认输出目录。
if ~exist('Result_File', 'var'), Result_File = ''; end
if ~exist('Output_Directory', 'var'), Output_Directory = ''; end
if ~exist('Parameter_File', 'var'), Parameter_File = ''; end
if ~exist('Scenario_Index', 'var'), Scenario_Index = []; end
[Data, Output_Directory] = load_figure_data(Result_File, Output_Directory, ...
    Parameter_File, '01_planning', Scenario_Index);

buses = Data.Candidate_Buses;
modules = Data.Modules_Per_Candidate;

fig = new_figure([7.0 4.2]);
ax = axes(fig);
bar(ax, 1:numel(buses), modules, 0.66, ...
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
save_figure_file(fig, fullfile(Output_Directory, 'GFM_ES_module_allocation'));

fig = new_figure([7.0 6.2]);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile(tl);
bar(ax1, 1:numel(buses), Data.Installed_Power_MW, 0.66, ...
    'FaceColor', [0.28 0.50 0.72], 'EdgeColor', 'k');
style_sci_axes(ax1); ylabel(ax1, 'Power capacity (MW)');
title(ax1, 'Installed GFM-ES power capacity');
xticks(ax1, 1:numel(buses)); xticklabels(ax1, compose('%d', buses));
ax2 = nexttile(tl);
bar(ax2, 1:numel(buses), Data.Installed_Energy_MWh, 0.66, ...
    'FaceColor', [0.72 0.46 0.22], 'EdgeColor', 'k');
style_sci_axes(ax2); ylabel(ax2, 'Energy capacity (MWh)');
xlabel(ax2, 'Candidate bus'); title(ax2, 'Installed GFM-ES energy capacity');
xticks(ax2, 1:numel(buses)); xticklabels(ax2, compose('%d', buses));
save_figure_file(fig, fullfile(Output_Directory, 'GFM_ES_installed_capacity'));

Cost = Data.Cost;
if abs(Cost.Decomposition_Error) > Cost.Tolerance || ...
        abs(Cost.Objective_Error) > Cost.Tolerance
    warning('ver2_5:CostMismatch', ['Cost decomposition mismatch: ', ...
        'sum-total = %.6g, sum-objective = %.6g (tolerance %.6g).'], ...
        Cost.Decomposition_Error, Cost.Objective_Error, Cost.Tolerance);
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
save_figure_file(fig, fullfile(Output_Directory, 'objective_cost_breakdown'));

Planning_Table = table(buses, modules, Data.Installed_Power_MW, ...
    Data.Installed_Energy_MWh, 'VariableNames', ...
    {'CandidateBus','InstalledModules','PowerCapacity_MW','EnergyCapacity_MWh'});
Cost_Table = table(Cost.Names, Cost.Values, Cost.Percent, ...
    'VariableNames', {'Component','AnnualCost','PercentOfTotal'});

Report = struct();
Report.PlanningTable = Planning_Table;
Report.CostTable = Cost_Table;
Report.Validation = [validation_row('cost_decomposition_error', ...
    Cost.Decomposition_Error, Cost.Tolerance, 'absolute annual cost'); ...
    validation_row('cost_objective_error', Cost.Objective_Error, ...
    Cost.Tolerance, 'absolute annual cost')];

disp('01_planning_已完成绘图');

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

function row = validation_row(name, value, tolerance, unit)
row = table(string(name), value, abs(value), tolerance, ...
    string(unit), abs(value) <= tolerance, 'VariableNames', ...
    {'Check','Value','AbsoluteValue','Tolerance','Unit','Passed'});
end
