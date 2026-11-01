function Report = plot_03_line_loading(Options)
%% 分别生成线路负载热力图、线路负载排序图及对应表格。
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
    'figs', 'for_debug', '03_line_loading'), 'Scenario_Index', 1));
Style = figure_style('review');
Style.Visible = Options.Visible;
Style.Close_After_Save = Options.Close_After_Save;
Result_File = Options.Result_File;
Output_Directory = Options.Output_Directory;
Scenario_Index = Options.Scenario_Index;
[Data, Output_Directory] = load_figure_data(Result_File, Output_Directory, ...
    '03_line_loading', Scenario_Index);
Data.Style = Style;

% 线路负载率仅在本脚本计算。
Data.Branch_From = Data.CONF.Branch_From;
Data.Branch_To = Data.CONF.Branch_To;
Line_Limit_MW = Data.CONF.Line_Limit_MW;
assert(numel(Line_Limit_MW) == Data.L, ...
    'LineLoading:DimensionMismatch', '线路限值数量与结果不一致。');
Data.Line_Loading_Pct = abs(Data.Result.P_Line) ./ ...
    reshape(Line_Limit_MW, Data.L, 1, 1) * 100;
Data.Line_Loading_Pct(~isfinite(Data.Line_Loading_Pct)) = NaN;

Max_Day_Loading = zeros(Data.L, Data.D);
validation = table();
for d = 1:Data.D
    day = sprintf('D%02d', d);
    loading = squeeze(Data.Line_Loading_Pct(:, d, :));
    Max_Day_Loading(:, d) = max(loading, [], 2, 'omitnan');

    fig = new_figure(2.54*[9.0 7.0], Data.Style); ax = axes(fig);
    draw_interval_heatmap(ax, Data.Time_Edges, loading, Data.Style.Sequential_Map);
    clim(ax, [0 max(100, ceil(max(loading(:), [], 'omitnan')/10)*10)]);
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

%% 2. 绘制指标图件
fig = new_figure(2.54*[8.2 6.0], Data.Style); ax = axes(fig);
Loading_Map = Data.Style.Sequential_Map;
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
            'FaceColor', Loading_Map(end, :), 'EdgeColor', 'none');
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
    {'Line', 'FromBus', 'ToBus', 'MaximumLoading_pct'});
Max_Table = sortrows(Max_Table, 'MaximumLoading_pct', 'descend');

%% 3. 返回统计与核验结果
Report = struct('MaximumLineLoading', Max_Table, 'Validation', validation);

disp('Line-loading figures saved.');

end

function draw_interval_heatmap(ax, edges, values, map)
%% 按实际时段边界绘制热图，避免非等长时段被等距显示。
[nrow, ncol] = size(values);
x = repmat(edges, nrow+1, 1);
y = repmat((0.5:1:nrow+0.5).', 1, ncol+1);
c = [values, values(:, end); values(end, :), values(end, end)];
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
        if ~mask(i, j)
            continue;
        end

        % 上边界
        if i == 1 || ~mask(i-1, j)
            Boundary_x = [Boundary_x, X_Edges(j), X_Edges(j+1), NaN]; %#ok<AGROW>
            Boundary_y = [Boundary_y, Y_Edges(i), Y_Edges(i), NaN]; %#ok<AGROW>
        end
        % 下边界
        if i == nrow || ~mask(i+1, j)
            Boundary_x = [Boundary_x, X_Edges(j), X_Edges(j+1), NaN]; %#ok<AGROW>
            Boundary_y = [Boundary_y, Y_Edges(i+1), Y_Edges(i+1), NaN]; %#ok<AGROW>
        end
        % 左边界
        if j == 1 || ~mask(i, j-1)
            Boundary_x = [Boundary_x, X_Edges(j), X_Edges(j), NaN]; %#ok<AGROW>
            Boundary_y = [Boundary_y, Y_Edges(i), Y_Edges(i+1), NaN]; %#ok<AGROW>
        end
        % 右边界
        if j == ncol || ~mask(i, j+1)
            Boundary_x = [Boundary_x, X_Edges(j+1), X_Edges(j+1), NaN]; %#ok<AGROW>
            Boundary_y = [Boundary_y, Y_Edges(i), Y_Edges(i+1), NaN]; %#ok<AGROW>
        end
    end
end
end

function row = validation_row(name, value, tolerance, unit, passed)
%% 将一个检查量、容差和单位整理为摘要表的一行。
row = table(string(name), value, abs(value), tolerance, string(unit), ...
    logical(passed), 'VariableNames', ...
    {'Check', 'Value', 'AbsoluteValue', 'Tolerance', 'Unit', 'Passed'});
end
