%% GFL-WG仿真收敛SCR边界搜索。
% 本文件集中展示验证过程；临时设置由局部函数的清理对象恢复。

%% 1. 设置验证选项
Validation_Options = struct('SCR_Tolerance', 0.005, ...
    'Stop_Time', 1.0, 'Tail_Window', [0.95 1.00]);

%% 2. 执行验证并保存结果
SCR_Convergence_Result = run_scan(Validation_Options);
SCR_Convergence_History = SCR_Convergence_Result.history;

% 主验证过程与局部辅助函数
function Result = run_scan(Overrides)
%% 按有限仿真窗口的收敛判据，搜索GFL模型的SCR边界。
if nargin < 1
    Overrides = struct();
end
cfg = default_config();
Fields = fieldnames(Overrides);
for k = 1:numel(Fields)
    Field = Fields{k};
    assert(isfield(cfg, Field), 'GFLBoundary:UnknownOption', '未知扫描选项：%s', Field);
    cfg.(Field) = Overrides.(Field);
end
if ~isfield(Overrides, 'Model_File')
    cfg.Model_File = fullfile(cfg.Model_Directory, [cfg.Model_Name, '.slx']);
end
Result = find_scr_boundary(cfg);
end

function cfg = default_config()
%% 集中定义SCR搜索范围、仿真窗口及收敛判据。
Project_Root = find_project_root(mfilename('fullpath'));
cfg.Work_Directory = Project_Root;
cfg.Model_Name = 'Grid_Following_Inverters';
cfg.Model_Directory = fullfile(Project_Root, 'simulink', 'models');
cfg.Model_File = fullfile(cfg.Model_Directory, [cfg.Model_Name, '.slx']);
cfg.Parameter_Script = fullfile(Project_Root, 'code', 'scripts', ...
    'equipment', 'initialization', 'initialize_gfl_model.m');
cfg.Signal_Name = 'v_PCC_mag';

cfg.Stop_Time = 1.0;
cfg.Tail_Window = [0.95, 1.00];

% 搜索设置；目标SCR区间宽度取0.005。
cfg.SCR_Tolerance = 0.005;
cfg.Bracket_Scale = 2.0;
cfg.SCR_Min = 0.05;
cfg.SCR_Max = 20.0;
cfg.Initial_SCR = NaN;  % NaN means: use SCR from initialize_gfl_model.m.
cfg.Max_Bisection_Iterations = 40;
cfg.Max_Bracket_Steps = 20;

% 电压幅值信号为相电压峰值，收敛指标按相电压峰值基准归一化。
cfg.Ripple_Limit_PU = 0.010;          % Tail-window peak-to-peak limit.
cfg.STD_Limit_PU = 0.003;             % Tail-window standard deviation limit.
cfg.Slope_Limit_PU_Per_Sec = 0.05;      % Linear trend slope limit.
cfg.Oscillation_Amplitude_Limit_PU = 0.003;  % Detrended oscillation amplitude limit.
cfg.Zero_Cross_Deadband_PU = 0.001;
cfg.Oscillation_Min_Zero_Crossings = 4;

% 平滑仅用于计算收敛指标，不改变仿真信号。
cfg.Smoothing_Window_Sec = 0.002;
cfg.Min_Tail_Points = 20;

cfg.Verbose = true;
end

function result = find_scr_boundary(cfg)
%% 初始化当前GFL模型，搜索并二分收敛与不收敛工况的SCR边界。
Old_Directory = pwd;
Cleanup_Obj = onCleanup(@() cd(Old_Directory));
cd(cfg.Work_Directory);

if ~isfile(cfg.Parameter_Script)
    error('Parameter script not found: %s', cfg.Parameter_Script);
end

if ~isfile(cfg.Model_File)
    error('Model file not found: %s', cfg.Model_File);
end

load_base_parameters(cfg);
Project_Root = find_project_root(cfg.Model_File);
Equipment_Directory = fullfile(Project_Root, 'code', 'functions');
if isempty(which('configure_simulink_file_generation'))
    addpath(genpath(Equipment_Directory));
