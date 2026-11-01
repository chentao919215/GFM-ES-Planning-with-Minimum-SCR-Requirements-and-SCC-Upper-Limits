function Report = plot_gfl_lvrt_validation(Options)
%PLOT_GFL_LVRT_VALIDATION 读取设备验证结果并绘制LVRT端口特性，不运行Simulink。
% 请先运行equipment/validation/run_gfl_lvrt_validation.m。
if nargin < 1
    Options = struct();
end

Script_Directory = fileparts(mfilename('fullpath'));
Code_Directory = fileparts(fileparts(fileparts(fileparts(Script_Directory))));
addpath(fullfile(Code_Directory, 'functions', 'utils'));
Project_Root = find_project_root(Script_Directory);
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
Options = figure_options(Options, struct('Result_File', fullfile(Project_Root, 'results', 'equipment', ...
    'GFL', 'GFL_LVRT_Validation_Result.mat'), ...
    'Output_Directory', fullfile(Project_Root, 'figs', 'equipment', 'GFL')));
Style = figure_style('review');
Style.Visible = Options.Visible;
Style.Close_After_Save = Options.Close_After_Save;
Result_File = Options.Result_File;
if ~isfile(Result_File)
    error('GFLValidation:MissingValidationResult', ...
        'Validation data missing: %s. Run run_gfl_lvrt_validation first.', Result_File);
end
loaded = load(Result_File, 'data_table', 'error_table', 'parameter_snapshot');
assert(all(isfield(loaded, {'data_table', 'error_table', 'parameter_snapshot'})), ...
    'GFLValidation:InvalidValidationResult', 'Validation result is incomplete.');
data_table = loaded.data_table;
error_table = loaded.error_table;
parameter_snapshot = loaded.parameter_snapshot;
Required_Columns = {'USimF_pu', 'IdSimF_pu', 'IqSimF_pu', 'ISimF_pu', ...
    'IdEqF_pu', 'IqEqF_pu', 'IEqF_pu'};
assert(istable(data_table) && height(data_table)>0 && ...
    all(ismember(Required_Columns, data_table.Properties.VariableNames)), ...
    'GFLValidation:InvalidValidationResult', 'Validation data columns are incomplete.');
assert(all(isfinite(data_table{:, Required_Columns}), 'all'), ...
    'GFLValidation:InvalidValidationResult', 'Validation data must be finite.');
u_sim = data_table.USimF_pu;
ID_Sim = data_table.IdSimF_pu;
Iq_Sim = data_table.IqSimF_pu;
I_Sim = data_table.ISimF_pu;
ID_Eq = data_table.IdEqF_pu;
Iq_Eq = data_table.IqEqF_pu;
I_Eq = data_table.IEqF_pu;
U_lim = parameter_snapshot.U_lim_pu;
V_LVRT_max = parameter_snapshot.V_LVRT_max_pu;
V_LVRT_min = parameter_snapshot.V_LVRT_min_pu;
Output_Dir = Options.Output_Directory;
if ~isfolder(Output_Dir)
    mkdir(Output_Dir);
end

%% 1. 画图部分：绘制LVRT端口特性并保存FIG
fig = new_figure(2.54*[7.6 8.2], Style);
tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

[u_line, idx] = sort(u_sim, 'ascend');
Iq_Line = Iq_Eq(idx);
ID_Line = ID_Eq(idx);
I_Line = I_Eq(idx);

ax1 = nexttile(tl);
plot(ax1, u_line, Iq_Line, '-', 'Color', Style.Colors.GFL, ...
    'LineWidth', 1.5, 'DisplayName', 'Port-equivalent model');
hold(ax1, 'on');
scatter(ax1, u_sim, Iq_Sim, 30, Style.Colors.Reference, 'filled', ...
    'DisplayName', 'Full model');
add_voltage_guides(ax1, U_lim, V_LVRT_max, V_LVRT_min);
hold(ax1, 'off');
ylabel(ax1, 'Reactive current {\itI_q}^F (p.u.)', ...
    'Interpreter', 'tex');
