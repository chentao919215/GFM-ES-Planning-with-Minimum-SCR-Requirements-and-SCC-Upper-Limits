function Report = plot_gfl_lvrt_characteristic(Options)
%% GFL LVRT附加无功电流特性
% 绘制附加无功电流随残余电压变化的分段特性。
%
% 说明：
% 1) 本图采用典型LVRT三段式外特性；
% 2) 横轴为残余PCC电压V，纵轴为附加无功电流Delta i_q^ref；
% 3) 曲线分为三段：
%    - V > V_LVRT_max              : Delta i_q^ref = 0
%    - V_LVRT_min <= V <= V_LVRT_max : Delta i_q^ref = K_q (V_LVRT_max - V) I_N
%    - V < V_LVRT_min              : Delta i_q^ref = Delta I_q^LVRT_max
% 4) 本脚本默认不依赖外部数据，直接根据给定参数绘制分段曲线；
% 5) 仅保存可编辑的FIG文件。
if nargin < 1
    Options = struct();
end

Script_Directory = fileparts(mfilename('fullpath'));
Code_Directory = fileparts(fileparts(fileparts(fileparts(Script_Directory))));
addpath(fullfile(Code_Directory, 'functions', 'utils'));
Project_Root = find_project_root(Script_Directory);
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
Options = figure_options(Options, struct('Output_Directory', fullfile(Project_Root, 'figs', 'equipment', ...
    'GFL')));
Style = figure_style('review');
Style.Visible = Options.Visible;
Style.Close_After_Save = Options.Close_After_Save;

%% 1. LVRT 参数（请在此输入）

% LVRT无功支撑启动电压阈值 V_LVRT_max
V_LVRT_max = 0.90;          % p.u.

% LVRT无功电流饱和电压阈值 V_LVRT_min
V_LVRT_min = 0.20;          % p.u.

% LVRT无功电流注入系数 K_q
K_q = 1.5;                  % p.u./p.u. 或按你的定义填写

% 额定电流 I_N
I_N = 1.0;                  % 若采用标幺值绘图，可取 1.0

% 是否手动指定最大附加无功电流Delta I_q^LVRT_max
Use_Manual_Iq_Max = false;

% 手动指定值（仅当 Use_Manual_Iq_Max = true 时生效）
Delta_Iq_LVRT_max_manual = 1.40;   % p.u.

% 若不手动指定，则默认按公式自动计算：
% Delta I_q^LVRT_max = K_q (V_LVRT_max - V_LVRT_min) I_N

%% 2. 绘图范围与采样设置

% 横轴绘图范围
V_plot_min = 0.00;          % p.u.
V_plot_max = 1.10;          % p.u.

% 曲线采样点数
Num_Points = 1200;

%% 3. 单位显示设置

% 电流纵轴显示模式：
% 'pu'  -> 以标幺值显示
% 'A'   -> 以 A 显示
% 'kA'  -> 以 kA 显示
Current_Display_Mode = 'pu';

% 若 I_N 以 A 为单位输入，则可切换为 A / kA 显示；
% 若 I_N 取 1.0 且使用标幺绘图，则建议保持 'pu'

%% 4. 区域标识与辅助线设置

% 是否显示三段区域底色
Show_Region_Patch = true;

% 是否显示阈值竖线与饱和电流水平线
Show_Auxiliary_Lines = false;

% 是否标注三段运行区间
Show_Region_Text = true;

%% 5. 图窗与格式设置

% 图窗大小
Figure_Width_cm = 16;
Figure_Height_cm = 7;

% 线宽设置
Lw_Curve = Style.Line_Width;
Lw_Aux = 1.2;
Lw_Axis = Style.Axis_Width;

% 字体与线宽由共用样式维护。
Font_Name = Style.Font_Name;
Font_Size = Style.Font_Size;

% 沿用Manuscript配色。
Color_Curve = Style.Colors.GFL;
Color_Aux = [0.3000, 0.3000, 0.3000];     % 灰
Color_Sat = Style.Colors.Reference;
Color_Zero = [0.45, 0.45, 0.45];          % 中灰

% 区域底色
Color_Region_1 = 0.2*Style.Colors.SCR+0.8;        % 浅蓝
Color_Region_2 = 0.2*Style.Colors.GFL+0.8;        % 浅绿
Color_Region_3 = [0.94, 0.94, 0.94];        % 浅灰

