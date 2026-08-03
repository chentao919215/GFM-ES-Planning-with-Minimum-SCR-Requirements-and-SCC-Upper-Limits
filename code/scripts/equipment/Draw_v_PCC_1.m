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
Signal_Paths = "out.v_PCC_mag";

% 曲线图例名称
% 若留空 strings(0,1)，则默认使用 signal_paths 生成图例
Legend_Labels_User = "并网点电压幅值";

% 数据缩放系数
% 例如：原始数据单位为 V，若希望绘制 kV，则设 y_scale = 1e-3
% 若希望绘制 p.u.，则设 y_scale = 1/Ubase
X_Scale = 1;
Y_Scale = 1e-3;

% 图题与坐标轴标签
Figure_Title = "";
X_Label = "时间/s";
Y_Label = "幅值/kV";

% 坐标轴范围；不需要限制就设为 []
X_Limit = [0 1];
Y_Limit = [];

% 是否显示图例
Show_Legend = true;

%% ===================== 数据读取区 =====================

Signal_Paths = string(Signal_Paths);

if isempty(Signal_Paths)
    error('未指定任何 Simulink timeseries 信号路径。');
end

fprintf('准备读取工作区中的 Simulink timeseries 信号：\n');
disp(Signal_Paths(:));

All_t = cell(numel(Signal_Paths), 1);
All_Y = cell(numel(Signal_Paths), 1);

for k = 1:numel(Signal_Paths)
    try
        Raw_Signal = evalin('base', Signal_Paths(k));
    catch ME
        error('无法从工作区读取信号：%s\n原始错误信息：%s', Signal_Paths(k), ME.message);
    end

    [t, y] = timeseries_to_xy(Raw_Signal);

    t = t(:) * X_Scale;
    y = y(:) * Y_Scale;

    All_t{k} = t;
    All_Y{k} = y;

    fprintf('已读取信号：%s，数据点数：%d\n', Signal_Paths(k), numel(t));
end

%% ===================== 变量选择区 =====================

% 兼容原 CSV 脚本结构：这里不再按列名选择变量，而是直接使用
% 用户设置区中的 signal_paths 作为待绘制信号。
if isempty(Legend_Labels_User)
    Legend_Labels = clean_legend_names(Signal_Paths);
else
    Legend_Labels = cellstr(string(Legend_Labels_User));
end

if numel(Legend_Labels) ~= numel(Signal_Paths)
    warning('legend_labels_user 数量与 signal_paths 数量不一致，已自动使用 signal_paths 生成图例。');
    Legend_Labels = clean_legend_names(Signal_Paths);
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
Line_Styles = {'-', '--', '-'};
Line_Colors = {[0.00 0.30 0.75],[0 0 0], [0.85 0.10 0.10]};
Line_Widths = [1.6, 1.8, 1.8];

Plot_Handles = gobjects(numel(Signal_Paths), 1);

for k = 1:numel(Signal_Paths)
    x = All_t{k};
    y = All_Y{k};
    valid = isfinite(x) & isfinite(y);

    Style_Index = min(k, numel(Line_Styles));
    Color_Index = min(k, numel(Line_Colors));
    Width_Index = min(k, numel(Line_Widths));

    Plot_Handles(k) = plot(ax, x(valid), y(valid), ...
        'LineStyle', Line_Styles{Style_Index}, ...
        'Color', Line_Colors{Color_Index}, ...
        'LineWidth', Line_Widths(Width_Index));
end

hold(ax, 'off');

% 坐标轴范围
if ~isempty(X_Limit)
    xlim(ax, X_Limit);
end

if ~isempty(Y_Limit)
    ylim(ax, Y_Limit);
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
xlabel(ax, X_Label, ...
    'FontName', '宋体', ...
    'FontSize', 11, ...
    'Color', 'k');

ylabel(ax, Y_Label, ...
    'FontName', '宋体', ...
    'FontSize', 11, ...
    'Color', 'k');

% 图题
if strlength(Figure_Title) > 0
    title(ax, Figure_Title, ...
        'FontName', '宋体', ...
        'FontSize', 11, ...
        'Color', 'k', ...
        'Interpreter', 'none');
end

% 图例
if Show_Legend
    legend(ax, Plot_Handles, Legend_Labels, ...
        'Location', 'northwest', ...
        'FontName', '宋体', ...
        'FontSize', 10.5, ...
        'Box', 'off', ...
        'Interpreter', 'none');
end

%% ===================== 本地函数区 =====================

function [t, y] = timeseries_to_xy(Raw_Signal)
    if isa(Raw_Signal, 'timeseries')
        t = Raw_Signal.Time;
        y = Raw_Signal.Data;
    elseif isa(Raw_Signal, 'Simulink.SimulationData.Signal')
        % 若 signal logging 得到的是 Simulink.SimulationData.Signal
        values = Raw_Signal.Values;
        if ~isa(values, 'timeseries')
            error('Simulink.SimulationData.Signal.Values 不是 timeseries 类型。');
        end
        t = values.Time;
        y = values.Data;
    else
        error('暂不支持该数据类型：%s。请确认导出变量为 timeseries。', class(Raw_Signal));
    end

    t = double(t);
    y = double(squeeze(y));

    % PCC幅值应为单列。
    if ~isvector(y)
        error('信号数据必须为单列。');
    end

    y = y(:);

    if numel(t) ~= numel(y)
        error('时间向量与数据向量长度不一致：numel(t)=%d, numel(y)=%d。', numel(t), numel(y));
    end
end

function labels = clean_legend_names(names)
    labels = cellstr(strrep(string(names), '_', '\_'));
end