xlabel(ax1, voltage_axis_label(), 'Interpreter', 'tex');

ax2 = nexttile(tl);
plot(ax2, u_line, ID_Line, '-', 'Color', Style.Colors.GFL, ...
    'LineWidth', 1.5, 'DisplayName', 'Port-equivalent model');
hold(ax2, 'on');
scatter(ax2, u_sim, ID_Sim, 30, Style.Colors.Reference, 'filled', ...
    'DisplayName', 'Full model');
add_voltage_guides(ax2, U_lim, V_LVRT_max, V_LVRT_min);
hold(ax2, 'off');
ylabel(ax2, 'Active current {\itI_d}^F (p.u.)', ...
    'Interpreter', 'tex');
xlabel(ax2, voltage_axis_label(), 'Interpreter', 'tex');

ax3 = nexttile(tl);
H_I_Eq = plot(ax3, u_line, I_Line, '-', 'Color', Style.Colors.GFL, ...
    'LineWidth', 1.5, 'DisplayName', 'Port-equivalent model');
hold(ax3, 'on');
H_I_Sim = scatter(ax3, u_sim, I_Sim, 30, Style.Colors.Reference, 'filled', ...
    'DisplayName', 'Full model');
h09 = xline(ax3, V_LVRT_max, '--', 'Color', [34 34 34]/255, ...
    'LineWidth', 0.9, ...
    'DisplayName', 'LVRT activation threshold');
hlim = xline(ax3, U_lim, '-.', 'Color', [196 123 67]/255, ...
    'LineWidth', 1.0, ...
    'DisplayName', 'Theoretical current-limit boundary');
h02 = xline(ax3, V_LVRT_min, ':', 'Color', [34 34 34]/255, ...
    'LineWidth', 0.9, ...
    'DisplayName', 'Reactive-current saturation threshold');
hold(ax3, 'off');
xlabel(ax3, voltage_axis_label(), 'Interpreter', 'tex');
ylabel(ax3, 'Current magnitude |{\itI}^F| (p.u.)', ...
    'Interpreter', 'tex');

Axes_List = [ax1 ax2 ax3];
for ax = Axes_List
    style_sci_axes(ax);
end
legend(ax3, [H_I_Sim H_I_Eq h09 hlim h02], ...
    {'Full model', 'Port-equivalent model', 'LVRT activation threshold', ...
    'Theoretical current-limit boundary', 'Reactive-current saturation threshold'}, ...
    'Location', 'southoutside', 'NumColumns', 2, ...
    'Interpreter', 'none', 'FontName', 'Times New Roman');
Fig_Base = fullfile(Output_Dir, 'GFL_LVRT_Validation');
save_figure_file(fig, Fig_Base);

fprintf('GFL LVRT validation saved to %s.fig\n', Fig_Base);
Report = struct('parameters', parameter_snapshot, 'data', data_table, ...
    'errors', error_table, 'figure_file', [Fig_Base '.fig'], ...
    'mat_file', char(Result_File));
end

function add_voltage_guides(ax, u_lim, V_Max, V_Min)
%% 标记LVRT启动、无功饱和及理论电流限值边界。
xline(ax, V_Max, '--', 'Color', [34 34 34]/255, 'LineWidth', 0.9, ...
    'DisplayName', 'LVRT activation threshold');
xline(ax, u_lim, '-.', 'Color', [196 123 67]/255, 'LineWidth', 1.0, ...
    'DisplayName', 'Theoretical current-limit boundary');
xline(ax, V_Min, ':', 'Color', [34 34 34]/255, 'LineWidth', 0.9, ...
    'DisplayName', 'Reactive-current saturation threshold');
end

function label = voltage_axis_label()
%% 生成残余PCC电压的英文坐标标签。
label = '\fontname{Times New Roman}Residual PCC voltage  \fontname{Times New Roman}|{\itU}_{sim}^F| (p.u.)';
end
