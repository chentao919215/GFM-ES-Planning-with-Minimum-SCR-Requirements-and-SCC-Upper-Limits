%% 分别生成运行平衡、同步机启停、GFL-WG和储能运行图及表格。
% 以下路径留空时，脚本自动使用最新结果、默认参数文件和默认输出目录。
if ~exist('result_file', 'var'), result_file = ''; end
if ~exist('output_dir', 'var'), output_dir = ''; end
if ~exist('param_file', 'var'), param_file = ''; end
if ~exist('scenario_index', 'var'), scenario_index = []; end
[Data, output_dir] = load_figure_data(result_file, output_dir, ...
    param_file, '02_operation', scenario_index);

R = Data.Result;
colors = lines(max(Data.G, 7));
markers = {'o','s','^','d','v','>','<','p'};
validation = table();
balance_max = zeros(Data.D,1);
cycle_max = zeros(Data.D,1);
curtail_energy = zeros(Data.D,1);
curtail_rate = zeros(Data.D,1);

for d = 1:Data.D
    day = sprintf('D%02d', d);
    sg = squeeze(sum(R.P_G(:,d,:),1));
    gfl = squeeze(sum(R.P_GFL(:,d,:),1));
    dis = squeeze(sum(R.P_GFM_Dis(:,d,:),1));
    ch = squeeze(sum(R.P_GFM_Ch(:,d,:),1));
    load_mw = squeeze(sum(Data.LoadMW(:,d,:),1));
    residual = sg+gfl+dis-load_mw-ch;
    balance_max(d) = max(abs(residual));

    fig = new_figure([8.2 4.8]); ax = axes(fig);
    a = area(ax, Data.TimeCenters, [sg gfl dis], 'LineStyle', '-');
    a(1).FaceColor = [78 121 167]/255;
    a(2).FaceColor = [143 188 143]/255;
    a(3).FaceColor = [242 182 109]/255;
    hold(ax, 'on');
    p = plot(ax, Data.TimeCenters, load_mw+ch, '-o', ...
        'Color', [34 34 34]/255, ...
        'LineWidth', 1.6, 'MarkerSize', 4, 'MarkerFaceColor', 'w');
    hold(ax, 'off'); style_sci_axes(ax);
    xlabel(ax, 'Hour'); ylabel(ax, 'Power (MW)');
    title(ax, sprintf('%s system power balance (max residual %.2e MW)', ...
        day, balance_max(d)));
    legend(ax, [a(:);p], {'Synchronous generation','GFL-WG generation', ...
        'GFM-ES discharge','Load + GFM-ES charging'}, ...
        'Location', 'best', 'NumColumns', 2);
    xlim(ax, [Data.TimeEdges(1), Data.TimeEdges(end)]);
    save_figure_file(fig, fullfile(output_dir, [day '_system_power_balance']));

    fig = new_figure([8.2 4.8]); ax = axes(fig); hold(ax, 'on');
    for g = 1:Data.G
        plot(ax, Data.TimeCenters, squeeze(R.P_G(g,d,:)), ...
            'Color', colors(g,:), 'LineStyle', line_style(g), ...
            'Marker', markers{mod(g-1,numel(markers))+1}, ...
            'MarkerSize', 4, 'LineWidth', 1.25, ...
            'DisplayName', sprintf('G%d (bus %d)', g, Data.GeneratorBuses(g)));
    end
    hold(ax, 'off'); style_sci_axes(ax);
    xlabel(ax, 'Hour'); ylabel(ax, 'Active power (MW)');
    title(ax, sprintf('%s synchronous generator dispatch', day));
    legend(ax, 'Location', 'best', 'NumColumns', min(3,Data.G));
    xlim(ax, [Data.TimeEdges(1), Data.TimeEdges(end)]);
    save_figure_file(fig, fullfile(output_dir, [day '_generator_dispatch']));

    fig = new_figure([8.2 6.5]);
    tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    binary_heatmap(nexttile(tl), Data.TimeEdges, squeeze(R.u_G(:,d,:)), ...
        'Commitment state', Data.GeneratorBuses);
    binary_heatmap(nexttile(tl), Data.TimeEdges, squeeze(R.u_G_Start(:,d,:)), ...
        'Startup action', Data.GeneratorBuses);
    binary_heatmap(nexttile(tl), Data.TimeEdges, squeeze(R.u_G_Stop(:,d,:)), ...
        'Shutdown action', Data.GeneratorBuses);
    title(tl, sprintf('%s synchronous generator UC states', day), ...
        'FontName', 'Times New Roman', 'FontSize', 12);
    save_figure_file(fig, fullfile(output_dir, [day '_generator_UC_heatmap']));

    make_gfl_figure(Data, d, output_dir, day);
    available_energy = sum(sum(squeeze(Data.GFLAvailableMW(:,d,:)),1) .* Data.PeriodHours);
    curtail_energy(d) = sum(sum(squeeze(R.P_GFL_Curt(:,d,:)),1) .* Data.PeriodHours);
    curtail_rate(d) = 100*curtail_energy(d)/max(available_energy, eps);

    cycle_error = make_gfm_figures(Data, d, output_dir, day);
    cycle_max(d) = max(cycle_error, [], 'omitnan');

    validation = [validation; ... %#ok<AGROW>
        validation_row([day '_power_balance_max_abs'], balance_max(d), ...
        max(1e-5, 1e-7*max(load_mw)), 'MW'); ...
        validation_row([day '_SOC_cycle_max_abs'], cycle_max(d), ...
        max(1e-5, 1e-7*max(Data.InstalledEnergyMWh)), 'MWh')];
