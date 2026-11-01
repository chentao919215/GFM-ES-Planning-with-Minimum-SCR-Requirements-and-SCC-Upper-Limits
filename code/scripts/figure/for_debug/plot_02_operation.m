function Report = plot_02_operation(Options)
%% 分别生成运行平衡、同步机启停、GFL-WG和储能运行图及表格。
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
    'figs', 'for_debug', '02_operation'), 'Scenario_Index', 1));
Style = figure_style('review');
Style.Visible = Options.Visible;
Style.Close_After_Save = Options.Close_After_Save;
Result_File = Options.Result_File;
Output_Directory = Options.Output_Directory;
Scenario_Index = Options.Scenario_Index;
[Data, Output_Directory] = load_figure_data(Result_File, Output_Directory, ...
    '02_operation', Scenario_Index);
Data.Style = Style;

%% 2. 绘制当前场景的结果图件
R = Data.Result;
colors = repmat(Style.Colors.Cases, ceil(Data.G/5), 1);
markers = {'o', 's', '^', 'd', 'v', '>', '<', 'p'};
validation = table();
Balance_Max = zeros(Data.D, 1);
Cycle_Max = zeros(Data.D, 1);
Curtail_Energy = zeros(Data.D, 1);
Curtail_Rate = zeros(Data.D, 1);

for d = 1:Data.D
    day = sprintf('D%02d', d);
    sg = squeeze(sum(R.P_G(:, d, :), 1));
    gfl = squeeze(sum(R.P_GFL(:, d, :), 1));
    dis = squeeze(sum(R.P_GFM_Dis(:, d, :), 1));
    ch = squeeze(sum(R.P_GFM_Ch(:, d, :), 1));
    Load_MW = squeeze(sum(Data.Load_MW(:, d, :), 1));
    residual = sg+gfl+dis-Load_MW-ch;
    Balance_Max(d) = max(abs(residual));

    fig = new_figure(2.54*[8.2 4.8], Data.Style); ax = axes(fig);
    a = area(ax, Data.Time_Centers, [sg gfl dis], 'LineStyle', '-');
    a(1).FaceColor = Style.Colors.SG;
    a(2).FaceColor = Style.Colors.GFL;
    a(3).FaceColor = Style.Colors.GFM;
    hold(ax, 'on');
    p = plot(ax, Data.Time_Centers, Load_MW+ch, '-o', ...
        'Color', [34 34 34]/255, ...
        'LineWidth', 1.6, 'MarkerSize', 4, 'MarkerFaceColor', 'w');
    hold(ax, 'off'); style_sci_axes(ax);
    xlabel(ax, 'Hour'); ylabel(ax, 'Power (MW)');
    title(ax, sprintf('%s system power balance (max residual %.2e MW)', ...
        day, Balance_Max(d)));
    legend(ax, [a(:);p], {'Synchronous generation', 'GFL-WG generation', ...
        'GFM-ES discharge', 'Load + GFM-ES charging'}, ...
        'Location', 'best', 'NumColumns', 2);
    xlim(ax, [Data.Time_Edges(1), Data.Time_Edges(end)]);
    save_figure_file(fig, fullfile(Output_Directory, [day '_system_power_balance']));

    fig = new_figure(2.54*[8.2 4.8], Data.Style); ax = axes(fig); hold(ax, 'on');
    for g = 1:Data.G
        plot(ax, Data.Time_Centers, squeeze(R.P_G(g, d, :)), ...
            'Color', colors(g, :), 'LineStyle', line_style(g), ...
            'Marker', markers{mod(g-1, numel(markers))+1}, ...
            'MarkerSize', 4, 'LineWidth', 1.25, ...
            'DisplayName', sprintf('G%d (bus %d)', g, Data.Generator_Buses(g)));
    end
    hold(ax, 'off'); style_sci_axes(ax);
    xlabel(ax, 'Hour'); ylabel(ax, 'Active power (MW)');
    title(ax, sprintf('%s synchronous generator dispatch', day));
    legend(ax, 'Location', 'best', 'NumColumns', min(3, Data.G));
    xlim(ax, [Data.Time_Edges(1), Data.Time_Edges(end)]);
    save_figure_file(fig, fullfile(Output_Directory, [day '_generator_dispatch']));

    fig = new_figure(2.54*[8.2 6.5], Data.Style);
    tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    binary_heatmap(nexttile(tl), Data.Time_Edges, squeeze(R.u_G(:, d, :)), ...
        'Commitment state', Data.Generator_Buses);
    binary_heatmap(nexttile(tl), Data.Time_Edges, squeeze(R.u_G_Start(:, d, :)), ...
        'Startup action', Data.Generator_Buses);
    binary_heatmap(nexttile(tl), Data.Time_Edges, squeeze(R.u_G_Stop(:, d, :)), ...
        'Shutdown action', Data.Generator_Buses);
    title(tl, sprintf('%s synchronous generator UC states', day), ...
        'FontName', 'Times New Roman', 'FontSize', 12);
    save_figure_file(fig, fullfile(Output_Directory, [day '_generator_UC_heatmap']));

    make_gfl_figure(Data, d, Output_Directory, day);
    Available_Energy = sum(sum(squeeze(Data.GFL_Available_MW(:, d, :)), 1) .* Data.Period_Hours);
    Curtail_Energy(d) = sum(sum(squeeze(R.P_GFL_Curt(:, d, :)), 1) .* Data.Period_Hours);
    Curtail_Rate(d) = 100*Curtail_Energy(d)/max(Available_Energy, eps);

    Cycle_Error = make_gfm_figures(Data, d, Output_Directory, day);
    Cycle_Max(d) = max(Cycle_Error, [], 'omitnan');

    validation = [validation; ... %#ok<AGROW>
        validation_row([day '_power_balance_max_abs'], Balance_Max(d), ...
        max(1e-5, 1e-7*max(Load_MW)), 'MW'); ...
        validation_row([day '_SOC_cycle_max_abs'], Cycle_Max(d), ...
        max(1e-5, 1e-7*max(Data.Installed_Energy_MWh)), 'MWh')];
