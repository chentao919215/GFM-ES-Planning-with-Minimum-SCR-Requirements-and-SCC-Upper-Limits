%% GFL-WG低电压穿越验证。
% 本文件包含选项、主验证过程及局部辅助函数；主过程结束时自动恢复临时设置。

%% 1. 设置验证选项
Validation_Options = struct();
% 指定电压子集时可设置：Validation_Options.Source_Voltages_pu = [0.9 0.6 0.2];

%% 2. 执行验证并保存结果
Validation_Result = run_validation(Validation_Options);

% 主验证过程与局部辅助函数
function results = run_validation(Options)
%% 扫描GFL低电压穿越工况并保存电流与端口等值对照。
if nargin < 1
    Options = struct();
end
% 绘图请另行调用 plot_gfl_lvrt_validation；本入口不生成图件。
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
% 参数由initialize_gfl_model.m加载，快照与结果一起保存。
% 当前参数计算得到的理论限流起始点约为0.304 p.u.。

%% 1. 路径与参数加载
Script_Dir = fileparts(mfilename('fullpath'));
Project_Root = find_project_root(Script_Dir);
Code_Dir = fullfile(Project_Root, 'code');

% 固定Simulink缓存和代码生成文件的输出位置。
Equipment_Dir = fullfile(Code_Dir, 'functions');
if isempty(which('configure_simulink_file_generation'))
    addpath(genpath(Equipment_Dir));
end
File_Generation_Cleanup = configure_simulink_file_generation(Project_Root); %#ok<NASGU>

Param_File = fullfile(Code_Dir, 'scripts', 'equipment', ...
    'initialization', 'initialize_gfl_model.m');
Model_File = fullfile(Project_Root, 'simulink', 'models', ...
    'Grid_Following_Inverters.slx');
Output_Dir = fullfile(Project_Root, 'results', 'equipment', 'GFL');
if isfield(Options, 'Result_Directory')
    Output_Dir = Options.Result_Directory;
end

assert(isfile(Param_File), 'Parameter script not found: %s', Param_File);
assert(isfile(Model_File), 'Simulink model not found: %s', Model_File);
if ~isfolder(Output_Dir)
    mkdir(Output_Dir);
end

