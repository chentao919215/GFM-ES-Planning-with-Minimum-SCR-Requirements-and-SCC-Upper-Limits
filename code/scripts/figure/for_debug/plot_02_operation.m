%% 分别生成运行平衡、同步机启停、GFL-WG和储能运行图及表格。
% 以下路径留空时，脚本自动使用最新结果、默认参数文件和默认输出目录。
if ~exist('Result_File', 'var'), Result_File = ''; end
if ~exist('Output_Directory', 'var'), Output_Directory = ''; end
if ~exist('Parameter_File', 'var'), Parameter_File = ''; end
if ~exist('Scenario_Index', 'var'), Scenario_Index = []; end
[Data, Output_Directory] = load_figure_data(Result_File, Output_Directory, ...
    Parameter_File, '02_operation', Scenario_Index);

R = Data.Result;
colors = lines(max(Data.G, 7));
markers = {'o','s','^','d','v','>','<','p'};
validation = table();
Balance_Max = zeros(Data.D,1);
Cycle_Max = zeros(Data.D,1);
Curtail_Energy = zeros(Data.D,1);
Curtail_Rate = zeros(Data.D,1);

for d = 1:Data.D
    day = sprintf('D%02d', d);
    sg = squeeze(sum(R.P_G(:,d,:),1));
    gfl = squeeze(sum(R.P_GFL(:,d,:),1));
    dis = squeeze(sum(R.P_GFM_Dis(:,d,:),1));
    ch = squeeze(sum(R.P_GFM_Ch(:,d,:),1));
    Load_MW = squeeze(sum(Data.Load_MW(:,d,:),1));
    residual = sg+gfl+dis-Load_MW-ch;
    Balance_Max(d) = max(abs(residual));

    fig = new_figure([8.2 4.8]); ax = axes(fig);
    a = area(ax, Data.Time_Centers, [sg gfl dis], 'LineStyle', '-');
    a(1).FaceColor = [78 121 167]/255;
    a(2).FaceColor = [143 188 143]/255;
    a(3).FaceColor = [242 182 109]/255;
    hold(ax, 'on');
    p = plot(ax, Data.Time_Centers, Load_MW+ch, '-o', ...
        'Color', [34 34 34]/255, ...
        'LineWidth', 1.6, 'MarkerSize', 4, 'MarkerFaceColor', 'w');
    hold(ax, 'off'); style_sci_axes(ax);
    xlabel(ax, 'Hour'); ylabel(ax, 'Power (MW)');
    title(ax, sprintf('%s system power balance (max residual %.2e MW)', ...
        day, Balance_Max(d)));
    legend(ax, [a(:);p], {'Synchronous generation','GFL-WG generation', ...
        'GFM-ES discharge','Load + GFM-ES charging'}, ...
        'Location', 'best', 'NumColumns', 2);
    xlim(ax, [Data.Time_Edges(1), Data.Time_Edges(end)]);
    save_figure_file(fig, fullfile(Output_Directory, [day '_system_power_balance']));

    fig = new_figure([8.2 4.8]); ax = axes(fig); hold(ax, 'on');
    for g = 1:Data.G
        plot(ax, Data.Time_Centers, squeeze(R.P_G(g,d,:)), ...
            'Color', colors(g,:), 'LineStyle', line_style(g), ...
            'Marker', markers{mod(g-1,numel(markers))+1}, ...
            'MarkerSize', 4, 'LineWidth', 1.25, ...
            'DisplayName', sprintf('G%d (bus %d)', g, Data.Generator_Buses(g)));
    end
    hold(ax, 'off'); style_sci_axes(ax);
    xlabel(ax, 'Hour'); ylabel(ax, 'Active power (MW)');
    title(ax, sprintf('%s synchronous generator dispatch', day));
    legend(ax, 'Location', 'best', 'NumColumns', min(3,Data.G));
    xlim(ax, [Data.Time_Edges(1), Data.Time_Edges(end)]);
    save_figure_file(fig, fullfile(Output_Directory, [day '_generator_dispatch']));

    fig = new_figure([8.2 6.5]);
    tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    binary_heatmap(nexttile(tl), Data.Time_Edges, squeeze(R.u_G(:,d,:)), ...
        'Commitment state', Data.Generator_Buses);
    binary_heatmap(nexttile(tl), Data.Time_Edges, squeeze(R.u_G_Start(:,d,:)), ...
        'Startup action', Data.Generator_Buses);
    binary_heatmap(nexttile(tl), Data.Time_Edges, squeeze(R.u_G_Stop(:,d,:)), ...
        'Shutdown action', Data.Generator_Buses);
    title(tl, sprintf('%s synchronous generator UC states', day), ...
        'FontName', 'Times New Roman', 'FontSize', 12);
    save_figure_file(fig, fullfile(Output_Directory, [day '_generator_UC_heatmap']));

    make_gfl_figure(Data, d, Output_Directory, day);
    Available_Energy = sum(sum(squeeze(Data.GFL_Available_MW(:,d,:)),1) .* Data.Period_Hours);
    Curtail_Energy(d) = sum(sum(squeeze(R.P_GFL_Curt(:,d,:)),1) .* Data.Period_Hours);
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
    'VariableNames', {'TypicalDay','RepresentativeDays','Curtailment_MWh', ...
    'CurtailmentRate_pct','MaxPowerBalanceResidual_MW','MaxSOCCycleError_MWh'});