end

summary = table((1:Data.D).', Data.CONF.TypicalDayWeights_Days(:), ...
    curtail_energy, curtail_rate, balance_max, cycle_max, ...
    'VariableNames', {'TypicalDay','RepresentativeDays','Curtailment_MWh', ...
    'CurtailmentRate_pct','MaxPowerBalanceResidual_MW','MaxSOCCycleError_MWh'});
Report = struct('Summary', summary, 'Validation', validation);

disp('02_operation_已完成绘图');

function make_gfl_figure(Data, d, output_dir, day)
R = Data.Result;
n = numel(Data.GFLBuses);
fig = new_figure([8.2 max(3.8, 3.0*n)]);
tl = tiledlayout(fig, n, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
for k = 1:n
    bus = Data.GFLBuses(k); ax = nexttile(tl);
    available = squeeze(Data.GFLAvailableMW(bus,d,:));
    actual = squeeze(R.P_GFL(bus,d,:));
    curtailed = squeeze(R.P_GFL_Curt(bus,d,:));
    xfill = [Data.TimeCenters, fliplr(Data.TimeCenters)];
    yfill = [actual(:).', fliplr(available(:).')];
    fill(ax, xfill, yfill, [0.82 0.82 0.82], ...
        'EdgeColor', [0.45 0.45 0.45], 'FaceAlpha', 0.75, ...
        'DisplayName', 'Curtailed power');
    hold(ax, 'on');
    plot(ax, Data.TimeCenters, available, 'k--s', 'LineWidth', 1.3, ...
        'MarkerSize', 4, 'DisplayName', 'Available power');
    plot(ax, Data.TimeCenters, actual, 'k-o', 'LineWidth', 1.5, ...
        'MarkerSize', 4, 'MarkerFaceColor', 'w', 'DisplayName', 'Actual power');
    hold(ax, 'off'); style_sci_axes(ax);
    ylabel(ax, 'Power (MW)'); title(ax, sprintf('GFL-WG at bus %d', bus));
    xlim(ax, [Data.TimeEdges(1) Data.TimeEdges(end)]);
    if k == n, xlabel(ax, 'Hour'); end
    legend(ax, 'Location', 'best', 'NumColumns', 3);
end
title(tl, sprintf('%s GFL-WG utilization and curtailment', day), ...
    'FontName', 'Times New Roman', 'FontSize', 12);
save_figure_file(fig, fullfile(output_dir, [day '_GFL_WG_output_curtailment']));
end

