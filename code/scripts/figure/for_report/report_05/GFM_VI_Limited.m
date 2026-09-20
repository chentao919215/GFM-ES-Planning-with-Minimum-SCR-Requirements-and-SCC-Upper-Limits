%% GFM_VI_Limited
% 虚拟阻抗限流下构网型变流器的 UPCC-IGFM 端口特性。
% 正式模型令 nq=0，内部电势固定为 E0；设备残余电抗完全由物理
% L2 表示，并计入 R_L2 以及两状态虚拟电抗。

clear;
close all;
clc;

%% 正式参数初始化
scriptFile = mfilename('fullpath');
projectRoot = fileparts(scriptFile);
for pathLevel = 1:5
    projectRoot = fileparts(projectRoot);
end
parameterFile = fullfile(projectRoot, 'code', 'scripts', 'equipment', ...
    'GFM', 'GFM_Parameters.m');
addpath(fullfile(projectRoot, 'code', 'functions', 'equipment'));
addpath(fileparts(parameterFile));
run(parameterFile);

theory = struct();
theory.E0_pu = GFM_Droop.E0_pu;
theory.R_L2_pu = R_L2/Z_base;
theory.X_L2_pu = 2*pi*f*L2/Z_base;
theory.X_res_device_pu = GFM_VI.X_res_device_pu;
theory.X_vir_pu = GFM_VI.X_vir_device_pu;
theory.I_lim_pu = GFM_VI.I_switch_threshold_pu;
theory.U_boundary_pu = GFM_VI.U_boundary_pu;

I_lim = theory.I_lim_pu;
U_boundary = theory.U_boundary_pu;
U_PCC_min = 0.00;
U_PCC_max = 1.00;
num_points = 501;

assert(theory.X_vir_pu > 0, 'X_vir_device_pu 必须大于 0。');
assert(abs(GFM_Droop.nq) < 1e-12, '固定内电势理论要求 GFM_Droop.nq=0。');
assert(abs(theory.X_L2_pu-theory.X_res_device_pu) < 1e-12, ...
    '物理 L2 电抗必须等于正式 X_res_device_pu。');

figure_width_cm = 14.8;
figure_height_cm = 10.5;
axis_font_size = 11;
label_font_size = 14;

%% 固定内电势下的两状态端口曲线
% E0^2 = [UPCC+(XL2+Slim*Xvir)*IGFM]^2+(RL2*IGFM)^2
% R_L2 很小，因此精确电流阈值位置应与正式 Ub 基本重合。
U_current_threshold = localFindCurrentThresholdVoltage( ...
    theory, U_PCC_min, U_PCC_max);
I_pre_switch = localPortCurrent(U_boundary, 0, theory);
I_post_switch = localPortCurrent(U_boundary, 1, theory);

if U_boundary <= U_PCC_min || U_boundary >= U_PCC_max
    error('正式 U_boundary=%.4f 不在扫描范围内。', U_boundary);
end

U_PCC_limited = linspace(U_PCC_min, U_boundary, num_points);
I_GFM_limited = localPortCurrent(U_PCC_limited, 1, theory);
U_PCC_unlimited = linspace(U_boundary, U_PCC_max, num_points);
I_GFM_unlimited = localPortCurrent(U_PCC_unlimited, 0, theory);
I_axis_max = 5/3*I_lim;

%% 创建图窗与坐标区
available_fonts = listfonts;
font_candidates = {'SimSun', 'Microsoft YaHei', 'Microsoft YaHei UI', ...
    'Noto Sans SC', 'Microsoft JhengHei', 'Arial'};
font_name = font_candidates{end};
for font_index = 1:numel(font_candidates)
    if any(strcmpi(strtrim(available_fonts), font_candidates{font_index}))
        font_name = font_candidates{font_index};
        break;
    end
end

figure_handle = figure('Color', 'w', 'Units', 'centimeters', ...
    'Position', [2.0, 2.0, figure_width_cm, figure_height_cm], ...
    'PaperPositionMode', 'auto');
axes_handle = axes('Parent', figure_handle, ...
    'Color', [0.98, 0.985, 0.99], ...
    'FontName', 'Times New Roman', 'FontSize', axis_font_size, ...
    'LineWidth', 1.1, 'TickDir', 'out', 'Box', 'on');
hold(axes_handle, 'on');
grid(axes_handle, 'on');
axes_handle.XMinorGrid = 'on';
axes_handle.YMinorGrid = 'on';
axes_handle.GridLineStyle = '--';
axes_handle.MinorGridLineStyle = ':';
axes_handle.GridColor = [0.72, 0.82, 0.90];
axes_handle.MinorGridColor = [0.80, 0.87, 0.93];
axes_handle.GridAlpha = 0.70;
axes_handle.MinorGridAlpha = 0.65;

%% 绘制理论特性
blue_color = [0.0000, 0.4470, 0.7410];
red_color = [0.85, 0.15, 0.15];

plot(axes_handle, U_PCC_unlimited, I_GFM_unlimited, '-', ...
    'Color', blue_color, 'LineWidth', 2.2, 'HandleVisibility', 'off');
plot(axes_handle, U_PCC_limited, I_GFM_limited, '-', ...
    'Color', blue_color, 'LineWidth', 2.2, 'HandleVisibility', 'off');