Report = struct('Summary', summary, 'Validation', validation);

disp('02_operation_已完成绘图');

function make_gfl_figure(Data, d, Output_Directory, day)
R = Data.Result;
n = numel(Data.GFL_Buses);
fig = new_figure([8.2 max(3.8, 3.0*n)]);
tl = tiledlayout(fig, n, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
for k = 1:n
    bus = Data.GFL_Buses(k); ax = nexttile(tl);
    available = squeeze(Data.GFL_Available_MW(bus,d,:));
    actual = squeeze(R.P_GFL(bus,d,:));
    xfill = [Data.Time_Centers, fliplr(Data.Time_Centers)];
    yfill = [actual(:).', fliplr(available(:).')];
    fill(ax, xfill, yfill, [0.82 0.82 0.82], ...
        'EdgeColor', [0.45 0.45 0.45], 'FaceAlpha', 0.75, ...
        'DisplayName', 'Curtailed power');
    hold(ax, 'on');
    plot(ax, Data.Time_Centers, available, 'k--s', 'LineWidth', 1.3, ...
        'MarkerSize', 4, 'DisplayName', 'Available power');
    plot(ax, Data.Time_Centers, actual, 'k-o', 'LineWidth', 1.5, ...
        'MarkerSize', 4, 'MarkerFaceColor', 'w', 'DisplayName', 'Actual power');
    hold(ax, 'off'); style_sci_axes(ax);
    ylabel(ax, 'Power (MW)'); title(ax, sprintf('GFL-WG at bus %d', bus));
    xlim(ax, [Data.Time_Edges(1) Data.Time_Edges(end)]);
    if k == n, xlabel(ax, 'Hour'); end
    legend(ax, 'Location', 'best', 'NumColumns', 3);
end
title(tl, sprintf('%s GFL-WG utilization and curtailment', day), ...
    'FontName', 'Times New Roman', 'FontSize', 12);
save_figure_file(fig, fullfile(Output_Directory, [day '_GFL_WG_output_curtailment']));
end

function Cycle_Error = make_gfm_figures(Data, d, Output_Directory, day)
R = Data.Result; C = Data.CONF;
built = find(Data.Built_Candidate_Mask);
Cycle_Error = NaN(Data.Candidate_Count,1);
for kk = 1:numel(built)
    k = built(kk); bus = Data.Candidate_Buses(k);
    pmax = Data.Installed_Power_MW(k);
    pdis = squeeze(R.P_GFM_Dis(k,d,:));
    pch = squeeze(R.P_GFM_Ch(k,d,:));
    fig = new_figure([8.2 4.2]); ax = axes(fig); hold(ax, 'on');
    stairs(ax, Data.Time_Edges, [pdis; pdis(end)], '-o', ...
        'Color', [47 93 140]/255, ...
        'LineWidth', 1.4, 'MarkerSize', 4, 'DisplayName', 'Discharge (+)');
    stairs(ax, Data.Time_Edges, -[pch; pch(end)], '--s', ...
        'Color', [180 90 74]/255, ...
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
    Energy_End = squeeze(R.E_GFM(k,d,:));
    Cycle_Error(k) = Energy_End(end)-Initial_Energy;
    soc = [Initial_Energy; Energy_End] / Data.Installed_Energy_MWh(k);
    fig = new_figure([8.2 4.2]); ax = axes(fig);
    stairs(ax, Data.Time_Edges, soc, 'k-o', 'LineWidth', 1.5, ...
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
draw_interval_heatmap(ax, edges, values, [0.94 0.94 0.94; 0.18 0.36 0.58]);
clim(ax, [-0.5 1.5]);
cb = colorbar(ax, 'Ticks', [0 1], 'TickLabels', {'0','1'});
cb.Label.String = Label_Text;
yticks(ax, 1:size(values,1));
yticklabels(ax, compose('G%d (B%d)', (1:size(values,1)).', Generator_Buses));
xlabel(ax, 'Hour'); ylabel(ax, 'Generator'); title(ax, Label_Text);
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
row = table(string(name), value, abs(value), tolerance, string(unit), ...
    abs(value) <= tolerance, 'VariableNames', ...
    {'Check','Value','AbsoluteValue','Tolerance','Unit','Passed'});
end
