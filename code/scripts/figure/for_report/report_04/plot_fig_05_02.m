function results = plot_fig_05_02()
%PLOT_FIG_05_02 生成图5-2验证数据与图形。
%
% 通过改变外部电网电压扫描完整Simulink模型。横坐标始终采用并网点
% 实际测得的残余电压|U_sim^F|，而不是外部电压指令值。扫描过程中
% 临时添加To Workspace模块，函数结束时删除，模型不会被本函数保存。
%
% 端口等值模型使用与完整模型相同的|U_sim^F|作为输入：
%   Iq_req = Iq_ref_manual + sat(K_q_LVRT*(V_LVRT_max-|U|), 0, Delta_Iq_max)
%   Id_eq  = Id_ref_manual，并在Iq之后执行有功电流限幅
%   |I_eq| = hypot(Id_eq,Iq_eq) <= I_limit。
%
% 当前项目中未找到原始报告或表5-3文件，因此本脚本执行当前
% Invert_Parameters.m，并将参数快照与结果一起保存。当前参数计算得到的
% 理论限流起始点约为0.304 p.u.。

%% 路径与参数加载
figure_dir = fileparts(mfilename('fullpath'));
project_root = find_project_root_local(figure_dir);
code_dir = fullfile(project_root, 'code');

% 固定Simulink缓存和代码生成文件的输出位置。
equipment_dir = fullfile(code_dir, 'functions', 'equipment');
if isempty(which('configure_simulink_file_generation'))
    addpath(equipment_dir);
end
file_generation_cleanup = configure_simulink_file_generation(project_root); %#ok<NASGU>

param_file = fullfile(code_dir, 'scripts', 'equipment', ...
    'Invert_Parameters.m');
model_file = fullfile(project_root, 'simulink', 'models', ...
    'Grid_Following_Inverters_LVRT.slx');
output_dir = fullfile(project_root, 'figs', 'for_report');

assert(isfile(param_file), 'Parameter script not found: %s', param_file);
assert(isfile(model_file), 'Simulink model not found: %s', model_file);
if ~isfolder(output_dir)
    mkdir(output_dir);
end

