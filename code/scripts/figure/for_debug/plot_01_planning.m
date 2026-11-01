function Report = plot_01_planning(Options)
%% 分别生成规划配置、容量和成本分解图及对应表格。
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
    'figs', 'for_debug', '01_planning'), 'Scenario_Index', 1));
Style = figure_style('review');
Style.Visible = Options.Visible;
Style.Close_After_Save = Options.Close_After_Save;
Result_File = Options.Result_File;
Output_Directory = Options.Output_Directory;
Scenario_Index = Options.Scenario_Index;
[Data, Output_Directory] = load_figure_data(Result_File, Output_Directory, ...
    '01_planning', Scenario_Index);
Data.Style = Style;

%% 2. 绘制当前场景的结果图件
buses = Data.Candidate_Buses;
units = Data.Units_Per_Candidate;

fig = new_figure(2.54*[7.0 4.2], Data.Style);
ax = axes(fig);
bar(ax, 1:numel(buses), units, 0.66, ...
    'FaceColor', Style.Colors.GFM, 'EdgeColor', 'k', 'LineWidth', 0.8);
style_sci_axes(ax);
xticks(ax, 1:numel(buses)); xticklabels(ax, compose('%d', buses));
xlabel(ax, 'Candidate bus'); ylabel(ax, 'Installed unit count');
title(ax, 'GFM-ES unit allocation');
ylim(ax, [0, max(1, max(units)+0.35)]);
for k = find(units(:).' > 0)
    text(ax, k, units(k)+0.05, sprintf('%d', round(units(k))), ...
        'HorizontalAlignment', 'center', 'FontName', 'Times New Roman', ...
        'FontSize', 10, 'FontWeight', 'bold');
end
save_figure_file(fig, fullfile(Output_Directory, 'GFM_ES_unit_allocation'));

fig = new_figure(2.54*[7.0 6.2], Data.Style);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile(tl);
bar(ax1, 1:numel(buses), Data.Installed_Power_MW, 0.66, ...
    'FaceColor', Style.Colors.GFM, 'EdgeColor', 'k');
style_sci_axes(ax1); ylabel(ax1, 'Power capacity (MW)');
title(ax1, 'Installed GFM-ES power capacity');
xticks(ax1, 1:numel(buses)); xticklabels(ax1, compose('%d', buses));
ax2 = nexttile(tl);
bar(ax2, 1:numel(buses), Data.Installed_Energy_MWh, 0.66, ...
    'FaceColor', 0.68*Style.Colors.GFM, 'EdgeColor', 'k');
style_sci_axes(ax2); ylabel(ax2, 'Energy capacity (MWh)');
xlabel(ax2, 'Candidate bus'); title(ax2, 'Installed GFM-ES energy capacity');
xticks(ax2, 1:numel(buses)); xticklabels(ax2, compose('%d', buses));
save_figure_file(fig, fullfile(Output_Directory, 'GFM_ES_installed_capacity'));

Cost = calculate_cost_breakdown(Data.Result);
if abs(Cost.Decomposition_Error) > Cost.Tolerance || ...
        abs(Cost.Objective_Error) > Cost.Tolerance
    warning('FigurePlanning:CostMismatch', ['Cost decomposition mismatch: ', ...
        'sum-total = %.6g, sum-objective = %.6g (tolerance %.6g).'], ...
        Cost.Decomposition_Error, Cost.Objective_Error, Cost.Tolerance);
end
fig = new_figure(2.54*[8.0 4.8], Data.Style);
ax = axes(fig);
b = bar(ax, Cost.Values/1e6, 0.68, 'FaceColor', 'flat', ...
    'EdgeColor', 'k', 'LineWidth', 0.8);
b.CData = [Style.Colors.SG;Style.Colors.GFM;Style.Colors.GFL;Style.Colors.Periodwise;Style.Colors.Grid];
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

Planning_Table = table(buses, units, Data.Installed_Power_MW, ...
    Data.Installed_Energy_MWh, 'VariableNames', ...
    {'CandidateBus', 'InstalledUnits', 'PowerCapacity_MW', 'EnergyCapacity_MWh'});
Cost_Table = table(Cost.Names, Cost.Values, Cost.Percent, ...
    'VariableNames', {'Component', 'AnnualCost', 'PercentOfTotal'});

%% 3. 返回统计与核验结果
Report = struct();
Report.PlanningTable = Planning_Table;
Report.CostTable = Cost_Table;
Report.Validation = [validation_row('cost_decomposition_error', ...
    Cost.Decomposition_Error, Cost.Tolerance, 'absolute annual cost'); ...
    validation_row('cost_objective_error', Cost.Objective_Error, ...
    Cost.Tolerance, 'absolute annual cost')];

disp('Planning figures saved.');

end

function row = validation_row(name, value, tolerance, unit)
%% 将一个检查量、容差和单位整理为摘要表的一行。
row = table(string(name), value, abs(value), tolerance, ...
    string(unit), abs(value) <= tolerance, 'VariableNames', ...
    {'Check', 'Value', 'AbsoluteValue', 'Tolerance', 'Unit', 'Passed'});
end

function Cost = calculate_cost_breakdown(Result)
%% 按配置快照重算各项年成本，并核验与归档总目标的一致性。
C = Result.CONF;
startup = 0;
shutdown = 0;
for d = 1:C.TypicalDayCount
    for t = 1:C.PeriodCount
        startup = startup + C.TypicalDayWeights_Days(d) * ...
            C.Gen_Startup_Cost(:).' * Result.u_G_Start(:, d, t);
        shutdown = shutdown + C.TypicalDayWeights_Days(d) * ...
            C.Gen_Shutdown_Cost(:).' * Result.u_G_Stop(:, d, t);
    end
end
Cost.Names = ["Operating"; "GFM fixed cost"; "Curtailment"; "Startup"; "Shutdown"];
Cost.Values = [Result.Cost.GEN; Result.Cost.GFM_Fixed; Result.Cost.Curt; startup; shutdown];
Cost.Sum = sum(Cost.Values);
Cost.Reported_Total = Result.Cost.Total;
Cost.Solver_Objective = Result.Diagnostics.objective;
Cost.Percent = 100*Cost.Values/max(abs(Cost.Reported_Total), eps);
Cost.Decomposition_Error = Cost.Sum-Cost.Reported_Total;
Cost.Objective_Error = Cost.Sum-Cost.Solver_Objective;
Cost.Tolerance = max(1, 1e-6*max(abs([Cost.Sum; Cost.Reported_Total; ...
    Cost.Solver_Objective]), [], 'omitnan'));
end
