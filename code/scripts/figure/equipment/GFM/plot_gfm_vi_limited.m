function Report = plot_gfm_vi_limited(Options)
%% GFM虚拟阻抗限流端口特性
% 虚拟阻抗限流下构网型变流器的 UPCC-IGFM 端口特性。
% 正式模型令 nq=0，内部电势固定为 E0；设备残余电抗完全由物理
% L2 表示，并计入 R_L2 以及两状态虚拟电抗。
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
U_PCC_min = 0.00;
U_PCC_max = 1.00;
Num_Points = 501;

assert(theory.X_vir_pu > 0, 'X_vir_device_pu 必须大于 0。');
assert(abs(GFM_Droop.nq) < 1e-12, '固定内电势理论要求 GFM_Droop.nq=0。');
assert(abs(theory.X_L2_pu-theory.X_res_device_pu) < 1e-12, ...
    '物理 L2 电抗必须等于正式 X_res_device_pu。');

Figure_Width_cm = 16;
Figure_Height_cm = 7;
Label_Font_Size = Style.Label_Size;

%% 2. 固定内电势下的两状态端口曲线
% E0^2 = [UPCC+(XL2+Slim*Xvir)*IGFM]^2+(RL2*IGFM)^2
% R_L2 很小，因此精确电流阈值位置应与正式 Ub 基本重合。
U_current_threshold = find_current_threshold_voltage( ...
    theory, U_PCC_min, U_PCC_max);
I_pre_switch = calculate_gfm_port_current(U_boundary, 0, theory);
I_post_switch = calculate_gfm_port_current(U_boundary, 1, theory);

if U_boundary <= U_PCC_min || U_boundary >= U_PCC_max
    error('正式 U_boundary=%.4f 不在扫描范围内。', U_boundary);
end

U_PCC_limited = linspace(U_PCC_min, U_boundary, Num_Points);
I_GFM_limited = calculate_gfm_port_current(U_PCC_limited, 1, theory);
U_PCC_unlimited = linspace(U_boundary, U_PCC_max, Num_Points);
I_GFM_unlimited = calculate_gfm_port_current(U_PCC_unlimited, 0, theory);
I_axis_max = 5/3*I_lim;

%% 3. 创建图窗与坐标区
Font_Name = Style.Font_Name;

Figure_Handle = new_figure([Figure_Width_cm Figure_Height_cm], Style);
Axes_Handle = axes('Parent', Figure_Handle);
style_sci_axes(Axes_Handle);
hold(Axes_Handle, 'on');

%% 4. 绘制理论特性
Curve_Color = Style.Colors.GFM;
Reference_Color = Style.Colors.Reference;

plot(Axes_Handle, U_PCC_unlimited, I_GFM_unlimited, '-', ...
    'Color', Curve_Color, 'LineWidth', 2.2, 'HandleVisibility', 'off');
plot(Axes_Handle, U_PCC_limited, I_GFM_limited, '-', ...
    'Color', Curve_Color, 'LineWidth', 2.2, 'HandleVisibility', 'off');
plot(Axes_Handle, [U_boundary, U_boundary], ...
    [I_post_switch, I_pre_switch], '-', ...
    'Color', Curve_Color, 'LineWidth', 2.2, 'HandleVisibility', 'off');

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
plot(Axes_Handle, U_boundary, I_pre_switch, 'o', ...
    'MarkerSize', 7, 'MarkerFaceColor', Reference_Color, ...
    'MarkerEdgeColor', Reference_Color, 'LineWidth', 1.0, ...
    'HandleVisibility', 'off');

%% 5. 坐标轴与文字标注
xlabel(Axes_Handle, '{\itU}^{F} (p.u.)', ...
    'FontName', 'Times New Roman', 'FontSize', Label_Font_Size, 'Color', 'k');
ylabel(Axes_Handle, '{\itI}^{GFM} (p.u.)', ...
    'FontName', 'Times New Roman', 'FontSize', Label_Font_Size, 'Color', 'k');

text(Axes_Handle, U_PCC_min+0.50*(U_boundary-U_PCC_min), ...
    0.80*I_lim, '\fontname{Times New Roman}Slope reduced due to virtual impedance', ...
    'Color', Curve_Color, 'FontName', Font_Name, 'FontSize', 10, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');

text(Axes_Handle, 0.30*(U_PCC_max-U_PCC_min), I_lim, ...
    '\fontname{Times New Roman}Current Limit {\itI}^{lim}', ...
    'Color', Reference_Color, 'FontName', Font_Name, 'FontSize', 11, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');
text(Axes_Handle, U_boundary-0.012*(U_PCC_max-U_PCC_min), ...
    0.90*I_axis_max, ...
    '\fontname{Times New Roman}State-voltage boundary {\itU}_b', ...
    'Color', Reference_Color, 'FontName', Font_Name, 'FontSize', 11, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');
text(Axes_Handle, U_boundary-0.012*(U_PCC_max-U_PCC_min), ...
    I_pre_switch, '\fontname{Times New Roman}Switching Point', 'Color', Reference_Color, ...
    'FontName', Font_Name, 'FontSize', 10, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');

fprintf(['Fixed-E theory: U(I=Ilim)=%.6f p.u., formal Ub=%.6f p.u., ' ...
    'I(Ub,OFF)=%.6f p.u., I(Ub,ON)=%.6f p.u.\n'], ...
    U_current_threshold, U_boundary, I_pre_switch, I_post_switch);

Figure_Base = fullfile(Options.Output_Directory, 'GFM_VI_Limited');
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
