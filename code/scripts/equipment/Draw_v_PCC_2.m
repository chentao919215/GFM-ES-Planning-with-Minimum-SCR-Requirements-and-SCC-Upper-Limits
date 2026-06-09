%% Draw_v_PCC_Simulink_Fig3410.m
% 数据来源：Simulink 导出到 MATLAB 工作区的 timeseries / SimulationData.Signal / Structure With Time
% 典型效果：上下两个子图分别绘制 PCC1、PCC2 电压幅值，红色实线，右上角图例，浅灰虚线网格

clc; close all;

%% ===================== 用户设置区 =====================

% 情况 A：PCC1、PCC2 分别导出为两个 timeseries
signal_paths = ["out.v_PCC_mag_1", "out.v_PCC_mag_2"];
channel_indices = [1, 1];

% 情况 B：若两个 PCC 电压在同一个 timeseries 的两列中，请改为：
% signal_paths    = ["out.v_PCC_mag", "out.v_PCC_mag"];
% channel_indices = [1, 2];

% 各子图图例名称
legend_labels_user = ["PCC1 电压幅值", "PCC2 电压幅值"];

% 数据缩放系数
% 例如：原始数据单位为 V，若希望绘制 kV，则设 y_scale = 1e-3；若希望绘制 V，则设 y_scale = 1
x_scale = 1;
y_scale = 1;

% 坐标轴标签
x_label = "时间/s";
y_label = "幅值/V";

% 坐标轴范围；不需要限制就设为 []
x_lim = [0 1];
y_lim = [];

% 是否统一两个子图的 y 轴范围
use_common_ylim = true;

% 是否保存图片
save_figure = false;
output_name = "Fig_3_4_10_like_PCC_voltage.png";
output_dpi = 600;

%% ===================== 数据读取区 =====================

signal_paths = string(signal_paths);
legend_labels_user = string(legend_labels_user);

if isempty(signal_paths)
    error('未指定任何 Simulink timeseries 信号路径。');
end

if numel(channel_indices) == 1 && numel(signal_paths) > 1
    channel_indices = repmat(channel_indices, size(signal_paths));
end

if numel(channel_indices) ~= numel(signal_paths)
    error('channel_indices 的数量应与 signal_paths 一致。');
end

fprintf('准备读取工作区中的 Simulink timeseries 信号：\n');
disp(signal_paths(:));

all_t = cell(numel(signal_paths), 1);
all_y = cell(numel(signal_paths), 1);

for k = 1:numel(signal_paths)
    try
        raw_signal = evalin('base', signal_paths(k));
    catch ME
        error('无法从工作区读取信号：%s\n原始错误信息：%s', signal_paths(k), ME.message);
    end

    [t, y] = timeseries_to_xy(raw_signal, channel_indices(k));

    t = t(:) * x_scale;
    y = y(:) * y_scale;

    all_t{k} = t;
    all_y{k} = y;

    fprintf('已读取信号：%s，第 %d 列，数据点数：%d\n', signal_paths(k), channel_indices(k), numel(t));
end

%% ===================== 图例名称处理 =====================

if isempty(legend_labels_user)
    legend_labels = clean_legend_names(signal_paths);
else
    legend_labels = cellstr(legend_labels_user);
end

if numel(legend_labels) ~= numel(signal_paths)
    warning('legend_labels_user 数量与 signal_paths 数量不一致，已自动使用 signal_paths 生成图例。');
    legend_labels = clean_legend_names(signal_paths);
end

%% ===================== 坐标轴范围预处理 =====================

if use_common_ylim && isempty(y_lim)
    y_all = [];
    for k = 1:numel(all_y)
        x = all_t{k};
        y = all_y{k};
        valid = isfinite(x) & isfinite(y);
        if ~isempty(x_lim)
            valid = valid & x >= x_lim(1) & x <= x_lim(2);
        end
        y_all = [y_all; y(valid)]; %#ok<AGROW>
    end

    if ~isempty(y_all)
        y_min = min(y_all);
        y_max = max(y_all);
        y_margin = 0.08 * max(y_max - y_min, eps);
        y_lim_auto = [y_min - y_margin, y_max + y_margin];
    else
        y_lim_auto = [];
    end
else
    y_lim_auto = y_lim;
end

%% ===================== 绘图区 =====================

fig = figure('Color', 'w', ...
    'InvertHardcopy', 'off', ...
    'Units', 'pixels', ...
    'Position', [120, 120, 720, 460]);