end

summary = table((1:Data.D).', Data.CONF.TypicalDayWeights_Days(:), ...
    Curtail_Energy, Curtail_Rate, Balance_Max, Cycle_Max, ...
    'VariableNames', {'TypicalDay', 'RepresentativeDays', 'Curtailment_MWh', ...
    'CurtailmentRate_pct', 'MaxPowerBalanceResidual_MW', 'MaxSOCCycleError_MWh'});

%% 3. 返回统计与核验结果
Report = struct('Summary', summary, 'Validation', validation);

disp('Operation figures saved.');

end

function make_gfl_figure(Data, d, Output_Directory, day)
%% 绘制各GFL-WG节点的实际出力、可用出力及弃风量。
R = Data.Result;
n = numel(Data.GFL_Buses);
fig = new_figure(2.54*[8.2 max(3.8, 3.0*n)], Data.Style);
tl = tiledlayout(fig, n, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
for k = 1:n
    bus = Data.GFL_Buses(k); ax = nexttile(tl);
    available = squeeze(Data.GFL_Available_MW(bus, d, :));
    actual = squeeze(R.P_GFL(bus, d, :));
    xfill = [Data.Time_Centers, fliplr(Data.Time_Centers)];
    yfill = [actual(:).', fliplr(available(:).')];
    fill(ax, xfill, yfill, [0.82 0.82 0.82], ...
        'EdgeColor', [0.45 0.45 0.45], 'FaceAlpha', 0.75, ...
        'DisplayName', 'Curtailed power');
    hold(ax, 'on');
    plot(ax, Data.Time_Centers, available, 'k--s', 'LineWidth', 1.3, ...
        'MarkerSize', 4, 'DisplayName', 'Available power');
    plot(ax, Data.Time_Centers, actual, '-o', 'Color', Data.Style.Colors.GFL, 'LineWidth', 1.5, ...
        'MarkerSize', 4, 'MarkerFaceColor', 'w', 'DisplayName', 'Actual power');
    hold(ax, 'off'); style_sci_axes(ax);
    ylabel(ax, 'Power (MW)'); title(ax, sprintf('GFL-WG at bus %d', bus));
    xlim(ax, [Data.Time_Edges(1) Data.Time_Edges(end)]);
    if k == n
        xlabel(ax, 'Hour');
    end
    legend(ax, 'Location', 'best', 'NumColumns', 3);
end
title(tl, sprintf('%s GFL-WG utilization and curtailment', day), ...
    'FontName', 'Times New Roman', 'FontSize', 12);
save_figure_file(fig, fullfile(Output_Directory, [day '_GFL_WG_output_curtailment']));
end