% Invert_Parameters.m是工作区初始化脚本。由于Simulink模块参数从基础
% 工作区解析，因此需要在基础工作区中执行。
evalin('base', sprintf('run(''%s'');', ...
    strrep(param_file, '''', '''''')));

mdl = 'Grid_Following_Inverters_LVRT';
was_loaded = bdIsLoaded(mdl);
if ~was_loaded
    load_system(model_file);
end

% 保存模型和外部电源的原始设置，扫描结束后恢复。
stop_time_original = get_param(mdl, 'StopTime');
stop_time_original = get_param(mdl, 'StopTime');
solver_original = get_param(mdl, 'Solver');
source_block = [mdl '/Three-Phase Source'];
source_voltage_original = get_param(source_block, 'Voltage');
Vg_original = evalin('base', 'Vg');

temporary_blocks = add_temporary_logs(mdl);
cleanup_obj = onCleanup(@()restore_scan_state(mdl, temporary_blocks, ...
    stop_time_original, solver_original, source_block, ...
    source_voltage_original, Vg_original, was_loaded)); %#ok<NASGU>

%% 读取并检查参数
V_base = evalin('base', 'V_base');
S_base = evalin('base', 'S_base');
V_base_phase = evalin('base', 'V_base_phase');
I_base = evalin('base', 'I_base');
I_N = evalin('base', 'I_N');
I_limit = evalin('base', 'I_limit');
V_LVRT_max = evalin('base', 'V_LVRT_max');
V_LVRT_min = evalin('base', 'V_LVRT_min');
K_q_LVRT = evalin('base', 'K_q_LVRT');
Delta_Iq_LVRT_max = evalin('base', 'Delta_Iq_LVRT_max');
Manual_Current_Ref = evalin('base', 'Manual_Current_Ref');
Id_ref_manual = evalin('base', 'Id_ref_manual');
Iq_ref_manual = evalin('base', 'Iq_ref_manual');

if Manual_Current_Ref ~= 1
    error(['Report 5.2 validation requires Manual_Current_Ref = 1 so that ', ...
        'the full model and port model use the same manual current basis.']);
end
if abs(Id_ref_manual) >= I_limit
    error('Id_ref_manual must be smaller than I_limit for the onset formula.');
end

% 本验证采用以下三相基准换算：
%   I_base = S_base/(sqrt(3)*V_base) [A，有效值线电流]
%   V_base_phase = sqrt(2/3)*V_base [V，相电压峰值]
% Simulink中的i2_d/i2_q信号单位为A，除以I_base后转换为p.u.。
assert(abs(I_base - S_base/(sqrt(3)*V_base)) <= 1e-9*max(1,I_base), ...
    'I_base is inconsistent with the three-phase base.');
assert(abs(V_base_phase - sqrt(2/3)*V_base) <= 1e-9*max(1,V_base_phase), ...
    'V_base_phase is inconsistent with V_base.');

% 不将0.304写死，严格按照报告给出的公式由参数自动计算限流起始点。
U_lim = V_LVRT_max - sqrt(I_limit^2 - Id_ref_manual^2)/K_q_LVRT;

fprintf('\nReport 5.2 parameter alignment snapshot:\n');
fprintf('  V_base = %.9g V, S_base = %.9g VA\n', V_base, S_base);
fprintf('  I_base = %.9g A, V_base_phase = %.9g V peak\n', ...
    I_base, V_base_phase);
fprintf('  Manual_Current_Ref = %d, Id_ref_manual = %.9g, Iq_ref_manual = %.9g p.u.\n', ...
    Manual_Current_Ref, Id_ref_manual, Iq_ref_manual);
fprintf('  V_LVRT_max = %.9g, V_LVRT_min = %.9g, K_q_LVRT = %.9g, I_limit = %.9g p.u.\n', ...
    V_LVRT_max, V_LVRT_min, K_q_LVRT, I_limit);
fprintf('  Theoretical current-limit onset |U^F|_lim = %.9g p.u.\n', U_lim);

%% 扫描部分：建立非等距扫描点并运行完整模型
target_voltage = [ ...
    0.90:0.03:1.05, ...                  % LVRT未启动区
    0.35:0.05:0.90, ...                  % LVRT线性未限流区
    0.24:0.01:0.36, ...                  % 限流拐点附近加密区
    0.05:0.03:0.20, ...                  % LVRT饱和限流区
    1.00, 0.90, 0.80, 0.60, 0.40, U_lim, ...
    0.30, 0.25, 0.20, 0.10];
target_voltage = sort(unique(round(target_voltage, 8)), 'ascend');
% 现有PQ阶跃发生在0.15 s和0.20 s。0.4 s仿真的最后四分之一段位于
% 阶跃之后，并作为控制响应稳定区间；该区间写入结果结构体。
scan_stop_time = 0.40;
settle_start_time = 0.30;
set_param(mdl, 'StopTime', num2str(scan_stop_time, '%.12g'));
set_param(mdl, 'SimulationCommand', 'update');

n = numel(target_voltage);
u_sim = nan(n, 1);
id_sim = nan(n, 1);
iq_sim = nan(n, 1);
i_sim = nan(n, 1);

fprintf('Scanning %d nonuniform residual-voltage commands...\n', n);
for k = 1:n
    % 外部电源模块使用工作区变量Vg。实际并网点电压在下方测量，且只用
    % 实测电压进行绘图和误差统计。
    assignin('base', 'Vg', target_voltage(k)*V_base);
    sim_out = sim(mdl, 'ReturnWorkspaceOutputs', 'on');

    u_ts = sim_out.v_PCC_mag;
    id_ts = sim_out.Scan_i2_d;
    iq_ts = sim_out.Scan_i2_q;

    u_sim(k) = mean_steady(u_ts, settle_start_time, scan_stop_time) / ...
        V_base_phase;
    id_sim(k) = mean_steady(id_ts, settle_start_time, scan_stop_time) / I_base;
    iq_sim(k) = mean_steady(iq_ts, settle_start_time, scan_stop_time) / I_base;
    % i2 abc信号为瞬时三相电流，时间平均值为零；使用同步旋转坐标系下
    % 的d/q分量计算电流幅值。
    i_sim(k) = hypot(id_sim(k), iq_sim(k));

    fprintf('  %2d/%2d: command %.6f -> |U_sim^F| %.6f, ', ...
        k, n, target_voltage(k), u_sim(k));
    fprintf('Id %.6f, Iq %.6f, |I| %.6f p.u.\n', ...
        id_sim(k), iq_sim(k), i_sim(k));
end

%% 端口等值模型计算：使用实测并网点残余电压
[id_eq, iq_eq, i_eq] = port_equivalent_current(u_sim, ...
    Id_ref_manual, Iq_ref_manual, I_limit, V_LVRT_max, ...
    V_LVRT_min, K_q_LVRT, I_N, Delta_Iq_LVRT_max);

current_error = i_sim - i_eq;
absolute_current_error = abs(current_error);
linear_mask = u_sim >= U_lim & u_sim <= V_LVRT_max;
limited_mask = u_sim < U_lim;
all_mask = isfinite(u_sim) & isfinite(i_sim) & isfinite(i_eq);

error_table = table( ...
    ["LVRT linear, not limited"; "current-limited"; "all scanned conditions"], ...
    [max_or_nan(absolute_current_error(linear_mask)); ...
     max_or_nan(absolute_current_error(limited_mask)); ...
     max_or_nan(absolute_current_error(all_mask))], ...
    [max_or_nan(100*absolute_current_error(linear_mask)./max(i_eq(linear_mask), eps)); ...
     max_or_nan(100*absolute_current_error(limited_mask)./max(i_eq(limited_mask), eps)); ...
     max_or_nan(100*absolute_current_error(all_mask)./max(i_eq(all_mask), eps))], ...
    [nnz(linear_mask); nnz(limited_mask); nnz(all_mask)], ...
    'VariableNames', {'Region','MaxAbsCurrentMagnitudeError_pu', ...
    'MaxRelativeCurrentMagnitudeError_pct','NumberOfPoints'});

data_table = table(target_voltage(:), u_sim, id_sim, iq_sim, i_sim, ...
    id_eq, iq_eq, i_eq, current_error, absolute_current_error, ...
    'VariableNames', {'TargetSourceVoltage_pu','USimF_pu','IdSimF_pu', ...
    'IqSimF_pu','ISimF_pu','IdEqF_pu','IqEqF_pu','IEqF_pu', ...
    'CurrentMagnitudeSignedError_pu','CurrentMagnitudeAbsError_pu'});

parameter_snapshot = struct( ...
    'V_base_V_line_rms', V_base, ...
    'S_base_VA_three_phase', S_base, ...
    'I_base_A_line_rms', I_base, ...
    'V_base_phase_V_peak', V_base_phase, ...
    'Manual_Current_Ref', Manual_Current_Ref, ...
    'Id_ref_manual_pu', Id_ref_manual, ...
    'Iq_ref_manual_pu', Iq_ref_manual, ...
    'I_N_pu', I_N, ...
    'I_limit_pu', I_limit, ...
    'V_LVRT_max_pu', V_LVRT_max, ...
    'V_LVRT_min_pu', V_LVRT_min, ...
    'K_q_LVRT', K_q_LVRT, ...
    'Delta_Iq_LVRT_max_pu', Delta_Iq_LVRT_max, ...
    'U_lim_pu', U_lim, ...
    'settle_start_time_s', settle_start_time, ...
    'scan_stop_time_s', scan_stop_time);

%% 画图部分：绘制图5-2并保存FIG/PNG
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', ...
    'Position', [1 1 7.6 8.2], 'InvertHardcopy', 'off', ...
    'CreateFcn', 'set(gcbf,''Visible'',''on'');');
tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

[u_line, idx] = sort(u_sim, 'ascend');
iq_line = iq_eq(idx);
id_line = id_eq(idx);
i_line = i_eq(idx);

ax1 = nexttile(tl);
plot(ax1, u_line, iq_line, '-', 'Color', [78 121 167]/255, ...
    'LineWidth', 1.5, 'DisplayName', '端口等值模型');
hold(ax1, 'on');
scatter(ax1, u_sim, iq_sim, 30, [0.8500 0.3250 0.0980], 'filled', ...
    'DisplayName', '完整模型');
add_voltage_guides(ax1, U_lim, V_LVRT_max, V_LVRT_min);
hold(ax1, 'off');
ylabel(ax1, '\fontname{SimSun}故障后无功电流 \fontname{Times New Roman}{\itI_q}^F (p.u.)', ...
    'Interpreter', 'tex');
xlabel(ax1, voltage_axis_label(), 'Interpreter', 'tex');

ax2 = nexttile(tl);
plot(ax2, u_line, id_line, '-', 'Color', [78 121 167]/255, ...
    'LineWidth', 1.5, 'DisplayName', '端口等值模型');
hold(ax2, 'on');
scatter(ax2, u_sim, id_sim, 30, [0.8500 0.3250 0.0980], 'filled', ...
    'DisplayName', '完整模型');
add_voltage_guides(ax2, U_lim, V_LVRT_max, V_LVRT_min);
hold(ax2, 'off');
ylabel(ax2, '\fontname{SimSun}故障后有功电流\fontname{Times New Roman}{\itI_d}^F (p.u.)', ...
    'Interpreter', 'tex');
xlabel(ax2, voltage_axis_label(), 'Interpreter', 'tex');

ax3 = nexttile(tl);
hIEq = plot(ax3, u_line, i_line, '-', 'Color', [78 121 167]/255, ...
    'LineWidth', 1.5, 'DisplayName', '端口等值模型');
hold(ax3, 'on');
hISim = scatter(ax3, u_sim, i_sim, 30, [0.8500 0.3250 0.0980], 'filled', ...
    'DisplayName', '完整模型');
h09 = xline(ax3, V_LVRT_max, '--', 'Color', [34 34 34]/255, ...
    'LineWidth', 0.9, ...
    'DisplayName', '低电压穿越启动阈值 0.90');
hlim = xline(ax3, U_lim, '-.', 'Color', [242 182 109]/255, ...
    'LineWidth', 1.0, ...
    'DisplayName', '理论限流起始点');
h02 = xline(ax3, V_LVRT_min, ':', 'Color', [34 34 34]/255, ...
    'LineWidth', 0.9, ...
    'DisplayName', '无功电流饱和阈值 0.20');
hold(ax3, 'off');
xlabel(ax3, voltage_axis_label(), 'Interpreter', 'tex');
ylabel(ax3, '\fontname{SimSun}故障后电流幅值\fontname{Times New Roman}|{\itI}^F| (p.u.)', ...
    'Interpreter', 'tex');

axes_list = [ax1 ax2 ax3];
for ax = axes_list
    style_axes(ax);
end
legend(ax3, [hISim hIEq h09 hlim h02], ...
    {'完整模型', '端口等值模型', '低电压穿越启动阈值 0.90', ...
    '理论限流起始点', '无功电流饱和阈值 0.20'}, ...
    'Location', 'southoutside', 'NumColumns', 3, ...
    'Interpreter', 'none', 'FontName', 'SimSun');
fig_base = fullfile(output_dir, 'Figure_5_2_LVRT_validation');
% 以可见状态保存FIG，确保在MATLAB中双击FIG文件时能够正常弹窗显示。
set(fig, 'Visible', 'on');
savefig(fig, [fig_base '.fig']);
exportgraphics(fig, [fig_base '.png'], 'Resolution', 400, ...
    'BackgroundColor', 'white');
close(fig);

% 仅保存MAT格式数值结果，不再输出CSV文件。
mat_file = fullfile(output_dir, 'Figure_5_2_LVRT_validation_results.mat');
save(mat_file, ...
    'data_table', 'error_table', 'parameter_snapshot');

fprintf('\nFig. 5-2 validation summary:\n');
fprintf('  Theory current-limit onset: |U^F|_lim = %.9f p.u.\n', U_lim);
fprintf('  LVRT linear/unlimited max |error| = %.6g p.u. (%.6g%%, %d points)\n', ...
    error_table.MaxAbsCurrentMagnitudeError_pu(1), ...
    error_table.MaxRelativeCurrentMagnitudeError_pct(1), ...
    error_table.NumberOfPoints(1));
fprintf('  Current-limited max |error| = %.6g p.u. (%.6g%%, %d points)\n', ...
    error_table.MaxAbsCurrentMagnitudeError_pu(2), ...
    error_table.MaxRelativeCurrentMagnitudeError_pct(2), ...
    error_table.NumberOfPoints(2));
fprintf('  All-condition max |error| = %.6g p.u. (%.6g%%, %d points)\n', ...
    error_table.MaxAbsCurrentMagnitudeError_pu(3), ...
    error_table.MaxRelativeCurrentMagnitudeError_pct(3), ...
    error_table.NumberOfPoints(3));
fprintf('  Figure: %s.fig and %s.png\n', fig_base, fig_base);
fprintf('  Data MAT: %s\n', mat_file);

results = struct('parameters', parameter_snapshot, 'data', data_table, ...
    'errors', error_table, 'figure_file', [fig_base '.fig'], ...
    'png_file', [fig_base '.png'], 'mat_file', mat_file);

end

function block_paths = add_temporary_logs(mdl)
% 向现有测量信号添加仅用于运行时的临时日志模块。
sub = [mdl '/GFL_1/测量部分'];
names = {'i2_d','i2_q'};
block_paths = cell(size(names));
for k = 1:numel(names)
    name = names{k};
    block = [sub '/Scan_Log_' name];
    block_paths{k} = block;
    if getSimulinkBlockHandle(block) == -1
        add_block('simulink/Sinks/To Workspace', block, ...
            'VariableName', ['Scan_' name], ...
            'SaveFormat', 'Timeseries', ...
            'Position', [1000 450+80*(k-1) 1160 480+80*(k-1)]);
    end
    line_handles = get_param(block, 'LineHandles');
    if isempty(line_handles.Inport) || all(line_handles.Inport == -1)
        source_handles = get_param([sub '/' name], 'PortHandles');
        add_line(sub, source_handles.Outport(1), ...
            get_param(block, 'PortHandles').Inport(1), ...
            'autorouting', 'on');
    end
end
end

function restore_scan_state(mdl, temporary_blocks, stop_time_original, ...
        solver_original, source_block, source_voltage_original, ...
        Vg_original, was_loaded)
for ii = 1:numel(temporary_blocks)
    if getSimulinkBlockHandle(temporary_blocks{ii}) ~= -1
        delete_block(temporary_blocks{ii});
    end
end
if bdIsLoaded(mdl)
    set_param(mdl, 'StopTime', stop_time_original, 'Solver', solver_original);
    set_param(source_block, 'Voltage', source_voltage_original);
    set_param(mdl, 'SimulationCommand', 'update');
end
assignin('base', 'Vg', Vg_original);
if ~was_loaded && bdIsLoaded(mdl)
    close_system(mdl, 0);
end
end

function value = mean_steady(ts, t_start, t_stop)
[time, data] = timeseries_data(ts);
mask = time >= t_start & time <= t_stop;
if nnz(mask) < 5
    mask = false(size(time));
    mask(max(1, numel(time)-max(5, round(0.1*numel(time)))):end) = true;
end
data = double(data(mask, :));
value = mean(data, 'all', 'omitnan');
end

function [time, data] = timeseries_data(ts)
if isa(ts, 'timeseries')
    time = double(ts.Time(:));
    data = ts.Data;
else
    error('Expected a timeseries output, received %s.', class(ts));
end
if size(data, 1) ~= numel(time) && size(data, 2) == numel(time)
    data = data.';
end
end

function [id_eq, iq_eq, i_eq] = port_equivalent_current(u_pu, ...
        id_ref, iq_ref, i_limit, v_max, v_min, kq, i_n, delta_iq_max)
% 先执行LVRT电压支撑，再执行无功优先限流。
delta_iq_max_from_parameters = kq*(v_max-v_min)*i_n;
if abs(delta_iq_max-delta_iq_max_from_parameters) > ...
        1e-10*max(1, abs(delta_iq_max))
    error('Delta_Iq_LVRT_max is inconsistent with the LVRT parameters.');
end
delta_iq = kq .* max(v_max - u_pu, 0);
delta_iq = min(delta_iq, delta_iq_max);
iq_eq = iq_ref + delta_iq;
id_eq = id_ref*ones(size(u_pu));

% 优先为无功电流保留电流容量。
id_available = sqrt(max(i_limit^2 - iq_eq.^2, 0));
id_eq(abs(id_eq) > id_available) = ...
    sign(id_eq(abs(id_eq) > id_available)) .* ...
    id_available(abs(id_eq) > id_available);
i_eq = hypot(id_eq, iq_eq);

% 保留额定电流参数并尽早检查参数一致性。本模型中I_N通常为1 p.u.。
if ~(isscalar(i_n) && isfinite(i_n) && i_n > 0)
    error('I_N must be a positive scalar.');
end
end

function add_voltage_guides(ax, u_lim, v_max, v_min)
xline(ax, v_max, '--', 'Color', [34 34 34]/255, 'LineWidth', 0.9, ...
    'DisplayName', '低电压穿越启动阈值 0.90');
xline(ax, u_lim, '-.', 'Color', [242 182 109]/255, 'LineWidth', 1.0, ...
    'DisplayName', '理论限流起始点');
xline(ax, v_min, ':', 'Color', [34 34 34]/255, 'LineWidth', 0.9, ...
    'DisplayName', '无功电流饱和阈值 0.20');
end

function style_axes(ax)
set(ax, 'FontName', 'Times New Roman', 'FontSize', 10, ...
    'LineWidth', 0.8, 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on', ...
    'GridAlpha', 0.18);
end

function label = voltage_axis_label()
label = '\fontname{SimSun}并网点残余电压 \fontname{Times New Roman}|{\itU}_{sim}^F| (p.u.)';
end

function value = max_or_nan(x)
if isempty(x)
    value = NaN;
else
    value = max(x, [], 'omitnan');
end
end

function project_root = find_project_root_local(start_dir)
% 从当前脚本目录向上查找同时包含code和simulink/models的项目根目录。
candidate = char(java.io.File(start_dir).getCanonicalPath());
while true
    if isfolder(fullfile(candidate, 'code')) && ...
        isfolder(fullfile(candidate, 'simulink', 'models'))
        project_root = candidate;
        return;
    end
    parent = fileparts(candidate);
    if strcmp(parent, candidate)
        break;
    end
    candidate = parent;
end
error('无法从目录%s找到项目根目录。', start_dir);
end
