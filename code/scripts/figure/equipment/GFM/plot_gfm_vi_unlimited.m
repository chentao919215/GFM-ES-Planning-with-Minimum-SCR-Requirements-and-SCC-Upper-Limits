function Report = plot_gfm_vi_unlimited(Options)
%% GFM虚拟阻抗未限流端口特性
% 构网型变流器未限流状态下的 UPCC-IGFM 端口外特性。
% 正式模型令 nq=0，内部电势固定为 E0；设备残余电抗完全由物理
% L2 表示，并计入 R_L2。
if nargin < 1
    Options = struct();
end

%% 1. 正式参数初始化
Script_Directory = fileparts(mfilename('fullpath'));
Code_Directory = fileparts(fileparts(fileparts(fileparts(Script_Directory))));
addpath(fullfile(Code_Directory, 'functions', 'utils'));
Project_Root = find_project_root(Script_Directory);
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
Options = figure_options(Options, struct('Output_Directory', fullfile(Project_Root, 'figs', 'equipment', ...
    'GFM')));
Style = figure_style('review');
Style.Visible = Options.Visible;
Style.Close_After_Save = Options.Close_After_Save;

Parameter_File = fullfile(Project_Root, 'code', 'scripts', 'equipment', ...
    'initialization', 'initialize_gfm_model.m');
addpath(fileparts(Parameter_File));
run(Parameter_File);

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

assert(abs(GFM_Droop.nq) < 1e-12, '固定内电势理论要求 GFM_Droop.nq=0。');
assert(abs(theory.X_L2_pu-theory.X_res_device_pu) < 1e-12, ...
    '物理 L2 电抗必须等于正式 X_res_device_pu。');
U_PCC_min = 0.70;
U_PCC_max = 1.00;
Num_Points = 501;

Figure_Width_cm = 14.8;
Figure_Height_cm = 10.5;
Label_Font_Size = Style.Label_Size;
Legend_Font_Size = Style.Legend_Size;

%% 2. 固定内电势下的未限流端口曲线
% E0^2 = [UPCC+XL2*IGFM]^2+(RL2*IGFM)^2
%
% U_current_threshold 是计入 R_L2 后电流达到 I_lim 的精确位置；
% U_boundary 是正式状态边界，两者仅因很小的 R_L2 存在微小差异。
U_current_threshold = find_current_threshold_voltage( ...
    theory, U_PCC_min, U_PCC_max);
I_boundary = calculate_gfm_port_current(U_boundary, 0, theory);

if U_boundary <= U_PCC_min || U_boundary >= U_PCC_max
    error('正式 U_boundary=%.4f 不在扫描范围内。', U_boundary);
end

U_PCC_extrapolated = linspace(U_PCC_min, U_boundary, Num_Points);
I_GFM_extrapolated = calculate_gfm_port_current(U_PCC_extrapolated, 0, theory);
U_PCC_unlimited = linspace(U_boundary, U_PCC_max, Num_Points);
I_GFM_unlimited = calculate_gfm_port_current(U_PCC_unlimited, 0, theory);

% 低电压 OFF 状态只是外推；纵轴保持原汇报尺度。
I_axis_max = max(2.2*I_lim, 1.15*I_boundary);

%% 3. 创建图窗与坐标区
Font_Name = Style.Font_Name;

Figure_Handle = new_figure([Figure_Width_cm Figure_Height_cm], Style);
Axes_Handle = axes('Parent', Figure_Handle);
style_sci_axes(Axes_Handle);
hold(Axes_Handle, 'on');

%% 4. 绘制特性曲线与限流标记
Curve_Color = Style.Colors.GFM;
Gray_Color = [0.65, 0.68, 0.72];
Reference_Color = Style.Colors.Reference;

Extrapolated_Line = plot(Axes_Handle, U_PCC_extrapolated, ...
    I_GFM_extrapolated, '--', 'Color', Gray_Color, ...
    'LineWidth', 1.9, 'DisplayName', 'Unlimited-model extrapolation');
Unlimited_Line = plot(Axes_Handle, U_PCC_unlimited, ...
    I_GFM_unlimited, '-', 'Color', Curve_Color, ...
    'LineWidth', 2.2, 'DisplayName', 'Unlimited port characteristic');

xlim(Axes_Handle, [U_PCC_min, U_PCC_max]);
ylim(Axes_Handle, [0, I_axis_max]);
xticks(Axes_Handle, linspace(U_PCC_min, U_PCC_max, 5));
yticks(Axes_Handle, 0:0.5:ceil(I_axis_max/0.5)*0.5);