function Cycle_Error = make_gfm_figures(Data, d, Output_Directory, day)
%% 按已投建设备节点绘制充放电功率和能量状态。
R = Data.Result; C = Data.CONF;
built = find(Data.Built_Candidate_Mask);
Cycle_Error = NaN(Data.Candidate_Count, 1);
for kk = 1:numel(built)
    k = built(kk); bus = Data.Candidate_Buses(k);
    pmax = Data.Installed_Power_MW(k);
    pdis = squeeze(R.P_GFM_Dis(k, d, :));
    pch = squeeze(R.P_GFM_Ch(k, d, :));
    fig = new_figure(2.54*[8.2 4.2], Data.Style); ax = axes(fig); hold(ax, 'on');
    stairs(ax, Data.Time_Edges, [pdis; pdis(end)], '-o', ...
        'Color', Data.Style.Colors.GFM, ...
        'LineWidth', 1.4, 'MarkerSize', 4, 'DisplayName', 'Discharge (+)');
    stairs(ax, Data.Time_Edges, -[pch; pch(end)], '--s', ...
        'Color', 0.68*Data.Style.Colors.GFM, ...
        'LineWidth', 1.4, 'MarkerSize', 4, 'DisplayName', 'Charge (-)');
    yline(ax, pmax, ':', 'Color', [74 74 74]/255, 'LineWidth', 1.1, ...
        'DisplayName', 'Rated power bounds');
    yline(ax, -pmax, ':', 'Color', [74 74 74]/255, ...
        'HandleVisibility', 'off', 'LineWidth', 1.1);
    yline(ax, 0, '-', 'Color', [158 158 158]/255, 'HandleVisibility', 'off');
    hold(ax, 'off'); style_sci_axes(ax); xlim(ax, [0 Data.Time_Edges(end)]);
    ylim(ax, 1.08*[-pmax pmax]);
    xlabel(ax, 'Hour'); ylabel(ax, 'Power (MW)');
    title(ax, sprintf('%s GFM-ES power at bus %d', day, bus));
    legend(ax, 'Location', 'best');
    save_figure_file(fig, fullfile(Output_Directory, ...
        sprintf('%s_gfm_power_bus_%02d', day, bus)));

    Initial_Energy = C.GFM_Candidate_SOC_Initial(k)*Data.Installed_Energy_MWh(k);
    Energy_End = squeeze(R.E_GFM(k, d, :));
    Cycle_Error(k) = Energy_End(end)-Initial_Energy;
    soc = [Initial_Energy; Energy_End] / Data.Installed_Energy_MWh(k);
    fig = new_figure(2.54*[8.2 4.2], Data.Style); ax = axes(fig);
    stairs(ax, Data.Time_Edges, soc, '-o', 'Color', Data.Style.Colors.GFM, 'LineWidth', 1.5, ...
        'MarkerFaceColor', 'w', 'MarkerSize', 4);
    hold(ax, 'on');
    Upper_Limit = yline(ax, C.GFM_Candidate_SOC_Max(k), 'k--', ...
        'SOC upper limit');
    Lower_Limit = yline(ax, C.GFM_Candidate_SOC_Min(k), 'k-.', ...
        'SOC lower limit');
    Upper_Limit.FontName = 'Times New Roman';
    Lower_Limit.FontName = 'Times New Roman';
    hold(ax, 'off'); style_sci_axes(ax); xlim(ax, [0 Data.Time_Edges(end)]);
    ylim(ax, [0 1]); xlabel(ax, 'Hour'); ylabel(ax, 'State of charge (p.u.)');
    title(ax, sprintf('%s GFM-ES SOC at bus %d (cycle error %.2e MWh)', ...
        day, bus, Cycle_Error(k)));
    save_figure_file(fig, fullfile(Output_Directory, ...
        sprintf('%s_gfm_soc_bus_%02d', day, bus)));

end
end

function binary_heatmap(ax, edges, values, Label_Text, Generator_Buses)
%% 用两种状态色绘制共享时间边界的二进制状态图。
S = figure_style('review');
draw_interval_heatmap(ax, edges, values, [S.Colors.Offline;S.Colors.Online]);
clim(ax, [-0.5 1.5]);
cb = colorbar(ax, 'Ticks', [0 1], 'TickLabels', {'0', '1'});
cb.Label.String = Label_Text;
yticks(ax, 1:size(values, 1));
yticklabels(ax, compose('G%d (B%d)', (1:size(values, 1)).', Generator_Buses));
xlabel(ax, 'Hour'); ylabel(ax, 'Generator'); title(ax, Label_Text);
end

function draw_interval_heatmap(ax, edges, values, map)
%% 按实际时段边界绘制热图，避免非等长时段被等距显示。
[nrow, ncol] = size(values);
x = repmat(edges, nrow+1, 1);
y = repmat((0.5:1:nrow+0.5).', 1, ncol+1);
c = [values, values(:, end); values(end, :), values(end, end)];
surface(ax, x, y, zeros(size(x)), c, 'FaceColor', 'flat', ...
    'EdgeColor', [1 1 1]*0.82, 'LineWidth', 0.3);
view(ax, 2); axis(ax, 'tight'); set(ax, 'YDir', 'reverse'); colormap(ax, map);
style_sci_axes(ax); grid(ax, 'off');
end

function style = line_style(index)
%% 按序号循环选取可区分的曲线线型。
styles = {'-', '--', '-.', ':'};
style = styles{mod(index-1, numel(styles))+1};
end

function row = validation_row(name, value, tolerance, unit)
%% 将一个检查量、容差和单位整理为摘要表的一行。
row = table(string(name), value, abs(value), tolerance, string(unit), ...
    abs(value) <= tolerance, 'VariableNames', ...
    {'Check', 'Value', 'AbsoluteValue', 'Tolerance', 'Unit', 'Passed'});
end
