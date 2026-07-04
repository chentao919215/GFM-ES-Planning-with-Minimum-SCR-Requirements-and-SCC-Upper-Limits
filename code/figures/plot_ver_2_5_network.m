function Report = plot_ver_2_5_network(Data, output_dir)
%% Figures 10--11 and network loading exports.

R = Data.Result;
max_day_loading = zeros(Data.L,Data.D);
validation = table();
for d = 1:Data.D
    day = sprintf('D%02d', d);
    loading = squeeze(Data.LineLoadingPct(:,d,:));
    max_day_loading(:,d) = max(loading, [], 2, 'omitnan');

    fig = new_figure([9.0 7.0]); ax = axes(fig);
    draw_interval_heatmap(ax, Data.TimeEdges, loading, blue_map(128));
    clim(ax, [0 max(100, ceil(max(loading(:),[],'omitnan')/10)*10)]);
    cb = colorbar(ax); cb.Label.String = 'Line loading (%)';
    xlabel(ax, 'Hour'); ylabel(ax, 'Line index');
    title(ax, sprintf('%s line loading ratio', day));
    yticks(ax, 1:2:Data.L);
    hold(ax, 'on');
    [line_idx,time_idx] = find(loading >= 95);
    if ~isempty(line_idx)
        plot(ax, Data.TimeCenters(time_idx), line_idx, 'ks', ...
            'MarkerSize', 4, 'LineWidth', 0.8, 'MarkerFaceColor', 'none');
    end
    hold(ax, 'off');
    export_sci_figure(fig, fullfile(output_dir, [day '_line_loading_heatmap']));

    table_day = array2table([Data.TimeCenters(:), loading.'], ...
        'VariableNames', [{'Hour'}, cellstr(compose('Line_%02d_pct',1:Data.L))]);
    writetable(table_day, fullfile(output_dir, [day '_line_loading.csv']));

    max_overload = max(loading(:), [], 'omitnan')-100;
    validation = [validation; validation_row([day '_max_line_overload'], ...
        max_overload, 1e-5, 'percentage points', max_overload <= 1e-5)]; %#ok<AGROW>
end

max_loading = max(max_day_loading, [], 2, 'omitnan');
[sorted_loading, order] = sort(max_loading, 'descend');
nshow = min(15, Data.L);
idx = order(1:nshow);
labels = compose('L%02d: %d-%d', idx, Data.BranchFrom(idx), Data.BranchTo(idx));

fig = new_figure([8.2 6.0]); ax = axes(fig);
barh(ax, 1:nshow, sorted_loading(1:nshow), 0.68, ...
    'FaceColor', [0.34 0.52 0.70], 'EdgeColor', 'k');
style_sci_axes(ax); set(ax, 'YDir', 'reverse');
yticks(ax, 1:nshow); yticklabels(ax, labels);
xlabel(ax, 'Maximum loading across all typical days (%)');
ylabel(ax, 'Line (from bus-to bus)');
title(ax, sprintf('Top %d congested lines', nshow));
xline(ax, 100, 'k--', '100% limit', 'LineWidth', 1.2, ...
    'LabelVerticalAlignment', 'bottom');
xlim(ax, [0 max(105, 1.08*max(sorted_loading(1:nshow)))]);
for k = 1:nshow
    text(ax, sorted_loading(k)+0.6, k, sprintf('%.1f', sorted_loading(k)), ...
        'VerticalAlignment', 'middle', 'FontName', 'Times New Roman', ...
        'FontSize', 9);
end
export_sci_figure(fig, fullfile(output_dir, 'maximum_line_loading_ranking'));

max_table = table((1:Data.L).', Data.BranchFrom, Data.BranchTo, ...
    max_loading, 'VariableNames', ...
    {'Line','FromBus','ToBus','MaximumLoading_pct'});
max_table = sortrows(max_table, 'MaximumLoading_pct', 'descend');
writetable(max_table, fullfile(output_dir, 'maximum_line_loading.csv'));

Report = struct('MaximumLineLoading', max_table, 'Validation', validation);
end

function draw_interval_heatmap(ax, edges, values, map)
[nrow,ncol] = size(values);
x = repmat(edges, nrow+1, 1);
y = repmat((0.5:1:nrow+0.5).', 1, ncol+1);
c = [values, values(:,end); values(end,:), values(end,end)];
surface(ax, x, y, zeros(size(x)), c, 'FaceColor', 'flat', ...
    'EdgeColor', 'none');
view(ax, 2); axis(ax, 'tight'); set(ax, 'YDir', 'reverse');
colormap(ax, map); style_sci_axes(ax); grid(ax, 'off');
end

function map = blue_map(n)
anchors = [0.96 0.97 0.98; 0.70 0.80 0.88; 0.31 0.53 0.70; 0.12 0.25 0.42];
x = linspace(0,1,size(anchors,1));
xi = linspace(0,1,n);
map = [interp1(x,anchors(:,1),xi).', interp1(x,anchors(:,2),xi).', ...
    interp1(x,anchors(:,3),xi).'];
end

function fig = new_figure(size_inches)
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', ...
    'Position', [1 1 size_inches]);
end

function row = validation_row(name, value, tolerance, unit, passed)
row = table(string(name), value, abs(value), tolerance, string(unit), ...
    logical(passed), 'VariableNames', ...
    {'Check','Value','AbsoluteValue','Tolerance','Unit','Passed'});
end
