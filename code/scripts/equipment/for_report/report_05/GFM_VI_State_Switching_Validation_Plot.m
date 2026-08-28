function [figure_handle, plot_data, transition_table] = ...
        GFM_VI_State_Switching_Validation_Plot(simulation_result)
%% GFM_VI_State_Switching_Validation_Plot
% 虚拟阻抗限流状态切换验证图
%
% 本函数只读取 Grid_Forming_Inverters.slx 已产生的仿真结果，不运行或
% 修改模型。图中仅显示 UPCC 和 IGFM；仍直接采用 logsout 中记录的 Slim
% 统计状态跃迁并标注投入/退出时刻，不根据电压、电流重构状态。
%
% 调用方式：
%   GFM_VI_State_Switching_Validation_Plot
%   GFM_VI_State_Switching_Validation_Plot(simOut)
%   [figure_handle, plot_data, transition_table] = ...
%       GFM_VI_State_Switching_Validation_Plot(simOut);

close all;
clc;

%% 参数设置（集中修改区）
% 不传入 simulation_result 时，从基础工作区读取该变量。
simulation_result_name = 'simOut';

% 绘图时间范围。[] 表示全部时间；也可改为 [0, 6]。
time_window_s = [];

% 阈值覆盖值。[] 表示采用 logsout 中记录的模型参数。
U_boundary_override_pu = [];
I_threshold_override_pu = [];
release_confirm_time_override_s = [];

% Case 边界。[] 表示从 GFM_GridSource.CaseB/CaseC 自动读取。
% 也可直接设置为 [2, 4]。
case_boundary_times_s = [];
case_names = {'Case A', 'Case B', 'Case C'};
show_case_boundaries = true;
show_case_names = true;

% 状态标注选项。
show_transition_labels = true;

% 图窗尺寸与字体参数（宽高比约 2.4，适合 PPT 横向双面板布局）。
figure_width_cm = 18.0;
figure_height_cm = 7.5;
axis_font_size = 10.5;
label_font_size = 13;

% 导出选项。默认只显示图窗；需要 PNG 时改为 true。
% export_figure = false;
% output_file = fullfile(fileparts(mfilename('fullpath')), ...
%     'GFM_VI_State_Switching_Validation.png');
% export_resolution_dpi = 300;

%% 读取仿真结果
if nargin < 1 || isempty(simulation_result)
    if ~isvarname(simulation_result_name)
        error('simulation_result_name 不是有效的 MATLAB 变量名。');
    end
    result_exists = evalin('base', sprintf( ...
        'exist(''%s'', ''var'')', simulation_result_name));
    if result_exists ~= 1
        error(['基础工作区中未找到仿真结果变量 %s。\n' ...
            '请先运行 Grid_Forming_Inverters.slx，或把仿真结果传入本函数。'], ...
            simulation_result_name);
    end
    simulation_result = evalin('base', simulation_result_name);
end

if isa(simulation_result, 'Simulink.SimulationOutput')
    result_variable_names = simulation_result.who;
    if ~any(strcmp(result_variable_names, 'logsout'))
        error(['仿真结果中没有 logsout。请确认模型已开启 Signal Logging，' ...
            '且 GFM_VI.LogSignals = true。']);
    end
    logsout = simulation_result.get('logsout');
elseif isa(simulation_result, 'Simulink.SimulationData.Dataset')
    logsout = simulation_result;
else
    error(['simulation_result 必须是 Simulink.SimulationOutput 或 ' ...
        'Simulink.SimulationData.Dataset，当前类型为 %s。'], ...
        class(simulation_result));
end

if ~isa(logsout, 'Simulink.SimulationData.Dataset')
    error('logsout 不是 Simulink.SimulationData.Dataset。');
end

% 先检查名称，再调用 getElement，避免缺失名称产生连续警告。
logged_signal_names = logsout.getElementNames;
required_signal_names = {'U_PCC_pu', 'I_GFM_mag_pu', 'Slim'};
missing_signal_names = required_signal_names( ...
    ~ismember(required_signal_names, logged_signal_names));
if ~isempty(missing_signal_names)
    error(['logsout 缺少绘图所需信号：%s。\n' ...
        '请确认 GFM_VI.LogSignals = true，并重新运行模型。'], ...
        strjoin(missing_signal_names, ', '));