% 坐标轴标签使用TeX数学符号。
X_Label_Text = ['\fontname{' Font_Name '}{\itV}^F (p.u.)'];
Y_Label_Text_pu = ['\fontname{' Font_Name '}{\it\Delta I}^{GFL} (p.u.)'];
Y_Label_Text_A = ['\fontname{' Font_Name '}Additional reactive current ' ...
    '\fontname{' Font_Name '}{\it\Delta I_q}^{ref}'...
    '\fontname{' Font_Name '}/A'];
Y_Label_Text_kA = ['\fontname{' Font_Name '}Additional reactive current ' ...
    '\fontname{' Font_Name '}{\it\Delta I_q}^{ref}'...
    '\fontname{' Font_Name '}/kA'];

% 图例位置
Legend_Location = 'northeast';

%% 6. 保存设置

% 图件保存路径（FIG）
Figure_Base = fullfile(Options.Output_Directory, 'GFL_LVRT_Reactive_Current');

%% 7. 参数预处理

% 参数合法性检查
if V_LVRT_min >= V_LVRT_max
    error('参数错误：应满足 V_LVRT_min < V_LVRT_max。');
end

if V_plot_min >= V_plot_max
    error('参数错误：应满足 V_plot_min < V_plot_max。');
end

if Use_Manual_Iq_Max
    Delta_Iq_LVRT_max = Delta_Iq_LVRT_max_manual;
else
    Delta_Iq_LVRT_max = K_q * (V_LVRT_max - V_LVRT_min) * I_N;
end

% 生成横轴采样点
V = linspace(V_plot_min, V_plot_max, Num_Points);

% 计算附加无功电流
Delta_iq_ref = zeros(size(V));

Idx_Region_1 = V > V_LVRT_max;
Idx_Region_2 = (V >= V_LVRT_min) & (V <= V_LVRT_max);
Idx_Region_3 = V < V_LVRT_min;

Delta_iq_ref(Idx_Region_1) = 0;
Delta_iq_ref(Idx_Region_2) = K_q .* (V_LVRT_max - V(Idx_Region_2)) .* I_N;
Delta_iq_ref(Idx_Region_3) = Delta_Iq_LVRT_max;

% 电流显示单位转换
switch lower(Current_Display_Mode)
    case 'pu'
        Y_Plot = Delta_iq_ref / I_N;
        Y_Sat_Plot = Delta_Iq_LVRT_max / I_N;
        Y_Label_Text = Y_Label_Text_pu;

    case 'a'
        Y_Plot = Delta_iq_ref;
        Y_Sat_Plot = Delta_Iq_LVRT_max;
        Y_Label_Text = Y_Label_Text_A;

    case 'ka'
        Y_Plot = Delta_iq_ref * 1e-3;
        Y_Sat_Plot = Delta_Iq_LVRT_max * 1e-3;
        Y_Label_Text = Y_Label_Text_kA;

    otherwise
        error('不支持的 current_display_mode：%s', Current_Display_Mode);
end

% 纵轴上限自动设置
Y_Max = max(Y_Plot);
if Y_Max <= 0
    Y_Max = 1;
end
Y_Lim_Upper = 1.15 * Y_Max;

%% 8. 创建图窗与坐标区

fig = new_figure([Figure_Width_cm Figure_Height_cm], Style);
ax = axes(fig);
hold(ax, 'on');
box(ax, 'on');
style_sci_axes(ax);

% 零轴
yline(ax, 0, '-', ...
    'Color', Color_Zero, ...
    'LineWidth', 1.1, ...
    'HandleVisibility', 'off');

% 三段区域底色
if Show_Region_Patch
    % 区域3：V < V_LVRT_min（饱和区）
    patch(ax, ...
        [V_plot_min, V_LVRT_min, V_LVRT_min, V_plot_min], ...
        [0, 0, Y_Lim_Upper, Y_Lim_Upper], ...
        Color_Region_3, ...
        'EdgeColor', 'none', ...
        'FaceAlpha', 0.25, ...
        'HandleVisibility', 'off');

    % 区域2：V_LVRT_min <= V <= V_LVRT_max（线性区）
    patch(ax, ...
        [V_LVRT_min, V_LVRT_max, V_LVRT_max, V_LVRT_min], ...
        [0, 0, Y_Lim_Upper, Y_Lim_Upper], ...
        Color_Region_2, ...
        'EdgeColor', 'none', ...
        'FaceAlpha', 0.20, ...
        'HandleVisibility', 'off');

    % 区域1：V > V_LVRT_max（无附加无功区）
    patch(ax, ...
        [V_LVRT_max, V_plot_max, V_plot_max, V_LVRT_max], ...
        [0, 0, Y_Lim_Upper, Y_Lim_Upper], ...
        Color_Region_1, ...
        'EdgeColor', 'none', ...
        'FaceAlpha', 0.20, ...
        'HandleVisibility', 'off');
