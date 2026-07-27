%% 分别生成线路负载热力图、线路负载排序图及对应表格。
% 以下路径留空时，脚本自动使用最新结果、默认参数文件和默认输出目录。
if ~exist('result_file', 'var'), result_file = ''; end
if ~exist('output_dir', 'var'), output_dir = ''; end
if ~exist('param_file', 'var'), param_file = ''; end
if ~exist('scenario_index', 'var'), scenario_index = []; end
[Data, output_dir] = load_figure_data(result_file, output_dir, ...
    param_file, '03_line_loading', scenario_index);

max_day_loading = zeros(Data.L,Data.D);
validation = table();
for d = 1:Data.D
    day = sprintf('D%02d', d);
    loading = squeeze(Data.LineLoadingPct(:,d,:));
    max_day_loading(:,d) = max(loading, [], 2, 'omitnan');

    fig = new_figure([9.0 7.0]); ax = axes(fig);
    draw_interval_heatmap(ax, Data.TimeEdges, loading, line_loading_map(128));
    clim(ax, [0 max(100, ceil(max(loading(:),[],'omitnan')/10)*10)]);
    cb = colorbar(ax); cb.Label.String = 'Line loading (%)';
    xlabel(ax, 'Hour'); ylabel(ax, 'Line index');
    title(ax, sprintf('%s line loading ratio', day));
    yticks(ax, 1:2:Data.L);
    hold(ax, 'on');
    full_loading_mask = double(loading >= 99.5);
    if any(full_loading_mask(:))
        [boundary_x, boundary_y] = grid_mask_boundary( ...
            full_loading_mask, Data.TimeEdges);
        line(ax, boundary_x, boundary_y, ...
            'Color', [0.25 0.25 0.25], 'LineWidth', 0.7);
    end
    hold(ax, 'off');
    save_figure_file(fig, fullfile(output_dir, [day '_line_loading_heatmap.fig']));

    max_overload = max(loading(:), [], 'omitnan')-100;
    validation = [validation; validation_row([day '_max_line_overload'], ...
        max_overload, 1e-5, 'percentage points', max_overload <= 1e-5)];
end

max_loading = max(max_day_loading, [], 2, 'omitnan');
[sorted_loading, order] = sort(max_loading, 'descend');
nshow = min(15, Data.L);
idx = order(1:nshow);
labels = compose('L%02d: %d-%d', idx, Data.BranchFrom(idx), Data.BranchTo(idx));

fig = new_figure([8.2 6.0]); ax = axes(fig);
loading_map = line_loading_map(128);
colormap(ax, loading_map);
clim(ax, [0 100]);
style_sci_axes(ax); set(ax, 'YDir', 'reverse');
ax.Layer = 'bottom';

bar_height = 0.30;
for k = 1:nshow
    value = sorted_loading(k);
    gradient_end = min(max(value, 0), 100);

    % 每条柱子只绘制其实际负载率对应的色带前段，统一按0--100%映射。
    if gradient_end > 0
        gradient_values = linspace(0, gradient_end, 256);
        image(ax, 'XData', [0 gradient_end], ...
            'YData', [k-bar_height/2 k+bar_height/2], ...
            'CData', repmat(gradient_values, 2, 1), ...
            'CDataMapping', 'scaled');
    end

    % 超过100%的部分使用色带末端颜色，避免突破0--100%的颜色归一化。
    if value > 100
        rectangle(ax, 'Position', [100, k-bar_height/2, value-100, bar_height], ...
            'FaceColor', loading_map(end,:), 'EdgeColor', 'none');
    end

    rectangle(ax, 'Position', [0, k-bar_height, value, bar_height*2], ...
        'FaceColor', 'none', 'EdgeColor', 'k', 'LineWidth', 0.8);
end

yticks(ax, 1:nshow); yticklabels(ax, labels);
xlabel(ax, 'Maximum loading across all typical days (%)');
ylabel(ax, 'Line (from bus-to bus)');
title(ax, sprintf('Top %d congested lines', nshow));
limit_line = xline(ax, 100, 'k--', '100% limit', 'LineWidth', 1.2, ...
    'LabelVerticalAlignment', 'bottom');