plot(axes_handle, [U_boundary, U_boundary], ...
    [I_post_switch, I_pre_switch], '-', ...
    'Color', blue_color, 'LineWidth', 2.2, 'HandleVisibility', 'off');

xlim(axes_handle, [U_PCC_min, U_PCC_max]);
ylim(axes_handle, [0, I_axis_max]);
xticks(axes_handle, linspace(U_PCC_min, U_PCC_max, 5));
yticks(axes_handle, 0:0.5:ceil(I_axis_max/0.5)*0.5);

plot(axes_handle, [U_PCC_min, U_PCC_max], [I_lim, I_lim], '--', ...
    'Color', red_color, 'LineWidth', 1.5, 'HandleVisibility', 'off');
plot(axes_handle, [U_boundary, U_boundary], [0, I_axis_max], '--', ...
    'Color', red_color, 'LineWidth', 1.5, 'HandleVisibility', 'off');

plot(axes_handle, U_current_threshold, I_lim, 'o', ...
    'MarkerSize', 7, 'MarkerFaceColor', 'w', ...
    'MarkerEdgeColor', red_color, 'LineWidth', 1.2, ...
    'HandleVisibility', 'off');
plot(axes_handle, U_boundary, I_pre_switch, 'o', ...
    'MarkerSize', 7, 'MarkerFaceColor', red_color, ...
    'MarkerEdgeColor', red_color, 'LineWidth', 1.0, ...
    'HandleVisibility', 'off');

%% 坐标轴与文字标注
xlabel(axes_handle, '|{\itU}^{PCC}|/{\itU}^N', ...
    'FontName', 'Times New Roman', 'FontSize', label_font_size, 'Color', 'k');
ylabel(axes_handle, '|{\itI}^{GFM}|/{\itI}^N', ...
    'FontName', 'Times New Roman', 'FontSize', label_font_size, 'Color', 'k');

text(axes_handle, U_boundary+0.56*(U_PCC_max-U_boundary), ...
    0.32*I_lim, '未限流区', 'Color', blue_color, ...
    'FontName', font_name, 'FontSize', 12, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
text(axes_handle, U_PCC_min+0.50*(U_boundary-U_PCC_min), ...
    0.28*I_lim, '虚拟阻抗限流区', 'Color', [0.25, 0.25, 0.25], ...
    'FontName', font_name, 'FontSize', 11, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
text(axes_handle, U_PCC_min+0.50*(U_boundary-U_PCC_min), ...
    0.80*I_lim, '虚拟阻抗投入后斜率减小', ...
    'Color', blue_color, 'FontName', font_name, 'FontSize', 10, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');

text(axes_handle, 0.30*(U_PCC_max-U_PCC_min), I_lim, ...
    '限流触发阈值\fontname{Times New Roman}{\itI}^{lim}', ...
    'Color', red_color, 'FontName', font_name, 'FontSize', 11, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');
text(axes_handle, U_boundary-0.25*(U_PCC_max-U_PCC_min), ...
    0.90*I_axis_max, ...
    '状态电压边界\fontname{Times New Roman}{\itU}_b', ...
    'Color', red_color, 'FontName', font_name, 'FontSize', 11, ...
    'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom');
text(axes_handle, U_boundary-0.012*(U_PCC_max-U_PCC_min), ...
    I_pre_switch, '状态切换点', 'Color', red_color, ...
    'FontName', font_name, 'FontSize', 10, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');

fprintf(['Fixed-E theory: U(I=Ilim)=%.6f p.u., formal Ub=%.6f p.u., ' ...
    'I(Ub,OFF)=%.6f p.u., I(Ub,ON)=%.6f p.u.\n'], ...
    U_current_threshold, U_boundary, I_pre_switch, I_post_switch);

% 可选：以 300 dpi 导出适合插入 PPT 的 PNG 图片。
% exportgraphics(figure_handle, 'GFM_VI_Limited.png', 'Resolution', 300);

function current = localPortCurrent(voltage, slim, theory)
    originalSize = size(voltage);
    voltage = voltage(:);
    if isscalar(slim)
        slim = repmat(slim, size(voltage));
    else
        slim = slim(:);
    end
    assert(numel(slim) == numel(voltage), 'Slim 与电压向量尺寸不一致。');

    X = theory.X_L2_pu+slim*theory.X_vir_pu;
    impedanceSquared = theory.R_L2_pu^2+X.^2;
    discriminant = (voltage.*X).^2 ...
        -impedanceSquared.*(voltage.^2-theory.E0_pu^2);
    assert(all(discriminant >= -1e-12), ...
        '固定内电势端口方程在当前电压范围内没有实数解。');
    current = (-voltage.*X+sqrt(max(discriminant, 0))) ...
        ./impedanceSquared;
    current = reshape(max(current, 0), originalSize);
end

function voltage = localFindCurrentThresholdVoltage(theory, Umin, Umax)
    radicand = theory.E0_pu^2 ...
        -(theory.R_L2_pu*theory.I_lim_pu)^2;
    assert(radicand >= 0, 'I_lim 超出固定内电势端口方程的可行范围。');
    voltage = sqrt(radicand) ...
        -theory.X_L2_pu*theory.I_lim_pu;
    assert(voltage >= Umin && voltage <= Umax, ...
        '当前扫描范围内不存在 I_GFM=I_lim 交点。');
end