end

% 主曲线
H_Curve = plot(ax, V, Y_Plot, ...
    'Color', Color_Curve, ...
    'LineWidth', Lw_Curve);

% 阈值辅助线与饱和值辅助线
if Show_Auxiliary_Lines
    xline(ax, V_LVRT_max, '--', ...
        'Color', Color_Aux, ...
        'LineWidth', Lw_Aux, ...
        'HandleVisibility', 'off');

    xline(ax, V_LVRT_min, '--', ...
        'Color', Color_Aux, ...
        'LineWidth', Lw_Aux, ...
        'HandleVisibility', 'off');

    H_Sat = yline(ax, Y_Sat_Plot, '--', ...
        'Color', Color_Sat, ...
        'LineWidth', Lw_Aux);
end

% 坐标轴范围
xlim(ax, [V_plot_min, V_plot_max]);
ylim(ax, [0, Y_Lim_Upper]);

% 区域文字说明
if Show_Region_Text
    % 区域1
    text(ax, ...
        0.5 * (V_LVRT_max + V_plot_max), ...
        0.58 * Y_Lim_Upper, ...
        {['\fontname{' Font_Name '}LVRT'], ...
        ['\fontname{' Font_Name '}inactive region']}, ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontName', Font_Name, ...
        'FontSize', Font_Size, ...
        'Color', Color_Aux);

    % 区域2
    text(ax, ...
        0.53 * (V_LVRT_min + V_LVRT_max), ...
        0.58 * Y_Lim_Upper, ...
        {['\fontname{' Font_Name '}LVRT'], ...
        ['\fontname{' Font_Name '}active region']}, ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontName', Font_Name, ...
        'FontSize', Font_Size, ...
        'Color', Color_Aux);

    % 区域3
    text(ax, ...
        0.65 * (V_plot_min + V_LVRT_min), ...
        0.58 * Y_Lim_Upper, ...
        {['\fontname{' Font_Name '}LVRT'], ...
        ['\fontname{' Font_Name '}saturated region']}, ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontName', Font_Name, ...
        'FontSize', Font_Size, ...
        'Color', Color_Aux);
end

% 阈值标签
text(ax, V_LVRT_max, 0.05 * Y_Lim_Upper, ...
    ['\fontname{' Font_Name '}{\itV}^{LVRT,on}'], ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'bottom', ...
    'FontName', Font_Name, ...
    'FontSize', Font_Size, ...
    'Color', Color_Aux);

text(ax, V_LVRT_min, 0.02 * Y_Lim_Upper, ...
    ['\fontname{' Font_Name '}{\itV}^{LVRT,sat}'], ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'bottom', ...
    'FontName', Font_Name, ...
    'FontSize', Font_Size, ...
    'Color', Color_Aux);

% 图例
if Show_Auxiliary_Lines
    legend(ax, [H_Curve, H_Sat], ...
        {'Additional reactive current', 'Maximum reactive current'}, ...
        'Location', Legend_Location, ...
        'Interpreter', 'tex', ...
        'FontName', Font_Name, ...
        'FontSize', Font_Size);
end

% 美化
set(ax, ...
    'Layer', 'top', ...
    'LineWidth', Lw_Axis, ...
    'FontName', Font_Name, ...
    'FontSize', Font_Size, ...
    'GridAlpha', Style.Grid_Alpha);

% 坐标轴标签
xlabel(ax, X_Label_Text, ...
    'Interpreter', 'tex', ...
    'FontName', Font_Name, ...
    'FontSize', 12);

ylabel(ax, Y_Label_Text, ...
    'Interpreter', 'tex', ...
    'FontName', Font_Name, ...
    'FontSize', 12);

save_figure_file(fig, Figure_Base);

%% 9. 输出关键信息

fprintf('绘图完成：LVRT附加无功电流特性已保存为FIG。\n');
fprintf('V_LVRT_max = %.4f p.u.\n', V_LVRT_max);
fprintf('V_LVRT_min = %.4f p.u.\n', V_LVRT_min);
fprintf('K_q = %.4f\n', K_q);
fprintf('I_N = %.4f\n', I_N);
fprintf('Delta I_q^LVRT_max = %.4f\n', Delta_Iq_LVRT_max);

Report = struct('Voltage_pu', V, 'Reactive_Current', Delta_iq_ref, 'Figure_File', [Figure_Base '.fig']);
end
