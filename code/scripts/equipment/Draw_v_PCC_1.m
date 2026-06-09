%% plot_single_simulink_timeseries.m
% 读取 MATLAB 工作区中的 Simulink timeseries 信号，并绘图
% 数据来源示例：out.v_PCC_mag，其中 out.v_PCC_mag 为 1x1 timeseries
% 不自动保存文件，只显示图窗
clc; close all;

%% ===================== 用户设置区 =====================

% Simulink 导出到工作区的信号路径
% 单条曲线示例："out.v_PCC_mag"
% 若后续需要三组场景对比，可写成：
% signal_paths = ["out_SCR2_Q0.v_PCC_mag", "out_SCR3_Q0.v_PCC_mag", "out_SCR3_QN.v_PCC_mag"];
signal_paths = "out.v_PCC_mag";

% 曲线图例名称
% 若留空 strings(0,1)，则默认使用 signal_paths 生成图例
legend_labels_user = "并网点电压幅值";

% 数据缩放系数
% 例如：原始数据单位为 V，若希望绘制 kV，则设 y_scale = 1e-3
% 若希望绘制 p.u.，则设 y_scale = 1/Ubase
x_scale = 1;
y_scale = 1e-3;

% 图题与坐标轴标签
fig_title = "";
x_label = "时间/s";
y_label = "幅值/kV";

% 坐标轴范围；不需要限制就设为 []
x_lim = [0 1];
y_lim = [];

% 是否显示图例
show_legend = true;

%% ===================== 数据读取区 =====================

signal_paths = string(signal_paths);

if isempty(signal_paths)
    error('未指定任何 Simulink timeseries 信号路径。');
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

    [t, y] = timeseries_to_xy(raw_signal);

    t = t(:) * x_scale;
    y = y(:) * y_scale;

    all_t{k} = t;
    all_y{k} = y;

    fprintf('已读取信号：%s，数据点数：%d\n', signal_paths(k), numel(t));
end

%% ===================== 变量选择区 =====================

% 兼容原 CSV 脚本结构：这里不再按列名选择变量，而是直接使用
% 用户设置区中的 signal_paths 作为待绘制信号。
if isempty(legend_labels_user)
    legend_labels = clean_legend_names(signal_paths);
else
    legend_labels = cellstr(string(legend_labels_user));
end

if numel(legend_labels) ~= numel(signal_paths)
    warning('legend_labels_user 数量与 signal_paths 数量不一致，已自动使用 signal_paths 生成图例。');
    legend_labels = clean_legend_names(signal_paths);
end

%% ===================== 绘图区 =====================

fig = figure('Color', 'w', ...
    'InvertHardcopy', 'off', ...
    'Position', [120, 120, 680, 420]);

ax = axes(fig);
set(ax, 'Color', 'w');
hold(ax, 'on');

% 论文图推荐线型：
% 第1条：黑色虚线；第2条：红色实线；第3条：蓝色实线
line_styles = {'-', '--', '-'};
line_colors = {[0.00 0.30 0.75],[0 0 0], [0.85 0.10 0.10]};
line_widths = [1.6, 1.8, 1.8];

plot_handles = gobjects(numel(signal_paths), 1);

for k = 1:numel(signal_paths)
    x = all_t{k};
    y = all_y{k};
    valid = isfinite(x) & isfinite(y);

    style_idx = min(k, numel(line_styles));
    color_idx = min(k, numel(line_colors));
    width_idx = min(k, numel(line_widths));

    plot_handles(k) = plot(ax, x(valid), y(valid), ...
        'LineStyle', line_styles{style_idx}, ...
        'Color', line_colors{color_idx}, ...
        'LineWidth', line_widths(width_idx));
end

hold(ax, 'off');

% 坐标轴范围
if ~isempty(x_lim)
    xlim(ax, x_lim);
end

if ~isempty(y_lim)
    ylim(ax, y_lim);
end

% 坐标轴与网格格式
box(ax, 'on');
grid(ax, 'on');

set(ax, ...
    'FontName', 'Times New Roman', ...
    'FontSize', 10.5, ...
    'LineWidth', 1.0, ...
    'TickDir', 'out', ...
    'XColor', 'k', ...
    'YColor', 'k', ...
    'GridLineStyle', '--', ...
    'GridColor', [0.70 0.70 0.70], ...
    'GridAlpha', 0.35, ...
    'XMinorGrid', 'off', ...
    'YMinorGrid', 'off');

% 坐标轴标签
xlabel(ax, x_label, ...
    'FontName', '宋体', ...
    'FontSize', 11, ...
    'Color', 'k');

ylabel(ax, y_label, ...
    'FontName', '宋体', ...
    'FontSize', 11, ...
    'Color', 'k');

% 图题
if strlength(fig_title) > 0
    title(ax, fig_title, ...
        'FontName', '宋体', ...
        'FontSize', 11, ...
        'Color', 'k', ...
        'Interpreter', 'none');
end

% 图例
if show_legend
    legend(ax, plot_handles, legend_labels, ...
        'Location', 'northwest', ...
        'FontName', '宋体', ...
        'FontSize', 10.5, ...
        'Box', 'off', ...
        'Interpreter', 'none');
end

%% ===================== 本地函数区 =====================

function [t, y] = timeseries_to_xy(raw_signal)
    if isa(raw_signal, 'timeseries')
        t = raw_signal.Time;
        y = raw_signal.Data;
    elseif isa(raw_signal, 'Simulink.SimulationData.Signal')
        % 若 signal logging 得到的是 Simulink.SimulationData.Signal
        values = raw_signal.Values;
        if ~isa(values, 'timeseries')
            error('Simulink.SimulationData.Signal.Values 不是 timeseries 类型。');
        end
        t = values.Time;
        y = values.Data;
    elseif isstruct(raw_signal) && isfield(raw_signal, 'time') && isfield(raw_signal, 'signals')
        % 兼容 Structure With Time 格式
        t = raw_signal.time;
        y = raw_signal.signals.values;
    else
        error('暂不支持该数据类型：%s。请确认导出变量为 timeseries。', class(raw_signal));
    end

    t = double(t);
    y = double(squeeze(y));

    % 若 y 为多列数据，默认取第 1 列；PCC 幅值通常应为单列。
    if ~isvector(y)
        warning('信号数据不是单列，已默认取第 1 列绘制。');
        y = reshape(y, size(y, 1), []);
        y = y(:, 1);
    end

    y = y(:);

    if numel(t) ~= numel(y)
        error('时间向量与数据向量长度不一致：numel(t)=%d, numel(y)=%d。', numel(t), numel(y));
    end
end

function labels = clean_legend_names(names)
    labels = cellstr(strrep(string(names), '_', '\_'));
end
