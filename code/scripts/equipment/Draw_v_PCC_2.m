%% Draw_v_PCC_Simulink_Fig3410.m
% 数据来源：Simulink导出到MATLAB工作区的timeseries或SimulationData.Signal。
% 典型效果：上下两个子图分别绘制 PCC1、PCC2 电压幅值，红色实线，右上角图例，浅灰虚线网格

clc; close all;

%% ===================== 用户设置区 =====================

% 情况 A：PCC1、PCC2 分别导出为两个 timeseries
Signal_Paths = ["out.v_PCC_mag_1", "out.v_PCC_mag_2"];
Channel_Indices = [1, 1];

% 情况 B：若两个 PCC 电压在同一个 timeseries 的两列中，请改为：
% signal_paths    = ["out.v_PCC_mag", "out.v_PCC_mag"];
% channel_indices = [1, 2];

% 各子图图例名称
Legend_Labels_User = ["PCC1 电压幅值", "PCC2 电压幅值"];

% 数据缩放系数
% 例如：原始数据单位为 V，若希望绘制 kV，则设 y_scale = 1e-3；若希望绘制 V，则设 y_scale = 1
X_Scale = 1;
Y_Scale = 1;

% 坐标轴标签
X_Label = "时间/s";
Y_Label = "幅值/V";

% 坐标轴范围；不需要限制就设为 []
X_Limit = [0 1];
Y_Limit = [];

% 是否统一两个子图的 y 轴范围
Use_Common_Y_Limit = true;

% 是否保存图片
Save_Figure = false;
Output_Name = "Fig_3_4_10_like_PCC_voltage.png";
Output_DPI = 600;

%% ===================== 数据读取区 =====================

Signal_Paths = string(Signal_Paths);
Legend_Labels_User = string(Legend_Labels_User);

if isempty(Signal_Paths)
    error('未指定任何 Simulink timeseries 信号路径。');
end

if isscalar(Channel_Indices) && numel(Signal_Paths) > 1
    Channel_Indices = repmat(Channel_Indices, size(Signal_Paths));
end

if numel(Channel_Indices) ~= numel(Signal_Paths)
    error('channel_indices 的数量应与 signal_paths 一致。');
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

    [t, y] = timeseries_to_xy(Raw_Signal, Channel_Indices(k));

    t = t(:) * X_Scale;
    y = y(:) * Y_Scale;

    All_t{k} = t;
    All_Y{k} = y;

    fprintf('已读取信号：%s，第 %d 列，数据点数：%d\n', Signal_Paths(k), Channel_Indices(k), numel(t));
end

%% ===================== 图例名称处理 =====================

if isempty(Legend_Labels_User)
    Legend_Labels = clean_legend_names(Signal_Paths);
else
    Legend_Labels = cellstr(Legend_Labels_User);
end

if numel(Legend_Labels) ~= numel(Signal_Paths)
    warning('legend_labels_user 数量与 signal_paths 数量不一致，已自动使用 signal_paths 生成图例。');
    Legend_Labels = clean_legend_names(Signal_Paths);
end

%% ===================== 坐标轴范围预处理 =====================

if Use_Common_Y_Limit && isempty(Y_Limit)
    Y_All = [];
    for k = 1:numel(All_Y)
        x = All_t{k};
        y = All_Y{k};
        valid = isfinite(x) & isfinite(y);
        if ~isempty(X_Limit)
            valid = valid & x >= X_Limit(1) & x <= X_Limit(2);
        end
        Y_All = [Y_All; y(valid)]; %#ok<AGROW>
    end

    if ~isempty(Y_All)
        Y_Min = min(Y_All);
        Y_Max = max(Y_All);
        Y_Margin = 0.08 * max(Y_Max - Y_Min, eps);
        Y_Limit_Auto = [Y_Min - Y_Margin, Y_Max + Y_Margin];
    else
        Y_Limit_Auto = [];
    end
else
    Y_Limit_Auto = Y_Limit;
end

%% ===================== 绘图区 =====================

fig = figure('Color', 'w', ...
    'InvertHardcopy', 'off', ...
    'Units', 'pixels', ...
    'Position', [120, 120, 720, 460]);

% 图 3.4.10 风格：上下两个子图，紧凑排布
layout = tiledlayout(fig, numel(Signal_Paths), 1, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

Plot_Handles = gobjects(numel(Signal_Paths), 1);
ax = gobjects(numel(Signal_Paths), 1);

for k = 1:numel(Signal_Paths)
    ax(k) = nexttile(layout, k);
    hold(ax(k), 'on');

    x = All_t{k};
    y = All_Y{k};
    valid = isfinite(x) & isfinite(y);

    Plot_Handles(k) = plot(ax(k), x(valid), y(valid), ...
        'LineStyle', '-', ...
        'Color', [1.00, 0.00, 0.00], ...
        'LineWidth', 1.2);

    hold(ax(k), 'off');

    if ~isempty(X_Limit)
        xlim(ax(k), X_Limit);
    end

    if ~isempty(Y_Limit)
        ylim(ax(k), Y_Limit);
    elseif Use_Common_Y_Limit && ~isempty(Y_Limit_Auto)
        ylim(ax(k), Y_Limit_Auto);
    end

    format_axis_like_paper(ax(k));

    ylabel(ax(k), Y_Label, ...
        'FontName', '宋体', ...
        'FontSize', 10.5, ...
        'Color', 'k');

    legend(ax(k), Plot_Handles(k), Legend_Labels{k}, ...
        'Location', 'northeast', ...
        'FontName', '宋体', ...
        'FontSize', 9.5, ...
        'Box', 'off', ...
        'Interpreter', 'none');

    % 仅最下方子图保留 x 轴标签，形成论文图常见的紧凑效果
    if k < numel(Signal_Paths)
        xlabel(ax(k), "");
        ax(k).XTickLabel = [];
    else
        xlabel(ax(k), X_Label, ...
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

if Save_Figure
    exportgraphics(fig, Output_Name, 'Resolution', Output_DPI, 'BackgroundColor', 'white');
    fprintf('图片已保存：%s\n', Output_Name);
end

%% ===================== 本地函数区 =====================

function [t, y] = timeseries_to_xy(Raw_Signal, Channel_Index)
    if isa(Raw_Signal, 'timeseries')
        t = Raw_Signal.Time;
        y = Raw_Signal.Data;
    elseif isa(Raw_Signal, 'Simulink.SimulationData.Signal')
        values = Raw_Signal.Values;
        if ~isa(values, 'timeseries')
            error('Simulink.SimulationData.Signal.Values 不是 timeseries 类型。');
        end
        t = values.Time;
        y = values.Data;
    else
        error('暂不支持该数据类型：%s。请确认导出变量为timeseries或SimulationData.Signal。', class(Raw_Signal));
    end

    t = double(t(:));
    y = double(squeeze(y));

    % 将数据整理为 [时间点 × 通道] 的二维矩阵
    if isvector(y)
        y = y(:);
    else
        y = reshape(y, size(y, 1), []);
    end

    if Channel_Index < 1 || Channel_Index > size(y, 2)
        error('指定的 channel_index=%d 超出信号通道数，当前信号共有 %d 列。', Channel_Index, size(y, 2));
    end

    y = y(:, Channel_Index);

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
