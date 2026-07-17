%% plot_fig_ieee30_generator_marginal_cost.m
% 绘制 IEEE-30 节点系统各同步机成本函数的导函数图
% 数据接口直接采用 MATPOWER 标准算例：mpc = case30; Gen_Cost = mpc.gencost;
% 默认自动保存图像，同时显示图窗
%
% 说明：
% 1) MATPOWER 中二次成本函数通常写为 C_g(P_g)=a_g P_g^2+b_g P_g+c_g；
% 2) 本脚本绘制其导函数 dC_g/dP_g=2a_g P_g+b_g，即边际运行成本曲线；
% 3) 曲线仅在各机组自身可行出力区间 [P_g^min, P_g^max] 内绘制；
% 4) 若各机组边际成本区间存在公共交集，则用浅灰色横向带标出，便于说明
%    多台机组同时开机并达到相同边际成本在经济调度中是可能的。

clear; clc; close all;

%% ===================== 用户设置区 =====================

% 项目根目录：脚本位于 <项目根目录>\code 下
project_root = fileparts(fileparts(mfilename('fullpath')));

% 是否只绘制当前处于投运状态的机组
use_only_online_generators = true;

% 每台机组曲线采样点数
num_points_per_generator = 300;

% 是否绘制全部机组共同边际成本区间
show_common_marginal_band = true;

% 是否在曲线末端标注机组编号
show_curve_label = true;

% 图窗大小
fig_position = [120, 120, 980, 520];

% 线宽设置
lw_curve = 2.0;
lw_band  = 1.0;
lw_axis  = 1.0;

% 字体设置：中文使用宋体，英文、数字和坐标刻度使用 Times New Roman
font_chinese = 'SimSun';
font_english = 'Times New Roman';
font_size = 11;

% 颜色设置（尽量延续 MATLAB 默认风格）
color_curve = lines(8);
color_band  = [0.65, 0.65, 0.65];
color_grid  = [0.85, 0.85, 0.85];

% 坐标轴标签与标题
x_label_text = '同步机有功出力/MW';
y_label_text = '边际运行成本/($/MWh)';
title_text = '';

% 图例
legend_location = 'northwest';

% 导出分辨率
export_resolution = 600;

%% ===================== 读取 MATPOWER 算例 =====================

if exist('case30', 'file') ~= 2
    error(['未在 MATLAB 路径中找到 MATPOWER 算例 case30。', ...
        '请先运行 addpath 或启动 MATPOWER。']);
end

% 按用户指定接口读取成本参数
mpc = case30;
Gen_Cost = mpc.gencost;

% 读取 MATPOWER 常量；若未安装 define_constants，则使用固定列号兜底
if exist('define_constants', 'file') == 2
    define_constants;
else
    GEN_BUS = 1;
    GEN_STATUS = 8;
    PMAX = 9;
    PMIN = 10;
end

Gen_Data = mpc.gen;
num_gen_total = size(Gen_Data, 1);

if size(Gen_Cost, 1) < num_gen_total
    error('gencost 行数少于 gen 行数，无法为所有同步机匹配成本函数。');
elseif size(Gen_Cost, 1) > num_gen_total
    % MATPOWER 允许在有功成本后继续给出无功成本，本脚本仅取前 num_gen_total 行有功成本
    Gen_Cost = Gen_Cost(1:num_gen_total, :);
end

if use_only_online_generators
    gen_idx = find(Gen_Data(:, GEN_STATUS) > 0);
else
    gen_idx = (1:num_gen_total).';
end

if isempty(gen_idx)
    error('未识别到需要绘制的同步机。');
end

%% ===================== 计算各同步机边际成本曲线 =====================

num_gen = numel(gen_idx);
curve_data = struct([]);
mc_min = nan(num_gen, 1);
mc_max = nan(num_gen, 1);

fprintf('\nIEEE-30 节点系统同步机边际成本函数：\n');