% 图 3.4.10 风格：上下两个子图，紧凑排布
layout = tiledlayout(fig, numel(signal_paths), 1, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

plot_handles = gobjects(numel(signal_paths), 1);
ax = gobjects(numel(signal_paths), 1);

for k = 1:numel(signal_paths)
    ax(k) = nexttile(layout, k);
    hold(ax(k), 'on');

    x = all_t{k};
    y = all_y{k};
    valid = isfinite(x) & isfinite(y);

    plot_handles(k) = plot(ax(k), x(valid), y(valid), ...
        'LineStyle', '-', ...
        'Color', [1.00, 0.00, 0.00], ...
        'LineWidth', 1.2);

    hold(ax(k), 'off');

    if ~isempty(x_lim)
        xlim(ax(k), x_lim);
    end

    if ~isempty(y_lim)
        ylim(ax(k), y_lim);
    elseif use_common_ylim && ~isempty(y_lim_auto)
        ylim(ax(k), y_lim_auto);
    end

    format_axis_like_paper(ax(k));

    ylabel(ax(k), y_label, ...
        'FontName', '宋体', ...
        'FontSize', 10.5, ...
        'Color', 'k');

    legend(ax(k), plot_handles(k), legend_labels{k}, ...
        'Location', 'northeast', ...
        'FontName', '宋体', ...
        'FontSize', 9.5, ...
        'Box', 'off', ...
        'Interpreter', 'none');

    % 仅最下方子图保留 x 轴标签，形成论文图常见的紧凑效果
    if k < numel(signal_paths)
        xlabel(ax(k), "");
        ax(k).XTickLabel = [];
    else
        xlabel(ax(k), x_label, ...
            'FontName', '宋体', ...
            'FontSize', 10.5, ...
            'Color', 'k');
    end
end

% 联动 x 轴，缩放或平移时两个子图同步
if numel(ax) > 1
    linkaxes(ax, 'x');
end

%% ===================== 图片保存区 =====================

if save_figure
    exportgraphics(fig, output_name, 'Resolution', output_dpi, 'BackgroundColor', 'white');
    fprintf('图片已保存：%s\n', output_name);
end

%% ===================== 本地函数区 =====================

function [t, y] = timeseries_to_xy(raw_signal, channel_index)
    if isa(raw_signal, 'timeseries')
        t = raw_signal.Time;
        y = raw_signal.Data;
    elseif isa(raw_signal, 'Simulink.SimulationData.Signal')
        values = raw_signal.Values;
        if ~isa(values, 'timeseries')
            error('Simulink.SimulationData.Signal.Values 不是 timeseries 类型。');
        end
        t = values.Time;
        y = values.Data;
    elseif isstruct(raw_signal) && isfield(raw_signal, 'time') && isfield(raw_signal, 'signals')
        t = raw_signal.time;
        y = raw_signal.signals.values;
    else
        error('暂不支持该数据类型：%s。请确认导出变量为 timeseries / SimulationData.Signal / Structure With Time。', class(raw_signal));
    end

    t = double(t(:));
    y = double(squeeze(y));

    % 将数据整理为 [时间点 × 通道] 的二维矩阵
    if isvector(y)
        y = y(:);
    else
        y = reshape(y, size(y, 1), []);
    end

    if channel_index < 1 || channel_index > size(y, 2)
        error('指定的 channel_index=%d 超出信号通道数，当前信号共有 %d 列。', channel_index, size(y, 2));
    end

    y = y(:, channel_index);

    if numel(t) ~= numel(y)
        error('时间向量与数据向量长度不一致：numel(t)=%d, numel(y)=%d。', numel(t), numel(y));
    end
end

function format_axis_like_paper(ax)
    box(ax, 'on');
    grid(ax, 'on');

    set(ax, ...
        'Color', 'w', ...
        'FontName', 'Times New Roman', ...
        'FontSize', 10.0, ...
        'LineWidth', 0.9, ...
        'TickDir', 'out', ...
        'XColor', 'k', ...
        'YColor', 'k', ...
        'GridLineStyle', '--', ...
        'GridColor', [0.75 0.75 0.75], ...
        'GridAlpha', 0.35, ...
        'XMinorGrid', 'off', ...
        'YMinorGrid', 'off');
end

function labels = clean_legend_names(names)
    labels = cellstr(strrep(string(names), '_', '\_'));
end
