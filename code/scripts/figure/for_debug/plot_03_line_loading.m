%% 分别生成线路负载热力图、线路负载排序图及对应表格。
% 以下路径留空时，脚本自动使用最新结果、默认参数文件和默认输出目录。
if ~exist('result_file', 'var'), Result_File = ''; end
if ~exist('output_dir', 'var'), Output_Directory = ''; end
if ~exist('param_file', 'var'), Parameter_File = ''; end
if ~exist('scenario_index', 'var'), Scenario_Index = []; end
[Data, Output_Directory] = load_figure_data(Result_File, Output_Directory, ...
    Parameter_File, '03_line_loading', Scenario_Index);

Max_Day_Loading = zeros(Data.L,Data.D);
validation = table();
for d = 1:Data.D
    day = sprintf('D%02d', d);
    loading = squeeze(Data.Line_Loading_Pct(:,d,:));
    Max_Day_Loading(:,d) = max(loading, [], 2, 'omitnan');

    fig = new_figure([9.0 7.0]); ax = axes(fig);
    draw_interval_heatmap(ax, Data.Time_Edges, loading, line_loading_map(128));
    clim(ax, [0 max(100, ceil(max(loading(:),[],'omitnan')/10)*10)]);
    cb = colorbar(ax); cb.Label.String = 'Line loading (%)';
    xlabel(ax, 'Hour'); ylabel(ax, 'Line index');
    title(ax, sprintf('%s line loading ratio', day));
    yticks(ax, 1:2:Data.L);
    hold(ax, 'on');
    Full_Loading_Mask = double(loading >= 99.5);
    if any(Full_Loading_Mask(:))
        [Boundary_x, Boundary_y] = grid_mask_boundary( ...
            Full_Loading_Mask, Data.Time_Edges);
        line(ax, Boundary_x, Boundary_y, ...
            'Color', [0.25 0.25 0.25], 'LineWidth', 0.7);
    end
    hold(ax, 'off');
    save_figure_file(fig, fullfile(Output_Directory, [day '_line_loading_heatmap.fig']));

    Max_Overload = max(loading(:), [], 'omitnan')-100;
    validation = [validation; validation_row([day '_max_line_overload'], ...
        Max_Overload, 1e-5, 'percentage points', Max_Overload <= 1e-5)];
end

Max_Loading = max(Max_Day_Loading, [], 2, 'omitnan');
[Sorted_Loading, order] = sort(Max_Loading, 'descend');
nshow = min(15, Data.L);
idx = order(1:nshow);
labels = compose('L%02d: %d-%d', idx, Data.Branch_From(idx), Data.Branch_To(idx));

fig = new_figure([8.2 6.0]); ax = axes(fig);
Loading_Map = line_loading_map(128);
colormap(ax, Loading_Map);
clim(ax, [0 100]);
style_sci_axes(ax); set(ax, 'YDir', 'reverse');
ax.Layer = 'bottom';

Bar_Height = 0.30;
for k = 1:nshow
    value = Sorted_Loading(k);
    Gradient_End = min(max(value, 0), 100);

    % 每条柱子只绘制其实际负载率对应的色带前段，统一按0--100%映射。
    if Gradient_End > 0
        Gradient_Values = linspace(0, Gradient_End, 256);
        image(ax, 'XData', [0 Gradient_End], ...
            'YData', [k-Bar_Height/2 k+Bar_Height/2], ...
            'CData', repmat(Gradient_Values, 2, 1), ...
            'CDataMapping', 'scaled');
    end

    % 超过100%的部分使用色带末端颜色，避免突破0--100%的颜色归一化。
    if value > 100
        rectangle(ax, 'Position', [100, k-Bar_Height/2, value-100, Bar_Height], ...
            'FaceColor', Loading_Map(end,:), 'EdgeColor', 'none');
    end

    rectangle(ax, 'Position', [0, k-Bar_Height, value, Bar_Height*2], ...
        'FaceColor', 'none', 'EdgeColor', 'k', 'LineWidth', 0.8);