limit_line.FontName = 'Times New Roman';
cb = colorbar(ax);
cb.Label.String = 'Maximum loading (%)';
xlim(ax, [0 max(105, 1.08*max(sorted_loading(1:nshow)))]);
for k = 1:nshow
    text(ax, sorted_loading(k)+0.6, k, sprintf('%.1f', sorted_loading(k)), ...
        'VerticalAlignment', 'middle', 'FontName', 'Times New Roman', ...
        'FontSize', 9);
end
save_figure_file(fig, fullfile(output_dir, 'maximum_line_loading_ranking.fig'));

max_table = table((1:Data.L).', Data.BranchFrom, Data.BranchTo, ...
    max_loading, 'VariableNames', ...
    {'Line','FromBus','ToBus','MaximumLoading_pct'});
max_table = sortrows(max_table, 'MaximumLoading_pct', 'descend');

Report = struct('MaximumLineLoading', max_table, 'Validation', validation);

disp('03_line_loading_已完成绘图');

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

function [boundary_x, boundary_y] = grid_mask_boundary(mask, x_edges)
% 按热力图网格边界提取满载区域的外轮廓，不连接单元格中心。
[nrow, ncol] = size(mask);
y_edges = 0.5:1:nrow+0.5;
boundary_x = [];
boundary_y = [];

for i = 1:nrow
    for j = 1:ncol
        if ~mask(i,j)
            continue;
        end

        % 上边界
        if i == 1 || ~mask(i-1,j)
            boundary_x = [boundary_x, x_edges(j), x_edges(j+1), NaN]; %#ok<AGROW>
            boundary_y = [boundary_y, y_edges(i), y_edges(i), NaN]; %#ok<AGROW>
        end
        % 下边界
        if i == nrow || ~mask(i+1,j)
            boundary_x = [boundary_x, x_edges(j), x_edges(j+1), NaN]; %#ok<AGROW>
            boundary_y = [boundary_y, y_edges(i+1), y_edges(i+1), NaN]; %#ok<AGROW>
        end
        % 左边界
        if j == 1 || ~mask(i,j-1)
            boundary_x = [boundary_x, x_edges(j), x_edges(j), NaN]; %#ok<AGROW>
            boundary_y = [boundary_y, y_edges(i), y_edges(i+1), NaN]; %#ok<AGROW>
        end
        % 右边界
        if j == ncol || ~mask(i,j+1)
            boundary_x = [boundary_x, x_edges(j+1), x_edges(j+1), NaN]; %#ok<AGROW>
            boundary_y = [boundary_y, y_edges(i), y_edges(i+1), NaN]; %#ok<AGROW>
        end
    end
end
end

function map = line_loading_map(n)
% 使用蓝色—浅紫—粉色—红色的连续渐变配色。
anchors = [40 67 125; 70 117 176; 104 146 197; 166 186 223; ...
    231 228 248; 244 220 237; 241 204 222; 234 183 202; ...
    210 121 140; 179 69 87] / 255;
x = linspace(0,1,size(anchors,1));
xi = linspace(0,1,n);
map = [interp1(x,anchors(:,1),xi).', interp1(x,anchors(:,2),xi).', ...
    interp1(x,anchors(:,3),xi).'];
end

function save_figure_file(fig, file_path)
set(fig, 'Color', 'w', 'InvertHardcopy', 'off');
drawnow;
set(fig, 'Visible', 'on');
savefig(fig, file_path);
set(fig, 'Visible', 'off');
png_path = strrep(file_path, '.fig', '.png');
if exist('exportgraphics', 'file') ~= 0 || exist('exportgraphics', 'builtin') ~= 0
    exportgraphics(fig, png_path, 'Resolution', 600, ...
        'BackgroundColor', 'white');
else
    set(fig, 'PaperPositionMode', 'auto');
    print(fig, png_path, '-dpng', '-r600');
end
close(fig);
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