for ii = 1:num_gen
    g = gen_idx(ii);

    p_min = Gen_Data(g, PMIN);
    p_max = Gen_Data(g, PMAX);
    if p_max < p_min
        error('机组 G%d 的 Pmax 小于 Pmin，请检查算例数据。', g);
    end

    p_grid = linspace(p_min, p_max, num_points_per_generator).';
    mc_grid = evaluate_marginal_cost(Gen_Cost(g, :), p_grid);

    curve_data(ii).gen_id = g;
    curve_data(ii).bus_id = Gen_Data(g, GEN_BUS);
    curve_data(ii).p_min = p_min;
    curve_data(ii).p_max = p_max;
    curve_data(ii).p_grid = p_grid;
    curve_data(ii).mc_grid = mc_grid;
    curve_data(ii).expr_text = build_marginal_cost_expression(Gen_Cost(g, :));

    mc_min(ii) = min(mc_grid);
    mc_max(ii) = max(mc_grid);

    fprintf('  G%-2d 节点 %-2g: dC/dP = %s,  P=[%.4g, %.4g] MW,  MC=[%.4g, %.4g] $/MWh\n', ...
        g, curve_data(ii).bus_id, curve_data(ii).expr_text, ...
        p_min, p_max, mc_min(ii), mc_max(ii));
end

common_mc_lower = max(mc_min);
common_mc_upper = min(mc_max);
has_common_marginal_interval = common_mc_lower <= common_mc_upper + 1e-9;

if has_common_marginal_interval
    fprintf('\n全部已绘制同步机的边际成本区间存在公共交集：[%.6g, %.6g] $/MWh。\n', ...
        common_mc_lower, common_mc_upper);
    fprintf('这说明在标准 IEEE-30 成本参数下，多台同步机达到相同边际成本并非不可能。\n\n');
else
    fprintf('\n全部已绘制同步机的边际成本区间不存在公共交集；可继续查看图中两两交集。\n\n');
end

%% ===================== 绘图 =====================

fig = figure('Color', 'w', 'Position', fig_position);
ax = axes(fig);
hold(ax, 'on');
grid(ax, 'on');
box(ax, 'on');

p_min_all = min([curve_data.p_min]);
p_max_all = max([curve_data.p_max]);
y_min_all = min(mc_min);
y_max_all = max(mc_max);
x_margin = 0.04 * max(p_max_all - p_min_all, eps);
y_margin = 0.08 * max(y_max_all - y_min_all, eps);

% 绘制公共边际成本区间横向带
h_band = gobjects(1, 1);
if show_common_marginal_band && has_common_marginal_interval
    x_patch = [p_min_all - x_margin, p_max_all + x_margin, ...
               p_max_all + x_margin, p_min_all - x_margin];
    y_patch = [common_mc_lower, common_mc_lower, ...
               common_mc_upper, common_mc_upper];
    h_band = patch(ax, x_patch, y_patch, color_band, ...
        'FaceAlpha', 0.18, ...
        'EdgeColor', 'none', ...
        'DisplayName', '全部机组共同边际成本区间');
end

% 绘制边际成本曲线
h_curve = gobjects(num_gen, 1);
for ii = 1:num_gen
    g = curve_data(ii).gen_id;
    bus_id = curve_data(ii).bus_id;
    curve_color = color_curve(mod(ii - 1, size(color_curve, 1)) + 1, :);

    h_curve(ii) = plot(ax, curve_data(ii).p_grid, curve_data(ii).mc_grid, ...
        'LineWidth', lw_curve, ...
        'Color', curve_color, ...
        'DisplayName', sprintf('G%d，Node%d', g, bus_id));

    plot(ax, curve_data(ii).p_min, curve_data(ii).mc_grid(1), 'o', ...
        'Color', curve_color, ...
        'MarkerFaceColor', 'w', ...
        'MarkerSize', 4.5, ...
        'HandleVisibility', 'off');
    plot(ax, curve_data(ii).p_max, curve_data(ii).mc_grid(end), 'o', ...
        'Color', curve_color, ...
        'MarkerFaceColor', curve_color, ...
        'MarkerSize', 4.5, ...
        'HandleVisibility', 'off');

    if show_curve_label
        text(ax, curve_data(ii).p_max + 0.012 * max(p_max_all - p_min_all, eps), ...
            curve_data(ii).mc_grid(end), sprintf('G%d', g), ...
            'Color', curve_color, ...
            'FontName', font_english, ...
            'FontSize', font_size, ...
            'HorizontalAlignment', 'left', ...
            'VerticalAlignment', 'middle');
    end