plot(Axes_Handle, [U_PCC_min, U_PCC_max], [I_lim, I_lim], '--', ...
    'Color', Reference_Color, 'LineWidth', 1.5, 'HandleVisibility', 'off');
plot(Axes_Handle, [U_boundary, U_boundary], [0, I_axis_max], '--', ...
    'Color', Reference_Color, 'LineWidth', 1.5, 'HandleVisibility', 'off');

plot(Axes_Handle, U_current_threshold, I_lim, 'o', ...
    'MarkerSize', 7, 'MarkerFaceColor', 'w', ...
    'MarkerEdgeColor', Reference_Color, 'LineWidth', 1.2, ...
    'HandleVisibility', 'off');
plot(Axes_Handle, U_boundary, I_boundary, 'o', ...
    'MarkerSize', 7, 'MarkerFaceColor', Reference_Color, ...
    'MarkerEdgeColor', Reference_Color, 'LineWidth', 1.0, ...
    'HandleVisibility', 'off');

%% 5. 坐标轴标签、区域说明和图例
xlabel(Axes_Handle, '|{\itU}^{PCC}|/{\itU}^N', ...
    'FontName', 'Times New Roman', 'FontSize', Label_Font_Size, 'Color', 'k');
ylabel(Axes_Handle, '|{\itI}^{GFM}|/{\itI}^N', ...
    'FontName', 'Times New Roman', 'FontSize', Label_Font_Size, 'Color', 'k');

text(Axes_Handle, U_boundary+0.55*(U_PCC_max-U_boundary), ...
    0.52*I_lim, {'VI';'off'}, 'Color', Curve_Color, ...
    'FontName', Font_Name, 'FontSize', 12, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
text(Axes_Handle, U_PCC_min+0.48*(U_boundary-U_PCC_min), ...
    0.84*I_axis_max, 'Virtual-impedance region', ...
    'Color', [0.25, 0.25, 0.25], ...
    'FontName', Font_Name, 'FontSize', 11, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');

text(Axes_Handle, U_PCC_max-0.012*(U_PCC_max-U_PCC_min), I_lim, ...
    'Current limit \fontname{Times New Roman}{\itI}^{lim}', ...
    'Color', Reference_Color, 'FontName', Font_Name, 'FontSize', 11, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');
text(Axes_Handle, U_boundary-0.012*(U_PCC_max-U_PCC_min), ...
    0.10*I_axis_max, ...
    'State boundary \fontname{Times New Roman}{\itU}_b', ...
    'Color', Reference_Color, 'FontName', Font_Name, 'FontSize', 11, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');
text(Axes_Handle, U_current_threshold-0.012*(U_PCC_max-U_PCC_min), ...
    I_lim, 'Current threshold', 'Color', Reference_Color, ...
    'FontName', Font_Name, 'FontSize', 10, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'top');
text(Axes_Handle, U_boundary-0.012*(U_PCC_max-U_PCC_min), ...
    I_boundary, 'Switching boundary', 'Color', Reference_Color, ...
    'FontName', Font_Name, 'FontSize', 10, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');

legend(Axes_Handle, [Unlimited_Line; Extrapolated_Line], ...
    {'Unlimited port characteristic', 'Unlimited-model extrapolation'}, ...
    'Location', 'northoutside', 'FontName', Font_Name, ...
    'FontSize', Legend_Font_Size, 'TextColor', 'k', ...
    'Color', 'w', 'EdgeColor', 'k', 'Box', 'on');

fprintf(['Fixed-E unlimited theory: U(I=Ilim)=%.6f p.u., ' ...
    'formal Ub=%.6f p.u., I(Ub,OFF)=%.6f p.u.\n'], ...
    U_current_threshold, U_boundary, I_boundary);

Figure_Base = fullfile(Options.Output_Directory, 'GFM_VI_Unlimited');
ensure_directory(fileparts(Figure_Base));
save_figure_file(Figure_Handle, Figure_Base);

Report = struct('Theory', theory, 'Figure_File', [Figure_Base '.fig']);
end

function voltage = find_current_threshold_voltage(theory, Umin, Umax)
%% 求解端口电流达到限流阈值时的残余电压。
radicand = theory.E0_pu^2 ...
    -(theory.R_L2_pu*theory.I_lim_pu)^2;
assert(radicand >= 0, 'I_lim 超出固定内电势端口方程的可行范围。');
voltage = sqrt(radicand) ...
    -theory.X_L2_pu*theory.I_lim_pu;
assert(voltage >= Umin && voltage <= Umax, ...
    '当前扫描范围内不存在 I_GFM=I_lim 交点。');
end