function cycle_error = make_gfm_figures(Data, d, output_dir, day)
R = Data.Result; C = Data.CONF;
built = find(Data.BuiltCandidateMask);
cycle_error = NaN(Data.CandidateCount,1);
for kk = 1:numel(built)
    k = built(kk); bus = Data.CandidateBuses(k);
    pmax = Data.InstalledPowerMW(k);
    pdis = squeeze(R.P_GFM_Dis(k,d,:));
    pch = squeeze(R.P_GFM_Ch(k,d,:));
    fig = new_figure([8.2 4.2]); ax = axes(fig); hold(ax, 'on');
    stairs(ax, Data.TimeEdges, [pdis; pdis(end)], '-o', ...
        'Color', [47 93 140]/255, ...
        'LineWidth', 1.4, 'MarkerSize', 4, 'DisplayName', 'Discharge (+)');
    stairs(ax, Data.TimeEdges, -[pch; pch(end)], '--s', ...
        'Color', [180 90 74]/255, ...
        'LineWidth', 1.4, 'MarkerSize', 4, 'DisplayName', 'Charge (-)');
    yline(ax, pmax, ':', 'Color', [74 74 74]/255, 'LineWidth', 1.1, ...
        'DisplayName', 'Rated power bounds');
    yline(ax, -pmax, ':', 'Color', [74 74 74]/255, ...
        'HandleVisibility', 'off', 'LineWidth', 1.1);
    yline(ax, 0, '-', 'Color', [158 158 158]/255, 'HandleVisibility', 'off');
    hold(ax, 'off'); style_sci_axes(ax); xlim(ax, [0 Data.TimeEdges(end)]);
    ylim(ax, 1.08*[-pmax pmax]);
    xlabel(ax, 'Hour'); ylabel(ax, 'Power (MW)');
    title(ax, sprintf('%s GFM-ES power at bus %d', day, bus));
    legend(ax, 'Location', 'best');
    save_figure_file(fig, fullfile(output_dir, ...
        sprintf('%s_gfm_power_bus_%02d', day, bus)));

    initial_energy = C.GFM_Candidate_SOC_Initial(k)*Data.InstalledEnergyMWh(k);
    energy_end = squeeze(R.E_GFM(k,d,:));
    cycle_error(k) = energy_end(end)-initial_energy;
    soc = [initial_energy; energy_end] / Data.InstalledEnergyMWh(k);
    fig = new_figure([8.2 4.2]); ax = axes(fig);
    stairs(ax, Data.TimeEdges, soc, 'k-o', 'LineWidth', 1.5, ...
        'MarkerFaceColor', 'w', 'MarkerSize', 4);
    hold(ax, 'on');
    upper_limit = yline(ax, C.GFM_Candidate_SOC_Max(k), 'k--', ...
        'SOC upper limit');
    lower_limit = yline(ax, C.GFM_Candidate_SOC_Min(k), 'k-.', ...
        'SOC lower limit');
    upper_limit.FontName = 'Times New Roman';
    lower_limit.FontName = 'Times New Roman';
    hold(ax, 'off'); style_sci_axes(ax); xlim(ax, [0 Data.TimeEdges(end)]);
    ylim(ax, [0 1]); xlabel(ax, 'Hour'); ylabel(ax, 'State of charge (p.u.)');
    title(ax, sprintf('%s GFM-ES SOC at bus %d (cycle error %.2e MWh)', ...
        day, bus, cycle_error(k)));
    save_figure_file(fig, fullfile(output_dir, ...
        sprintf('%s_gfm_soc_bus_%02d', day, bus)));

end
end

function binary_heatmap(ax, edges, values, label_text, generator_buses)
draw_interval_heatmap(ax, edges, values, [0.94 0.94 0.94; 0.18 0.36 0.58]);
clim(ax, [-0.5 1.5]);
cb = colorbar(ax, 'Ticks', [0 1], 'TickLabels', {'0','1'});
cb.Label.String = label_text;
yticks(ax, 1:size(values,1));
yticklabels(ax, compose('G%d (B%d)', (1:size(values,1)).', generator_buses));
xlabel(ax, 'Hour'); ylabel(ax, 'Generator'); title(ax, label_text);
end

function draw_interval_heatmap(ax, edges, values, map)
[nrow,ncol] = size(values);
x = repmat(edges, nrow+1, 1);
y = repmat((0.5:1:nrow+0.5).', 1, ncol+1);
c = [values, values(:,end); values(end,:), values(end,end)];
surface(ax, x, y, zeros(size(x)), c, 'FaceColor', 'flat', ...
    'EdgeColor', [1 1 1]*0.82, 'LineWidth', 0.3);
view(ax, 2); axis(ax, 'tight'); set(ax, 'YDir', 'reverse'); colormap(ax, map);
style_sci_axes(ax); grid(ax, 'off');
end

function style = line_style(index)
styles = {'-','--','-.',':'};
style = styles{mod(index-1,numel(styles))+1};
end

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
row = table(string(name), value, abs(value), tolerance, string(unit), ...
    abs(value) <= tolerance, 'VariableNames', ...
    {'Check','Value','AbsoluteValue','Tolerance','Unit','Passed'});
end