end
File_Generation_Cleanup = configure_simulink_file_generation(Project_Root); %#ok<NASGU>
Was_Loaded = bdIsLoaded(cfg.Model_Name);
load_system(cfg.Model_File);
Original_Stop_Time = get_param(cfg.Model_Name, 'StopTime');
Original_Dirty = get_param(cfg.Model_Name, 'Dirty');
Original_Return_Outputs = get_param(cfg.Model_Name, 'ReturnWorkspaceOutputs');
Original_Parameters = struct();
Grid_Names = {'SCR', 'Zg', 'Rg', 'Lg'};
for j = 1:numel(Grid_Names)
    Name = Grid_Names{j};
    Original_Parameters.(Name) = evalin('base', Name);
end
Model_Cleanup = onCleanup(@() restore_scan( ...
    cfg.Model_Name, Was_Loaded, Original_Stop_Time, ...
    Original_Return_Outputs, Original_Parameters, Original_Dirty)); %#ok<NASGU>

set_param(cfg.Model_Name, 'ReturnWorkspaceOutputs', 'on');
set_param(cfg.Model_Name, 'StopTime', num_to_text(cfg.Stop_Time));

if isnan(cfg.Initial_SCR)
    cfg.Initial_SCR = evalin('base', 'SCR');
end
cfg.V_Base = evalin('base', 'V_base_phase');
validateattributes(cfg.V_Base, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});

fprintf('Searching SCR boundary for %s.\n', cfg.Model_Name);
fprintf('  Tail window : %.3f to %.3f s\n', cfg.Tail_Window(1), cfg.Tail_Window(2));
fprintf('  SCR target gap < %.6f\n\n', cfg.SCR_Tolerance);

history = empty_history();
[trial, history] = evaluate_and_store(cfg.Initial_SCR, cfg, history);

if trial.converged
    Stable_Trial = trial;
    Unstable_Trial = [];
    Next_SCR = cfg.Initial_SCR / cfg.Bracket_Scale;

    for step = 1:cfg.Max_Bracket_Steps
        if Next_SCR < cfg.SCR_Min
            break;
        end

        [trial, history] = evaluate_and_store(Next_SCR, cfg, history);
        if trial.converged
            Stable_Trial = trial;
            Next_SCR = Next_SCR / cfg.Bracket_Scale;
        else
            Unstable_Trial = trial;
            break;
        end
    end

    if isempty(Unstable_Trial)
        error(['No non-converged SCR was found down to SCR = %.6g. ', ...
            'Lower cfg.SCR_Min or start from a smaller cfg.Initial_SCR.'], cfg.SCR_Min);
    end
else
    Unstable_Trial = trial;
    Stable_Trial = [];
    Next_SCR = cfg.Initial_SCR * cfg.Bracket_Scale;

    for step = 1:cfg.Max_Bracket_Steps
        if Next_SCR > cfg.SCR_Max
            break;
        end

        [trial, history] = evaluate_and_store(Next_SCR, cfg, history);
        if trial.converged
            Stable_Trial = trial;
            break;
        else
            Unstable_Trial = trial;
            Next_SCR = Next_SCR * cfg.Bracket_Scale;
        end
    end

    if isempty(Stable_Trial)
        error(['No converged SCR was found up to SCR = %.6g. ', ...
            'Raise cfg.SCR_Max or start from a larger cfg.Initial_SCR.'], cfg.SCR_Max);
    end
end

for iter = 1:cfg.Max_Bisection_Iterations
    if abs(Stable_Trial.SCR - Unstable_Trial.SCR) < cfg.SCR_Tolerance
        break;
    end

    Mid_SCR = 0.5 * (Stable_Trial.SCR + Unstable_Trial.SCR);
    [trial, history] = evaluate_and_store(Mid_SCR, cfg, history);

    if trial.converged
        Stable_Trial = trial;
    else
        Unstable_Trial = trial;
    end
end