end

yticks(ax, 1:nshow); yticklabels(ax, labels);
xlabel(ax, 'Maximum loading across all typical days (%)');
ylabel(ax, 'Line (from bus-to bus)');
title(ax, sprintf('Top %d congested lines', nshow));
Limit_Line = xline(ax, 100, 'k--', '100% limit', 'LineWidth', 1.2, ...
    'LabelVerticalAlignment', 'bottom');
Limit_Line.FontName = 'Times New Roman';
cb = colorbar(ax);
cb.Label.String = 'Maximum loading (%)';
xlim(ax, [0 max(105, 1.08*max(Sorted_Loading(1:nshow)))]);
for k = 1:nshow
    text(ax, Sorted_Loading(k)+0.6, k, sprintf('%.1f', Sorted_Loading(k)), ...
        'VerticalAlignment', 'middle', 'FontName', 'Times New Roman', ...
        'FontSize', 9);
end
save_figure_file(fig, fullfile(Output_Directory, 'maximum_line_loading_ranking.fig'));

Max_Table = table((1:Data.L).', Data.Branch_From, Data.Branch_To, ...
    Max_Loading, 'VariableNames', ...
    {'Line','FromBus','ToBus','MaximumLoading_pct'});
Max_Table = sortrows(Max_Table, 'MaximumLoading_pct', 'descend');

Report = struct('MaximumLineLoading', Max_Table, 'Validation', validation);

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

function [Boundary_x, Boundary_y] = grid_mask_boundary(mask, X_Edges)
% 按热力图网格边界提取满载区域的外轮廓，不连接单元格中心。
[nrow, ncol] = size(mask);
Y_Edges = 0.5:1:nrow+0.5;
Boundary_x = [];
Boundary_y = [];

for i = 1:nrow
    for j = 1:ncol
        if ~mask(i,j)
            continue;
        end

        % 上边界
        if i == 1 || ~mask(i-1,j)
            Boundary_x = [Boundary_x, X_Edges(j), X_Edges(j+1), NaN]; %#ok<AGROW>
            Boundary_y = [Boundary_y, Y_Edges(i), Y_Edges(i), NaN]; %#ok<AGROW>
        end
        % 下边界
        if i == nrow || ~mask(i+1,j)
            Boundary_x = [Boundary_x, X_Edges(j), X_Edges(j+1), NaN]; %#ok<AGROW>
            Boundary_y = [Boundary_y, Y_Edges(i+1), Y_Edges(i+1), NaN]; %#ok<AGROW>
        end
        % 左边界
        if j == 1 || ~mask(i,j-1)
            Boundary_x = [Boundary_x, X_Edges(j), X_Edges(j), NaN]; %#ok<AGROW>
            Boundary_y = [Boundary_y, Y_Edges(i), Y_Edges(i+1), NaN]; %#ok<AGROW>
        end
        % 右边界
        if j == ncol || ~mask(i,j+1)
            Boundary_x = [Boundary_x, X_Edges(j+1), X_Edges(j+1), NaN]; %#ok<AGROW>
            Boundary_y = [Boundary_y, Y_Edges(i), Y_Edges(i+1), NaN]; %#ok<AGROW>
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

function save_figure_file(fig, File_Path)
set(fig, 'Color', 'w', 'InvertHardcopy', 'off');
drawnow;
set(fig, 'Visible', 'on');
savefig(fig, File_Path);
set(fig, 'Visible', 'off');
Png_Path = strrep(File_Path, '.fig', '.png');
exportgraphics(fig, Png_Path, 'Resolution', 600, ...
    'BackgroundColor', 'white');
close(fig);
end

function fig = new_figure(Size_Inches)
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', ...
    'Position', [1 1 Size_Inches]);
end

function row = validation_row(name, value, tolerance, unit, passed)
row = table(string(name), value, abs(value), tolerance, string(unit), ...
    logical(passed), 'VariableNames', ...
    {'Check','Value','AbsoluteValue','Tolerance','Unit','Passed'});
end