end

U_PCC_ts = logsout.getElement('U_PCC_pu').Values;
I_GFM_ts = logsout.getElement('I_GFM_mag_pu').Values;
Slim_ts = logsout.getElement('Slim').Values;

if ~isa(U_PCC_ts, 'timeseries') || ...
        ~isa(I_GFM_ts, 'timeseries') || ...
        ~isa(Slim_ts, 'timeseries')
    error('U_PCC_pu、I_GFM_mag_pu 和 Slim 必须记录为 timeseries。');
end

%% 读取状态边界和恢复确认时间
if isempty(U_boundary_override_pu)
    U_boundary_pu = localReadLoggedScalar( ...
        logsout, logged_signal_names, 'U_boundary_pu');
else
    U_boundary_pu = U_boundary_override_pu;
end

if isempty(I_threshold_override_pu)
    I_threshold_pu = localReadLoggedScalar( ...
        logsout, logged_signal_names, 'I_switch_threshold_pu');
else
    I_threshold_pu = I_threshold_override_pu;
end

if isempty(release_confirm_time_override_s)
    if ismember('ReleaseConfirmTime_s', logged_signal_names)
        release_confirm_time_s = localReadLoggedScalar( ...
            logsout, logged_signal_names, 'ReleaseConfirmTime_s');
    else
        release_confirm_time_s = NaN;
    end
else
    release_confirm_time_s = release_confirm_time_override_s;
end

if ~isscalar(U_boundary_pu) || ~isfinite(U_boundary_pu)
    error('U_boundary_pu 必须是有限标量。');
end
if ~isscalar(I_threshold_pu) || ~isfinite(I_threshold_pu)
    error('I_threshold_pu 必须是有限标量。');
end

%% 整理并对齐模型输出
[time_s, S_lim] = localTimeseriesData(Slim_ts, 'Slim');
S_lim = double(S_lim >= 0.5);

[U_time_s, U_PCC_pu_raw] = ...
    localTimeseriesData(U_PCC_ts, 'U_PCC_pu');
[I_time_s, I_GFM_pu_raw] = ...
    localTimeseriesData(I_GFM_ts, 'I_GFM_mag_pu');

common_start_s = max([time_s(1), U_time_s(1), I_time_s(1)]);
common_end_s = min([time_s(end), U_time_s(end), I_time_s(end)]);
valid_time = time_s >= common_start_s & time_s <= common_end_s;
time_s = time_s(valid_time);
S_lim = S_lim(valid_time);
if numel(time_s) < 2
    error('U_PCC_pu、I_GFM_mag_pu 与 Slim 没有足够的公共时间范围。');
end

U_PCC_pu = localInterpolate(U_time_s, U_PCC_pu_raw, ...
    time_s, 'linear');
I_GFM_pu = localInterpolate(I_time_s, I_GFM_pu_raw, ...
    time_s, 'linear');

% 可选记录：恢复确认计时和实际投入虚拟电抗。
release_elapsed_s = nan(size(time_s));
if ismember('ReleaseConfirmElapsed_s', logged_signal_names)
    release_ts = logsout.getElement('ReleaseConfirmElapsed_s').Values;
    [release_time_s, release_data_s] = ...
        localTimeseriesData(release_ts, 'ReleaseConfirmElapsed_s');
    release_elapsed_s = localInterpolate(release_time_s, ...
        release_data_s, time_s, 'previous');
end

X_vir_applied_pu = nan(size(time_s));
if ismember('X_vir_applied_pu', logged_signal_names)
    X_vir_ts = logsout.getElement('X_vir_applied_pu').Values;
    [X_vir_time_s, X_vir_data_pu] = ...
        localTimeseriesData(X_vir_ts, 'X_vir_applied_pu');
    X_vir_applied_pu = localInterpolate(X_vir_time_s, ...
        X_vir_data_pu, time_s, 'previous');
end