result = struct();
result.convergedSCR = Stable_Trial.SCR;
result.nonConvergedSCR = Unstable_Trial.SCR;
result.scrGap = abs(Stable_Trial.SCR - Unstable_Trial.SCR);
result.criticalSCRMidpoint = 0.5 * (Stable_Trial.SCR + Unstable_Trial.SCR);
result.toleranceTarget = cfg.SCR_Tolerance;
result.tailWindow = cfg.Tail_Window;
result.convergedMetrics = Stable_Trial.metrics;
result.nonConvergedMetrics = Unstable_Trial.metrics;
result.history = struct2table(history);
result.config = cfg;
end

function [trial, history] = evaluate_and_store(SCR_Value, cfg, history)
%% 评估一个SCR工况，并将判据和诊断追加到历史记录。
trial = evaluate_scr(SCR_Value, cfg);
% 仿真错误不是稳定性边界；不能把模型配置错误当成不收敛样本。
assert(trial.status ~= "sim_failed", 'GFLBoundary:SimulationFailed', ...
    'SCR=%.6g仿真失败：%s', SCR_Value, trial.metrics.message);
history(end + 1) = history_row(trial);

if cfg.Verbose
    fprintf(['SCR=%9.5f -> %-13s  ripple=%8.4g pu  std=%8.4g pu  ', ...
        'slope=%8.4g pu/s  oscAmp=%8.4g pu  zc=%2d  time=%6.2f s\n'], ...
        trial.SCR, char(trial.status), trial.metrics.ripplePu, ...
        trial.metrics.stdPu, trial.metrics.slopePuPerSec, ...
        trial.metrics.oscillationAmpPu, trial.metrics.oscillationZeroCrossings, ...
        trial.elapsedSec);
end
end

function trial = evaluate_scr(SCR_Value, cfg)
%% 设置电网等值阻抗，运行当前SCR工况并判断末段收敛性。
T_Start = tic;
metrics = blank_metrics();

trial = struct();
trial.SCR = SCR_Value;
trial.converged = false;
trial.status = "not_converged";
trial.metrics = metrics;
trial.elapsedSec = NaN;

try
    Grid_Vars = apply_scr_to_base(SCR_Value);

    Simulation_Input = Simulink.SimulationInput(cfg.Model_Name);
    Simulation_Input = Simulation_Input.setModelParameter( ...
        'StopTime', num_to_text(cfg.Stop_Time), ...
        'ReturnWorkspaceOutputs', 'on');
    Source_Settings = {'NonIdealSource', 'on'; 'SpecifyImpedance', 'off'; ...
        'Resistance', 'Rg'; 'Inductance', 'Lg'};
    for j = 1:size(Source_Settings, 1)
        Simulation_Input = Simulation_Input.setBlockParameter( ...
            [cfg.Model_Name '/Three-Phase Source'], ...
            Source_Settings{j, 1}, Source_Settings{j, 2});
    end

    Simulation_Input = Simulation_Input.setVariable('SCR', SCR_Value);
    Simulation_Input = Simulation_Input.setVariable('Zg', Grid_Vars.Zg);
    Simulation_Input = Simulation_Input.setVariable('Rg', Grid_Vars.Rg);
    Simulation_Input = Simulation_Input.setVariable('Lg', Grid_Vars.Lg);

    Simulation_Out = sim(Simulation_Input);
    [t, y] = extract_signal(Simulation_Out, cfg.Signal_Name);
    [trial.converged, metrics] = judge_convergence(t, y, cfg);

    if trial.converged
        trial.status = "converged";
    else
        trial.status = "not_converged";
    end
catch ME
    metrics.message = "Simulation or signal extraction failed: " + string(ME.message);
    trial.converged = false;
    trial.status = "sim_failed";
end

trial.metrics = metrics;
trial.elapsedSec = toc(T_Start);
end

