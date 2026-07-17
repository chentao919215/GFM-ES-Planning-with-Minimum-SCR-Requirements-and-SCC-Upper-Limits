%% 典型日内机组组合变化下节点SCR裕度与SCC裕度
clear;
clc;
close all;

%% 1. 数据设置（与原脚本一致）
% 各运行方式的切换时刻
t = [0, 6, 10, 16, 22, 24];

% 阶梯曲线数据
% 最后一个数据用于维持22:00—24:00时段的数值
SCR = [2.40, 2.75, 3.15, 2.80, 2.45, 2.45];
SCC = [9.6, 10.8, 12.6, 11.4, 9.8, 9.8];

% 在线同步机数量
unit_num = [2, 3, 4, 3, 2];

% 约束阈值
SCR_min = 2.5;
SCC_max = 12;

%% 2. 裕度定义
% SCR裕度：大于0表示满足下限，小于0表示SCR不足
SCR_margin = SCR - SCR_min;

% SCC裕度：大于0表示未超标，小于0表示SCC超标
SCC_margin = SCC_max - SCC;

%% 3. 配色设置（与原图保持一致）
blue_color   = [0.00, 0.45, 0.74];   % SCR蓝色
orange_color = [0.85, 0.33, 0.10];   % SCC橙色

gray_color   = [0.35, 0.35, 0.35];
light_gray   = [0.75, 0.75, 0.75];

blue_bg      = [0.40, 0.52, 0.78];
orange_bg    = [0.95, 0.62, 0.26];

%% 4. 图幅尺寸设置
% 原图约为15.5 cm × 8.5 cm，这里取一半
fig_w = 7.75;
fig_h = 4.25;

%% =========================
%% 5. 绘制 SCR 裕度图
%% =========================
fig1 = figure( ...
    'Color', 'w', ...
    'Units', 'centimeters', ...
    'Position', [4, 5, fig_w, fig_h]);

ax1 = axes(fig1);
hold(ax1, 'on');
box(ax1, 'on');

% SCR裕度阶梯曲线
h1 = stairs(t, SCR_margin, ...
    'Color', blue_color, ...
    'LineWidth', 2.0);

% 零裕度线
yline(0, '--', ...
    'SCR margin=0', ...
    'Color', blue_color, ...
    'LineWidth', 1.1, ...
    'LabelHorizontalAlignment', 'center', ...
    'LabelVerticalAlignment', 'bottom', ...
    'FontName', 'Times New Roman', ...
    'FontSize', 7);

% 横坐标
xlim([0, 24]);
xticks([0, 6, 10, 16, 22, 24]);
xlabel('Times/h', ...
    'FontName', 'Times New Roman', ...
    'FontSize', 8, ...
    'FontWeight', 'bold');

% 纵坐标
ylim([-0.20, 0.80]);
yticks(-0.2:0.2:0.8);
ylabel('SCR Margin', ...
    'FontName', 'Times New Roman', ...
    'FontSize', 8, ...
    'FontWeight', 'bold');
ax1.YColor = blue_color;

% 机组切换分界线
switch_time = [6, 10, 16, 22];
for k = 1:length(switch_time)
    xline(switch_time(k), ':', ...
        'Color', light_gray, ...
        'LineWidth', 0.9, ...
        'HandleVisibility', 'off');
end

% 顶部机组数量标注
time_mid = (t(1:end-1) + t(2:end)) / 2;
text_y1 = 0.73;
for k = 1:length(unit_num)
    text(time_mid(k), text_y1, ...
        sprintf('%d台机组', unit_num(k)), ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontName', 'Microsoft YaHei', ...
        'FontSize', 6.5, ...
        'FontWeight', 'bold', ...
        'Color', gray_color);
end

% 坐标轴与网格格式
ax1.FontName = 'Times New Roman';
ax1.FontSize = 7.5;
ax1.LineWidth = 1.0;
ax1.TickDir = 'out';
ax1.XColor = [0.15, 0.15, 0.15];

grid(ax1, 'on');
ax1.GridLineStyle = ':';
ax1.GridAlpha = 0.18;

% 控制边距
ax1.Position = [0.12, 0.20, 0.80, 0.68];

% 如需保存图片，可取消下注释
% exportgraphics(fig1, 'SCR_margin.png', 'Resolution', 600);

%% =========================
%% 6. 绘制 SCC 裕度图
%% =========================
fig2 = figure( ...
    'Color', 'w', ...
    'Units', 'centimeters', ...
    'Position', [13, 5, fig_w, fig_h]);

ax2 = axes(fig2);
hold(ax2, 'on');
box(ax2, 'on');

% SCC裕度阶梯曲线
h2 = stairs(t, SCC_margin, ...
    'Color', orange_color, ...
    'LineWidth', 2.0);

% 零裕度线
yline(0, '--', ...
    'SCC margin=0', ...
    'Color', orange_color, ...
    'LineWidth', 1.1, ...
    'LabelHorizontalAlignment', 'right', ...
    'LabelVerticalAlignment', 'bottom', ...
    'FontName', 'Times New Roman', ...
    'FontSize', 7);

% 横坐标
xlim([0, 24]);
xticks([0, 6, 10, 16, 22, 24]);
xlabel('Times/h', ...
    'FontName', 'Times New Roman', ...
    'FontSize', 8, ...
    'FontWeight', 'bold');

% 纵坐标
ylim([-1.0, 3.0]);
yticks(-1:1:3);
ylabel('SCC Margin/kA', ...
    'FontName', 'Times New Roman', ...
    'FontSize', 8, ...
    'FontWeight', 'bold');
ax2.YColor = orange_color;

% 机组切换分界线
for k = 1:length(switch_time)
    xline(switch_time(k), ':', ...
        'Color', light_gray, ...
        'LineWidth', 0.9, ...
        'HandleVisibility', 'off');
end

% 顶部机组数量标注
text_y2 = 2.75;
for k = 1:length(unit_num)
    text(time_mid(k), text_y2, ...
        sprintf('%d台机组', unit_num(k)), ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontName', 'Microsoft YaHei', ...
        'FontSize', 6.5, ...
        'FontWeight', 'bold', ...
        'Color', gray_color);
end

% 坐标轴与网格格式
ax2.FontName = 'Times New Roman';
ax2.FontSize = 7.5;
ax2.LineWidth = 1.0;
ax2.TickDir = 'out';
ax2.XColor = [0.15, 0.15, 0.15];

grid(ax2, 'on');
ax2.GridLineStyle = ':';
ax2.GridAlpha = 0.18;

% 控制边距
ax2.Position = [0.12, 0.20, 0.80, 0.68];

% 如需保存图片，可取消下注释
% exportgraphics(fig2, 'SCC_margin.png', 'Resolution', 600);