% 按需截取绘图时间范围。
if ~isempty(time_window_s)
    if ~isnumeric(time_window_s) || numel(time_window_s) ~= 2 || ...
            ~all(isfinite(time_window_s)) || ...
            time_window_s(2) <= time_window_s(1)
        error('time_window_s 必须为空或形如 [t_start, t_end] 的递增向量。');
    end
    in_window = time_s >= time_window_s(1) & ...
        time_s <= time_window_s(2);
    time_s = time_s(in_window);
    U_PCC_pu = U_PCC_pu(in_window);
    I_GFM_pu = I_GFM_pu(in_window);
    S_lim = S_lim(in_window);
    release_elapsed_s = release_elapsed_s(in_window);
    X_vir_applied_pu = X_vir_applied_pu(in_window);
    if numel(time_s) < 2
        error('time_window_s 内没有足够的仿真数据。');
    end
end

%% 自动统计状态跃迁
transition_index = find(diff(S_lim) ~= 0) + 1;
transition_times_s = time_s(transition_index);
from_state = S_lim(transition_index - 1);
to_state = S_lim(transition_index);

transition_direction = strings(numel(transition_index), 1);
transition_direction(from_state == 0 & to_state == 1) = "OFF->ON";
transition_direction(from_state == 1 & to_state == 0) = "ON->OFF";

transition_table = table(transition_times_s, transition_direction, ...
    from_state, to_state, 'VariableNames', ...
    {'Time_s', 'Direction', 'FromState', 'ToState'});

plot_data = struct();
plot_data.Time_s = time_s;
plot_data.U_PCC_pu = U_PCC_pu;
plot_data.I_GFM_mag_pu = I_GFM_pu;
plot_data.Slim = S_lim;
plot_data.X_vir_applied_pu = X_vir_applied_pu;
plot_data.ReleaseConfirmElapsed_s = release_elapsed_s;
plot_data.U_boundary_pu = U_boundary_pu;
plot_data.I_switch_threshold_pu = I_threshold_pu;
plot_data.ReleaseConfirmTime_s = release_confirm_time_s;

fprintf('\n=== 虚拟阻抗限流状态切换验证 ===\n');
fprintf('状态跃迁总次数：%d\n', height(transition_table));
fprintf('U_boundary = %.6f p.u.\n', U_boundary_pu);
fprintf('I_switch_threshold = %.6f p.u.\n', I_threshold_pu);
if isfinite(release_confirm_time_s)
    fprintf('ReleaseConfirmTime = %.6f s\n', release_confirm_time_s);
end
if isempty(transition_table)
    fprintf('当前时间范围内没有检测到状态跃迁。\n');
else
    disp(transition_table);
end

%% 自动读取 Case A / B / C 的时间边界
if isempty(case_boundary_times_s) && show_case_boundaries
    has_grid_source = evalin('base', ...
        'exist(''GFM_GridSource'', ''var'')') == 1;
    if has_grid_source
        grid_source = evalin('base', 'GFM_GridSource');
        if isstruct(grid_source) && ...
                isfield(grid_source, 'CaseB') && ...
                isfield(grid_source, 'CaseC') && ...
                isfield(grid_source.CaseB, 'StartTime_s') && ...
                isfield(grid_source.CaseC, 'StartTime_s')
            case_boundary_times_s = [grid_source.CaseB.StartTime_s, ...
                grid_source.CaseC.StartTime_s];
        end
    end
end
case_boundary_times_s = case_boundary_times_s(:).';
case_boundary_times_s = case_boundary_times_s( ...
    case_boundary_times_s > time_s(1) & ...
    case_boundary_times_s < time_s(end));

%% 创建图窗和坐标区
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

figure_handle = figure('Color', 'w', ...
    'Units', 'centimeters', ...
    'Position', [2.0, 1.0, figure_width_cm, figure_height_cm], ...
    'PaperPositionMode', 'auto');

axes_U = subplot(2, 1, 1, 'Parent', figure_handle);
axes_I = subplot(2, 1, 2, 'Parent', figure_handle);
axes_list = [axes_U, axes_I];