% initialize_gfl_model.m是工作区初始化脚本。由于Simulink模块参数从基础
% 工作区解析，因此需要在基础工作区中执行。
evalin('base', sprintf('run(''%s'');', ...
    strrep(Param_File, '''', '''''')));

mdl = 'Grid_Following_Inverters';
Was_Loaded = bdIsLoaded(mdl);
if ~Was_Loaded
    load_system(Model_File);
end

% 保存模型和外部电源的原始设置，扫描结束后恢复。
Stop_Time_Original = get_param(mdl, 'StopTime');
Dirty_Original = get_param(mdl, 'Dirty');
Solver_Original = get_param(mdl, 'Solver');
Source_Block = [mdl '/Three-Phase Source'];
Source_Voltage_Original = get_param(Source_Block, 'Voltage');
Source_Impedance_Original = get_param(Source_Block, 'NonIdealSource');
Vg_original = evalin('base', 'Vg');

Temporary_Blocks = add_temporary_logs(mdl);
Cleanup_Obj = onCleanup(@()restore_scan_state(mdl, Temporary_Blocks, ...
    Stop_Time_Original, Solver_Original, Source_Block, ...
    Source_Voltage_Original, Source_Impedance_Original, Vg_original, Was_Loaded, Dirty_Original));
% 端口特性校验使用刚性电压源；SCR扫描则在同一模型中启用内部电网阻抗。
set_param(Source_Block, 'NonIdealSource', 'off');

%% 2. 读取并检查参数
V_base = evalin('base', 'V_base');
S_base = evalin('base', 'S_base');
V_base_phase = evalin('base', 'V_base_phase');
I_base = evalin('base', 'I_base');
I_base_rms = evalin('base', 'I_base_rms');
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
    error(['GFL LVRT validation requires Manual_Current_Ref = 1 so that ', ...
        'the full model and port model use the same manual current basis.']);
end
if abs(Id_ref_manual) >= I_limit
    error('Id_ref_manual must be smaller than I_limit for the onset formula.');
end

% 本验证采用以下三相基准换算：
%   I_base_rms = S_base/(sqrt(3)*V_base) [A，有效值线电流]
%   I_base = sqrt(2)*I_base_rms [A，dq峰值电流]
%   V_base_phase = sqrt(2/3)*V_base [V，相电压峰值]
% Simulink中的i2_d/i2_q信号单位为A，除以I_base后转换为p.u.。
assert(abs(I_base - sqrt(2)*S_base/(sqrt(3)*V_base)) <= 1e-9*max(1, I_base), ...
    'I_base is inconsistent with the three-phase base.');
assert(abs(V_base_phase - sqrt(2/3)*V_base) <= 1e-9*max(1, V_base_phase), ...
    'V_base_phase is inconsistent with V_base.');

% 不将0.304写死，严格按照报告给出的公式由参数自动计算限流起始点。
U_lim = V_LVRT_max - sqrt(I_limit^2 - Id_ref_manual^2)/K_q_LVRT;

fprintf('\nGFL LVRT parameter alignment snapshot:\n');
fprintf('  V_base = %.9g V, S_base = %.9g VA\n', V_base, S_base);
fprintf('  I_base = %.9g A, V_base_phase = %.9g V peak\n', ...
    I_base, V_base_phase);
fprintf('  Manual_Current_Ref = %d, Id_ref_manual = %.9g, Iq_ref_manual = %.9g p.u.\n', ...
    Manual_Current_Ref, Id_ref_manual, Iq_ref_manual);
fprintf('  V_LVRT_max = %.9g, V_LVRT_min = %.9g, K_q_LVRT = %.9g, I_limit = %.9g p.u.\n', ...
    V_LVRT_max, V_LVRT_min, K_q_LVRT, I_limit);
fprintf('  Theoretical current-limit onset |U^F|_lim = %.9g p.u.\n', U_lim);

%% 3. 扫描部分：建立非等距扫描点并运行完整模型
Target_Voltage = [ ...
    0.90:0.03:1.05, ...                  % LVRT未启动区
    0.35:0.05:0.90, ...                  % LVRT线性未限流区
    0.24:0.01:0.36, ...                  % 限流拐点附近加密区
    0.05:0.03:0.20, ...                  % LVRT饱和限流区
    1.00, 0.90, 0.80, 0.60, 0.40, U_lim, ...
    0.30, 0.25, 0.20, 0.10];
if isfield(Options, 'Source_Voltages_pu')
    Target_Voltage = Options.Source_Voltages_pu;
end
Target_Voltage = sort(unique(round(Target_Voltage, 8)), 'ascend');
% 现有PQ阶跃发生在0.15 s和0.20 s。0.4 s仿真的最后四分之一段位于
% 阶跃之后，并作为控制响应稳定区间；该区间写入结果结构体。
Scan_Stop_Time = 0.40;
Settle_Start_Time = 0.30;
set_param(mdl, 'StopTime', num2str(Scan_Stop_Time, '%.12g'));
set_param(mdl, 'SimulationCommand', 'update');

n = numel(Target_Voltage);
u_sim = nan(n, 1);
ID_Sim = nan(n, 1);
Iq_Sim = nan(n, 1);
I_Sim = nan(n, 1);
I_RMS_Sim = nan(n, 1);

fprintf('Scanning %d nonuniform residual-voltage commands...\n', n);
for k = 1:n
    % 外部电源模块使用工作区变量Vg。实际并网点电压在下方测量，且只用
    % 实测电压进行绘图和误差统计。
    assignin('base', 'Vg', Target_Voltage(k)*V_base);
    Sim_Out = sim(mdl, 'ReturnWorkspaceOutputs', 'on');

    u_ts = Sim_Out.v_PCC_mag;
    ID_Ts = Sim_Out.Scan_i2_d;
    Iq_Ts = Sim_Out.Scan_i2_q;

    u_sim(k) = mean_steady(u_ts, Settle_Start_Time, Scan_Stop_Time) / ...
        V_base_phase;
    ID_Sim(k) = mean_steady(ID_Ts, Settle_Start_Time, Scan_Stop_Time) / I_base;
    Iq_Sim(k) = mean_steady(Iq_Ts, Settle_Start_Time, Scan_Stop_Time) / I_base;
    % i2 abc信号为瞬时三相电流，时间平均值为零；使用同步旋转坐标系下
    % 的d/q分量计算电流幅值。
    I_Sim(k) = hypot(ID_Sim(k), Iq_Sim(k));
    [RMS_Time, abc] = timeseries_data(Sim_Out.Scan_i2);
    RMS_Mask = RMS_Time >= Settle_Start_Time & RMS_Time <= Scan_Stop_Time;
    RMS_Time = RMS_Time(RMS_Mask);
    I_RMS_Sim(k) = sqrt(trapz(RMS_Time, ...
        mean(abc(RMS_Mask, :).^2, 2))/(RMS_Time(end)-RMS_Time(1)))/I_base_rms;

    fprintf('  %2d/%2d: command %.6f -> |U_sim^F| %.6f, ', ...
        k, n, Target_Voltage(k), u_sim(k));
    fprintf('Id %.6f, Iq %.6f, |I| %.6f p.u.\n', ...
        ID_Sim(k), Iq_Sim(k), I_Sim(k));
end

%% 4. 端口等值模型计算：使用实测并网点残余电压
[ID_Eq, Iq_Eq, I_Eq] = port_equivalent_current(u_sim, ...
    Id_ref_manual, Iq_ref_manual, I_limit, V_LVRT_max, ...
    V_LVRT_min, K_q_LVRT, I_N, Delta_Iq_LVRT_max);

Current_Error = I_Sim - I_Eq;
Absolute_Current_Error = abs(Current_Error);
Linear_Mask = u_sim >= U_lim & u_sim <= V_LVRT_max;
Limited_Mask = u_sim < U_lim;
All_Mask = isfinite(u_sim) & isfinite(I_Sim) & isfinite(I_Eq);

error_table = table( ...
    ["LVRT linear, not limited"; "current-limited"; "all scanned conditions"], ...
    [max_or_nan(Absolute_Current_Error(Linear_Mask)); ...
    max_or_nan(Absolute_Current_Error(Limited_Mask)); ...
    max_or_nan(Absolute_Current_Error(All_Mask))], ...
    [max_or_nan(100*Absolute_Current_Error(Linear_Mask)./max(I_Eq(Linear_Mask), eps)); ...
    max_or_nan(100*Absolute_Current_Error(Limited_Mask)./max(I_Eq(Limited_Mask), eps)); ...
    max_or_nan(100*Absolute_Current_Error(All_Mask)./max(I_Eq(All_Mask), eps))], ...
    [nnz(Linear_Mask); nnz(Limited_Mask); nnz(All_Mask)], ...
    'VariableNames', {'Region', 'MaxAbsCurrentMagnitudeError_pu', ...
    'MaxRelativeCurrentMagnitudeError_pct', 'NumberOfPoints'});

data_table = table(Target_Voltage(:), u_sim, ID_Sim, Iq_Sim, I_Sim, ...
    ID_Eq, Iq_Eq, I_Eq, Current_Error, Absolute_Current_Error, ...
    'VariableNames', {'TargetSourceVoltage_pu', 'USimF_pu', 'IdSimF_pu', ...
    'IqSimF_pu', 'ISimF_pu', 'IdEqF_pu', 'IqEqF_pu', 'IEqF_pu', ...
    'CurrentMagnitudeSignedError_pu', 'CurrentMagnitudeAbsError_pu'});
data_table.IAbcRMS_pu = I_RMS_Sim;
data_table.CurrentBasisError_pu = abs(I_RMS_Sim-I_Sim);
assert(all(data_table.CurrentBasisError_pu < 0.01), ...
    'GFLValidation:CurrentBasisMismatch', ...
    '三相有效值与dq峰值的电流标幺值不一致，请核对电流基准。');

parameter_snapshot = struct( ...
    'V_base_V_line_rms', V_base, ...
    'S_base_VA_three_phase', S_base, ...
    'I_base_A_line_rms', I_base_rms, ...
    'I_base_A_dq_peak', I_base, ...
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
    'settle_start_time_s', Settle_Start_Time, ...
    'scan_stop_time_s', Scan_Stop_Time);

%% 5. 保存数值结果；仿真设置由清理对象恢复
MAT_File = fullfile(Output_Dir, 'GFL_LVRT_Validation_Result.mat');
save(MAT_File, 'data_table', 'error_table', 'parameter_snapshot');

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
fprintf('  Data MAT: %s\n', MAT_File);

results = struct('parameters', parameter_snapshot, 'data', data_table, ...
    'errors', error_table, 'mat_file', MAT_File);
end

function Block_Paths = add_temporary_logs(mdl)
% 向现有测量信号添加仅用于运行时的临时日志模块。
sub = [mdl '/GFL_1/测量部分'];
names = {'i2_d', 'i2_q', 'i2'};
Block_Paths = cell(size(names));
for k = 1:numel(names)
    name = names{k};
    block = [sub '/Scan_Log_' name];
    Block_Paths{k} = block;
    if getSimulinkBlockHandle(block) == -1
        add_block('simulink/Sinks/To Workspace', block, ...
            'VariableName', ['Scan_' name], ...
            'SaveFormat', 'Timeseries', ...
            'Position', [1000 450+80*(k-1) 1160 480+80*(k-1)]);
    end
    Line_Handles = get_param(block, 'LineHandles');
    if isempty(Line_Handles.Inport) || all(Line_Handles.Inport == -1)
        Source_Handles = get_param([sub '/' name], 'PortHandles');
        add_line(sub, Source_Handles.Outport(1), ...
            get_param(block, 'PortHandles').Inport(1), ...
            'autorouting', 'on');
    end
end
end

function restore_scan_state(mdl, Temporary_Blocks, Stop_Time_Original, ...
    Solver_Original, Source_Block, Source_Voltage_Original, ...
    Source_Impedance_Original, Vg_original, Was_Loaded, Dirty_Original)
%% 移除临时信号块，恢复模型、工况参数及原有加载状态。
for ii = 1:numel(Temporary_Blocks)
    if getSimulinkBlockHandle(Temporary_Blocks{ii}) ~= -1
        delete_block(Temporary_Blocks{ii});
    end
end
if bdIsLoaded(mdl)
    set_param(mdl, 'StopTime', Stop_Time_Original, 'Solver', Solver_Original);
    set_param(Source_Block, 'Voltage', Source_Voltage_Original, ...
        'NonIdealSource', Source_Impedance_Original);
    set_param(mdl, 'Dirty', Dirty_Original);
end
assignin('base', 'Vg', Vg_original);
if ~Was_Loaded && bdIsLoaded(mdl)
    close_system(mdl, 0);
end
end

function value = mean_steady(ts, T_Start, T_Stop)
%% 从指定稳态时间窗提取均值，采样不足时选取末段数据。
[time, data] = timeseries_data(ts);
mask = time >= T_Start & time <= T_Stop;
if nnz(mask) < 5
    mask = false(size(time));
    mask(max(1, numel(time)-max(5, round(0.1*numel(time)))):end) = true;
end
data = double(data(mask, :));
value = mean(data, 'all', 'omitnan');
end

function [time, data] = timeseries_data(ts)
%% 提取timeseries的时间和数值，统一时间所在维度。
if isa(ts, 'timeseries')
    time = double(ts.Time(:));
    data = squeeze(ts.Data);
else
    error('Expected a timeseries output, received %s.', class(ts));
end
if size(data, 1) ~= numel(time) && size(data, 2) == numel(time)
    data = data.';
end
end

function [ID_Eq, Iq_Eq, I_Eq] = port_equivalent_current(u_pu, ...
    ID_Ref, Iq_Ref, I_Limit, V_Max, V_Min, kq, i_n, Delta_Iq_Max)
% 先执行LVRT电压支撑，再执行无功优先限流。
Delta_Iq_Max_From_Parameters = kq*(V_Max-V_Min)*i_n;
if abs(Delta_Iq_Max-Delta_Iq_Max_From_Parameters) > ...
        1e-10*max(1, abs(Delta_Iq_Max))
    error('Delta_Iq_LVRT_max is inconsistent with the LVRT parameters.');
end
Delta_Iq = kq .* max(V_Max - u_pu, 0);
Delta_Iq = min(Delta_Iq, Delta_Iq_Max);
Iq_Eq = Iq_Ref + Delta_Iq;
ID_Eq = ID_Ref*ones(size(u_pu));

% 优先为无功电流保留电流容量。
ID_Available = sqrt(max(I_Limit^2 - Iq_Eq.^2, 0));
ID_Eq(abs(ID_Eq) > ID_Available) = ...
    sign(ID_Eq(abs(ID_Eq) > ID_Available)) .* ...
    ID_Available(abs(ID_Eq) > ID_Available);
I_Eq = hypot(ID_Eq, Iq_Eq);

% 保留额定电流参数并尽早检查参数一致性。本模型中I_N通常为1 p.u.。
if ~(isscalar(i_n) && isfinite(i_n) && i_n > 0)
    error('I_N must be a positive scalar.');
end
end

function value = max_or_nan(x)
%% 返回有效数据的最大值，空输入返回NaN。
if isempty(x)
    value = NaN;
else
    value = max(x, [], 'omitnan');
end
end