function load_base_parameters(cfg)
%% 在基础工作区执行正式初始化脚本。
Escaped_Path = strrep(cfg.Parameter_Script, '''', '''''');
try
    evalc(sprintf('evalin(''base'', ''run(''''%s'''');'');', Escaped_Path));
catch ME
    error('Failed to run parameter script %s\n%s', cfg.Parameter_Script, ME.message);
end
end

function Grid_Vars = apply_scr_to_base(SCR_Value)
%% 按SCR换算电网等值阻抗，并发布当前仿真工况。
Vg = evalin('base', 'Vg');
S_base = evalin('base', 'S_base');
f = evalin('base', 'f');

Zg = Vg^2 / (S_base * SCR_Value);
Lg = Zg / (2 * pi * f);

assignin('base', 'SCR', SCR_Value);
assignin('base', 'Zg', Zg);
assignin('base', 'Rg', 0);
assignin('base', 'Lg', Lg);

Grid_Vars = struct('Zg', Zg, 'Rg', 0, 'Lg', Lg);
end

function restore_scan(Model, Was_Loaded, Stop_Time, Return_Outputs, Parameters, Dirty)
%% 恢复SCR扫描前的模型配置、工作区参数和加载状态。
for Name = {'SCR', 'Zg', 'Rg', 'Lg'}
    assignin('base', Name{1}, Parameters.(Name{1}));
end
if bdIsLoaded(Model)
    set_param(Model, 'StopTime', Stop_Time, ...
        'ReturnWorkspaceOutputs', Return_Outputs);
    set_param(Model, 'Dirty', Dirty);
    if ~Was_Loaded
        close_system(Model, 0);
    end
end
end

function [t, y] = extract_signal(Simulation_Out, Signal_Name)
%% 读取当前模型的timeseries输出，并核验其为标量时间序列。
Raw_Signal = Simulation_Out.get(Signal_Name);
assert(isa(Raw_Signal, 'timeseries'), 'GFLBoundary:InvalidSignalType', ...
    '当前模型的%s输出必须为timeseries。', Signal_Name);
t = double(Raw_Signal.Time(:));
y = double(squeeze(Raw_Signal.Data));
validateattributes(y, {'numeric'}, {'vector', 'numel', numel(t)});
y = y(:);
end

function [converged, metrics] = judge_convergence(t, y, cfg)
%% 按末段纹波、标准差、趋势及振荡幅值判断仿真收敛性。
metrics = blank_metrics();

valid = isfinite(t) & isfinite(y);
t = t(valid);
y = y(valid);

if isempty(t)
    metrics.message = "Signal is empty or non-finite.";
    converged = false;
    return;
end

[t, order] = sort(t);
y = y(order);

idx = (t >= cfg.Tail_Window(1)) & (t <= cfg.Tail_Window(2));
metrics.tailPointCount = nnz(idx);
if metrics.tailPointCount < cfg.Min_Tail_Points
    metrics.message = "Too few points in the tail window.";
    converged = false;
    return;
end

T_Tail = t(idx);
Y_Tail_PU = y(idx) ./ cfg.V_Base;

dt = median(diff(unique(T_Tail)));
if ~isfinite(dt) || dt <= 0
    metrics.message = "Tail-window time vector is not usable.";
    converged = false;
    return;
end

Smooth_Points = max(1, round(cfg.Smoothing_Window_Sec / dt));
if Smooth_Points > 1
    Y_Trend_PU = movmean(Y_Tail_PU, Smooth_Points, 'Endpoints', 'shrink');
else
    Y_Trend_PU = Y_Tail_PU;
end

T_Fit = T_Tail - T_Tail(1);
Fit_Coeff = polyfit(T_Fit, Y_Trend_PU, 1);
Fitted_PU = polyval(Fit_Coeff, T_Fit);
Residual_PU = Y_Trend_PU - Fitted_PU;

metrics.meanPu = mean(Y_Trend_PU);
metrics.ripplePu = max(Y_Trend_PU) - min(Y_Trend_PU);
metrics.stdPu = std(Y_Trend_PU);
metrics.slopePuPerSec = abs(Fit_Coeff(1));
metrics.oscillationAmpPu = 0.5 * (max(Residual_PU) - min(Residual_PU));
metrics.oscillationZeroCrossings = significant_zero_crossings( ...
    Residual_PU, cfg.Zero_Cross_Deadband_PU);

metrics.smallRipple = metrics.ripplePu <= cfg.Ripple_Limit_PU;
metrics.lowStd = metrics.stdPu <= cfg.STD_Limit_PU;
metrics.lowSlope = metrics.slopePuPerSec <= cfg.Slope_Limit_PU_Per_Sec;
metrics.noSustainedOscillation = ...
    (metrics.oscillationAmpPu <= cfg.Oscillation_Amplitude_Limit_PU) || ...
    (metrics.oscillationZeroCrossings < cfg.Oscillation_Min_Zero_Crossings);

converged = metrics.smallRipple && metrics.lowStd && ...
    metrics.lowSlope && metrics.noSustainedOscillation;

if converged
    metrics.message = "Tail window is settled.";
else
    metrics.message = sprintf(['Not settled: smallRipple=%d, lowStd=%d, ', ...
        'lowSlope=%d, noSustainedOscillation=%d.'], ...
        metrics.smallRipple, metrics.lowStd, metrics.lowSlope, ...
        metrics.noSustainedOscillation);
end
end

function count = significant_zero_crossings(x, deadband)
%% 忽略死区内的小幅变化，统计有效过零次数。
x = x(:) - mean(x(:));
x(abs(x) < deadband) = 0;
signs = sign(x);
signs(signs == 0) = [];

if numel(signs) < 2
    count = 0;
else
    count = sum(signs(1:end-1) .* signs(2:end) < 0);
end
end

function metrics = blank_metrics()
%% 初始化未完成仿真的收敛指标。
metrics = struct();
metrics.tailPointCount = 0;
metrics.meanPu = NaN;
metrics.ripplePu = NaN;
metrics.stdPu = NaN;
metrics.slopePuPerSec = NaN;
metrics.oscillationAmpPu = NaN;
metrics.oscillationZeroCrossings = 0;
metrics.smallRipple = false;
metrics.lowStd = false;
metrics.lowSlope = false;
metrics.noSustainedOscillation = false;
metrics.message = "";
end

function history = empty_history()
%% 创建与逐工况记录字段一致的空历史数组。
row = struct();
row.SCR = NaN;
row.converged = false;
row.status = "";
row.elapsedSec = NaN;
row.tailPointCount = 0;
row.meanPu = NaN;
row.ripplePu = NaN;
row.stdPu = NaN;
row.slopePuPerSec = NaN;
row.oscillationAmpPu = NaN;
row.oscillationZeroCrossings = 0;
row.smallRipple = false;
row.lowStd = false;
row.lowSlope = false;
row.noSustainedOscillation = false;
row.message = "";
history = row([]);
end

function row = history_row(trial)
%% 将一次SCR评估结果转换为历史记录行。
row = struct();
row.SCR = trial.SCR;
row.converged = trial.converged;
row.status = trial.status;
row.elapsedSec = trial.elapsedSec;
row.tailPointCount = trial.metrics.tailPointCount;
row.meanPu = trial.metrics.meanPu;
row.ripplePu = trial.metrics.ripplePu;
row.stdPu = trial.metrics.stdPu;
row.slopePuPerSec = trial.metrics.slopePuPerSec;
row.oscillationAmpPu = trial.metrics.oscillationAmpPu;
row.oscillationZeroCrossings = trial.metrics.oscillationZeroCrossings;
row.smallRipple = trial.metrics.smallRipple;
row.lowStd = trial.metrics.lowStd;
row.lowSlope = trial.metrics.lowSlope;
row.noSustainedOscillation = trial.metrics.noSustainedOscillation;
row.message = string(trial.metrics.message);
end

function text = num_to_text(value)
%% 以足够精度将数值转换为Simulink参数文本。
text = sprintf('%.15g', value);
end