% 坐标轴和网格风格沿用 GFM_VI_Limited.m。
for axes_index = 1:numel(axes_list)
    axes_handle = axes_list(axes_index);
    axes_handle.Color = [0.98, 0.985, 0.99];
    axes_handle.FontName = 'Times New Roman';
    axes_handle.FontSize = axis_font_size;
    axes_handle.LineWidth = 1.0;
    axes_handle.TickDir = 'out';
    axes_handle.Box = 'on';
    hold(axes_handle, 'on');
    grid(axes_handle, 'on');
    axes_handle.XMinorGrid = 'on';
    axes_handle.YMinorGrid = 'on';
    axes_handle.GridLineStyle = '--';
    axes_handle.MinorGridLineStyle = ':';
    axes_handle.GridColor = [0.72, 0.82, 0.90];
    axes_handle.MinorGridColor = [0.80, 0.87, 0.93];
    axes_handle.GridAlpha = 0.70;
    axes_handle.MinorGridAlpha = 0.60;
end

%% 绘制 UPCC 和 IGFM
blue_color = [0.0000, 0.4470, 0.7410];
navy_color = [0.1216, 0.3059, 0.4745];
red_color = [0.85, 0.15, 0.15];
green_color = [0.20, 0.58, 0.27];
gray_color = [0.42, 0.46, 0.50];

plot(axes_U, time_s, U_PCC_pu, '-', ...
    'Color', blue_color, 'LineWidth', 1.7);
plot(axes_U, [time_s(1), time_s(end)], ...
    [U_boundary_pu, U_boundary_pu], '--', ...
    'Color', red_color, 'LineWidth', 1.3);
ylabel(axes_U, '{\itU}^{PCC}/{\itU}^{N}', ...
    'FontName', 'Times New Roman', 'FontSize', label_font_size);
yticks(0:0.5:1.5);

plot(axes_I, time_s, I_GFM_pu, '-', ...
    'Color', navy_color, 'LineWidth', 1.7);
plot(axes_I, [time_s(1), time_s(end)], ...
    [I_threshold_pu, I_threshold_pu], '--', ...
    'Color', red_color, 'LineWidth', 1.3);
ylabel(axes_I, '|{\itI}^{GFM}|/{\itI}^{N}', ...
    'FontName', 'Times New Roman', 'FontSize', label_font_size);

xlabel(axes_I, '时间/\fontname{Times New Roman}s', ...
    'FontName', font_name, 'FontSize', label_font_size - 1);

finite_U = U_PCC_pu(isfinite(U_PCC_pu));
finite_I = I_GFM_pu(isfinite(I_GFM_pu));
if isempty(finite_U) || isempty(finite_I)
    error('U_PCC_pu 或 I_GFM_mag_pu 没有有限数值，无法绘图。');
end

U_limits = [min([finite_U; U_boundary_pu]), ...
    max([finite_U; U_boundary_pu])];
U_span = max(diff(U_limits), 0.05);
ylim(axes_U, [U_limits(1) - 0.08 * U_span, ...
    U_limits(2) + 0.15 * U_span]);

I_upper = max([finite_I; I_threshold_pu]);
ylim(axes_I, [0, max(1.10 * I_upper, I_threshold_pu + 0.1)]);

for axes_index = 1:numel(axes_list)
    xlim(axes_list(axes_index), [time_s(1), time_s(end)]);
end
linkaxes(axes_list, 'x');