end

% 公共边际成本区间文字标注
if show_common_marginal_band && has_common_marginal_interval
    text(ax, p_min_all + 0.02 * max(p_max_all - p_min_all, eps), ...
        0.5 * (common_mc_lower + common_mc_upper), ...
        sprintf('共同边际成本区间：[%.3g, %.3g] $/MWh', ...
            common_mc_lower, common_mc_upper), ...
        'Color', [0.20, 0.20, 0.20], ...
        'FontName', font_chinese, ...
        'FontSize', font_size, ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment', 'middle');
end

if ~isempty(title_text)
    title(ax, title_text, ...
        'FontName', font_chinese, 'FontSize', font_size);
end

xlim(ax, [p_min_all - x_margin, p_max_all + 3 * x_margin]);
ylim(ax, [y_min_all - y_margin, y_max_all + y_margin]);

% 图例
if show_common_marginal_band && has_common_marginal_interval
    legend_handles = [h_band; h_curve];
else
    legend_handles = h_curve;
end
legend(ax, legend_handles, ...
    'Location', legend_location, ...
    'Interpreter', 'tex', ...
    'FontName', font_chinese, ...
    'FontSize', font_size);

% 美化
set(ax, ...
    'Layer', 'top', ...
    'LineWidth', lw_axis, ...
    'FontName', font_english, ...
    'FontSize', font_size, ...
    'GridAlpha', 0.15, ...
    'MinorGridAlpha', 0.10, ...
    'XMinorGrid', 'on', ...
    'YMinorGrid', 'on');

% 坐标轴与标题
xlabel(ax, x_label_text, ...
    'FontName', font_chinese, 'FontSize', font_size);
ylabel(ax, y_label_text, ...
    'FontName', font_chinese, 'FontSize', font_size);

% 避免未使用变量提示，同时保留网格色接口
if exist('color_grid', 'var') %#ok<EXIST>
    ax.GridColor = color_grid;
end

fprintf('绘图完成：同步机数量 = %d。\n', num_gen);

%% ===================== 本地函数 =====================

function mc = evaluate_marginal_cost(cost_row, p)
    % 计算 MATPOWER 多项式成本函数的导函数值。
    % cost_row = [MODEL, STARTUP, SHUTDOWN, NCOST, c_{n-1}, ..., c_0]

    model_type = cost_row(1);
    if model_type ~= 2
        error('当前脚本仅支持 MATPOWER 多项式成本模型 MODEL=2。');
    end

    ncost = cost_row(4);
    coeffs = cost_row(5:(4 + ncost));
    d_coeffs = polyder(coeffs);

    if isempty(d_coeffs)
        mc = zeros(size(p));
    else
        mc = polyval(d_coeffs, p);
    end
end

function expr_text = build_marginal_cost_expression(cost_row)
    % 生成便于命令行核查的导函数字符串。

    model_type = cost_row(1);
    if model_type ~= 2
        expr_text = 'unsupported cost model';
        return;
    end

    ncost = cost_row(4);
    coeffs = cost_row(5:(4 + ncost));
    d_coeffs = polyder(coeffs);

    if isempty(d_coeffs)
        expr_text = '0';
    elseif numel(d_coeffs) == 1
        expr_text = sprintf('%.6g', d_coeffs(1));
    elseif numel(d_coeffs) == 2
        expr_text = sprintf('%.6g P + %.6g', d_coeffs(1), d_coeffs(2));
    else
        terms = strings(0, 1);
        degree = numel(d_coeffs) - 1;
        for kk = 1:numel(d_coeffs)
            coef = d_coeffs(kk);
            pow = degree - kk + 1;
            if abs(coef) < 1e-12
                continue;
            end
            if pow == 0
                term = sprintf('%.6g', coef);
            elseif pow == 1
                term = sprintf('%.6g P', coef);
            else
                term = sprintf('%.6g P^%d', coef, pow);
            end
            terms(end + 1, 1) = string(term); %#ok<AGROW>
        end
        if isempty(terms)
            expr_text = '0';
        else
            expr_text = strjoin(terms, ' + ');
        end
    end
end
