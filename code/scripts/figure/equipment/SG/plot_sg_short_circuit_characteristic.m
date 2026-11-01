function Report = plot_sg_short_circuit_characteristic(Options)
%% 同步机初始对称短路电流端口特性
% 传统同步发电机初始对称短路电流的 UPCC-ISG 理论外特性。
% 采用三相对称故障初始时刻的次暂态端口模型：
%     ISG = (E'' - UPCC) / (j*X'')
% 在本扫描范围内 UPCC <= E''，因此电流幅值为：
%     |ISG| = (E'' - UPCC) / X''
if nargin < 1
    Options = struct();
end

Script_Directory = fileparts(mfilename('fullpath'));
Code_Directory = fileparts(fileparts(fileparts(fileparts(Script_Directory))));
addpath(fullfile(Code_Directory, 'functions', 'utils'));
Project_Root = find_project_root(Script_Directory);
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
Options = figure_options(Options, struct('Output_Directory', fullfile(Project_Root, 'figs', 'equipment', ...
    'SG')));
Style = figure_style('review');
Style.Visible = Options.Visible;
Style.Close_After_Save = Options.Close_After_Save;

%% 1. 理论参数与扫描范围
E_subtransient_pu = 1.0;
X_subtransient_pu = 0.10;

U_PCC_min = 0.3;
U_PCC_max = 1.0;
Num_Points = 501;

assert(U_PCC_max <= E_subtransient_pu, ...
    '扫描范围必须满足 U_PCC <= E''''。');

U_PCC = linspace(U_PCC_min, U_PCC_max, Num_Points);
I_SG = abs(E_subtransient_pu - U_PCC) ./ X_subtransient_pu;

%% 2. 图窗与坐标区参数
Figure_Width_cm = 14.8;
Figure_Height_cm = 10.5;
Label_Font_Size = Style.Label_Size;
Legend_Font_Size = Style.Legend_Size;

% 纵轴按理论最大电流自动设置，并在顶部预留约 10% 空间。
I_axis_max = 1.10 * max(I_SG);

%% 3. 共用字体与图窗
Font_Name = Style.Font_Name;

Figure_Handle = new_figure([Figure_Width_cm Figure_Height_cm], Style);
Axes_Handle = axes('Parent', Figure_Handle);
style_sci_axes(Axes_Handle);
hold(Axes_Handle, 'on');

%% 4. 绘制同步机理论外特性
SG_Line = plot(Axes_Handle, U_PCC, I_SG, '-', ...
    'Color', Style.Colors.SG, 'LineWidth', 2.2, ...
    'DisplayName', 'Initial symmetrical fault current');

xlim(Axes_Handle, [U_PCC_min, U_PCC_max]);
ylim(Axes_Handle, [0, I_axis_max]);
xticks(Axes_Handle, linspace(U_PCC_min, U_PCC_max, 5));
yticks(Axes_Handle, 0:1:ceil(I_axis_max));

%% 5. 坐标轴标签与图例
xlabel(Axes_Handle, '|{\itU}^{PCC}|/{\itU}^N', ...
    'FontName', 'Times New Roman', 'FontSize', Label_Font_Size, 'Color', 'k');
ylabel(Axes_Handle, '|{\itI}^{SG}|/{\itI}^N', ...
    'FontName', 'Times New Roman', 'FontSize', Label_Font_Size, 'Color', 'k');

legend(Axes_Handle, SG_Line, {'Initial symmetrical fault current'}, ...
    'Location', 'northeast', 'FontName', Font_Name, ...
    'FontSize', Legend_Font_Size, 'TextColor', 'k', ...
    'Color', 'w', 'EdgeColor', 'k', 'Box', 'on');

Figure_Base = fullfile(Options.Output_Directory, 'SG_ShortCircuit_Characteristic');
ensure_directory(fileparts(Figure_Base));
save_figure_file(Figure_Handle, Figure_Base);

Report = struct('Voltage_pu', U_PCC, 'Current_pu', I_SG, 'Figure_File', [Figure_Base '.fig']);
end