% 阈值文字位置可在这里直接手动修改。
label_time_s = time_s(1) + 0.985 * (time_s(end) - time_s(1));
text(axes_U, label_time_s, U_boundary_pu, '{\itU}_b  ', ...
    'Color', red_color, 'FontName', 'Times New Roman', ...
    'FontSize', 11, 'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'bottom');
text(axes_I, label_time_s, I_threshold_pu, '{\itI}^{lim}  ', ...
    'Color', red_color, 'FontName', 'Times New Roman', ...
    'FontSize', 11, 'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'bottom');

%% 标出连续恢复确认区间
release_intervals_s = zeros(0, 2);
on_to_off_rows = find(transition_direction == "ON->OFF");
for row_index = on_to_off_rows(:).'
    exit_index = transition_index(row_index);
    exit_time_s = time_s(exit_index);
    start_time_s = NaN;

    if any(isfinite(release_elapsed_s))
        search_index = max(1, exit_index - 1);
        while search_index > 1 && ...
                isfinite(release_elapsed_s(search_index)) && ...
                release_elapsed_s(search_index) > 0
            search_index = search_index - 1;
        end
        start_time_s = time_s(min(search_index + 1, exit_index));
    elseif isfinite(release_confirm_time_s)
        start_time_s = max(time_s(1), ...
            exit_time_s - release_confirm_time_s);
    end

    if isfinite(start_time_s) && start_time_s < exit_time_s
        release_intervals_s(end + 1, :) = ...
            [start_time_s, exit_time_s]; %#ok<AGROW>
    end
end

%% 标出 Case 边界和状态跃迁
if show_case_boundaries
    for boundary_index = 1:numel(case_boundary_times_s)
        boundary_time_s = case_boundary_times_s(boundary_index);
        for axes_index = 1:numel(axes_list)
            y_limits = ylim(axes_list(axes_index));
            plot(axes_list(axes_index), ...
                [boundary_time_s, boundary_time_s], y_limits, ':', ...
                'Color', gray_color, 'LineWidth', 1.0, ...
                'HandleVisibility', 'off');
        end
    end
end

for row_index = 1:height(transition_table)
    transition_time_s = transition_table.Time_s(row_index);
    if transition_table.Direction(row_index) == "OFF->ON"
        transition_color = red_color;
        transition_label = sprintf('投入%.4f s', transition_time_s);
    else
        transition_color = green_color;
        transition_label = sprintf('退出%.4f s', transition_time_s);
    end

    for axes_index = 1:numel(axes_list)
        y_limits = ylim(axes_list(axes_index));
        plot(axes_list(axes_index), ...
            [transition_time_s, transition_time_s], y_limits, '--', ...
            'Color', transition_color, 'LineWidth', 1.15, ...
            'HandleVisibility', 'off');
    end

    if show_transition_labels
        y_limits = ylim(axes_U);
        text(axes_U, transition_time_s, ...
            y_limits(2) - 0.03 * diff(y_limits), transition_label, ...
            'Color', transition_color, 'FontName', font_name, ...
            'FontSize', 9, 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'top');
    end
end

if show_case_boundaries && show_case_names
    case_edges_s = [time_s(1), case_boundary_times_s, time_s(end)];
    number_of_case_regions = numel(case_edges_s) - 1;
    number_of_case_labels = min(number_of_case_regions, numel(case_names));
    y_limits = ylim(axes_U);
    for case_index = 1:number_of_case_labels
        case_center_s = mean(case_edges_s(case_index:case_index + 1));
        text(axes_U, case_center_s, ...
            y_limits(2) - 0.13 * diff(y_limits), case_names{case_index}, ...
            'Color', gray_color, 'FontName', 'Times New Roman', ...
            'FontSize', 9.5, 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'top');
    end
end

%% 可选导出 PNG
% if export_figure
%     exportgraphics(figure_handle, output_file, ...
%         'Resolution', export_resolution_dpi, ...
%         'BackgroundColor', 'white');
%     fprintf('PNG：%s\n', output_file);
% end
end

function value = localReadLoggedScalar(logsout, signal_names, signal_name)
% 读取 logsout 中的常数参数记录。
if ~ismember(signal_name, signal_names)
    error(['logsout 中没有 %s。请重新运行模型，或在函数顶部设置' ...
        '对应的覆盖值。'], signal_name);
end
signal_ts = logsout.getElement(signal_name).Values;
if ~isa(signal_ts, 'timeseries')
    error('%s 必须记录为 timeseries。', signal_name);
end
values = double(squeeze(signal_ts.Data));
values = values(isfinite(values));
if isempty(values)
    error('%s 没有有限数值。', signal_name);
end
value = values(1);
end

function [time_s, data] = localTimeseriesData(signal_ts, signal_name)
% 将标量 timeseries 整理为严格递增的列向量。
time_s = double(signal_ts.Time(:));
data = double(squeeze(signal_ts.Data));
data = data(:);
if numel(data) ~= numel(time_s)
    error('%s 的时间长度与数据长度不一致。', signal_name);
end
[time_s, unique_index] = unique(time_s, 'last');
data = data(unique_index);
if isempty(time_s)
    error('%s 没有可用数据。', signal_name);
end
end

function values = localInterpolate(source_time, source_data, query_time, method)
% 将一个标量记录信号对齐到 Slim 的时间轴。
if isscalar(source_time)
    values = repmat(source_data(1), size(query_time));
else
    values = interp1(source_time, source_data, query_time, method, 'extrap');
end
values = values(:);
end
