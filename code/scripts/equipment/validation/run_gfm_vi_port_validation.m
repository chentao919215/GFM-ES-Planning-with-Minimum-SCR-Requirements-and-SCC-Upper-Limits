%% GFM-ES虚拟阻抗限流端口特性验证。
% 本文件集中展示验证过程；临时设置由局部函数的清理对象恢复。

%% 1. 设置验证选项
Validation_Options = struct();
% 指定扫描子集时可设置：Validation_Options.Case_Indices = 1:15;

%% 2. 执行验证并保存结果
[Validation_Result, Result_File] = run_validation(Validation_Options);
Project_Root = find_project_root(mfilename('fullpath'));
Figure_File = fullfile(Project_Root, 'figs', 'equipment', 'GFM', ...
    'GFM_VI_Port_Characteristic_Validation.fig');
Figure_Handle = plot_gfm_vi_port_validation( ...
    Validation_Result, Figure_File, figure_style('review'));

% 主验证过程与局部辅助函数
function [ValidationResult, Result_File] = run_validation(Options)
%% 编排模型验证与数值结果归档，绘图由独立入口负责。
if nargin < 1
    Options = struct();
end
Project_Root = find_project_root(mfilename('fullpath'));
% 使用正式 Grid_Forming_Inverters.slx 和正式 initialize_gfm_model.m，扫描
% 不同外部三相电源电压工况，提取故障持续阶段的准稳态 UPCC、IGFM 和
% 实际 Slim，并与严格两状态分段理论模型比较。
%
% 本函数不保存Simulink模型，不覆盖ReleaseConfirmTime、Ub、
% 虚拟阻抗参数或主控制器参数。故障深度仅通过 SimulationInput 临时覆盖
% 可编程三相电源的 Amplitudes/TimeValues。

%% 1. 路径和正式参数初始化

Result_Dir = fullfile(Project_Root, 'results', 'equipment', 'GFM');
if isfield(Options, 'Result_Directory')
    Result_Dir = Options.Result_Directory;
end
Figure_Dir = fullfile(Project_Root, 'figs', 'equipment', 'GFM');
if ~isfolder(Result_Dir)
    mkdir(Result_Dir);
end
if ~isfolder(Figure_Dir)
    mkdir(Figure_Dir);
end

Model_File = fullfile(Project_Root, 'simulink', 'models', ...
    'Grid_Forming_Inverters.slx');
Parameter_File = fullfile(Project_Root, 'code', 'scripts', 'equipment', ...
    'initialization', 'initialize_gfm_model.m');
Reference_Plot_File = fullfile(Project_Root, 'code', 'scripts', 'figure', ...
    'equipment', 'GFM', 'plot_gfm_vi_limited.m');

assert(isfile(Model_File), 'Formal GFM model was not found: %s', Model_File);
assert(isfile(Parameter_File), ...
    'Formal GFM parameter script was not found: %s', Parameter_File);
assert(isfile(Reference_Plot_File), ...
    'GFM reference plot script was not found: %s', Reference_Plot_File);

addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
File_Generation_Cleanup = configure_simulink_file_generation(Project_Root); %#ok<NASGU>

run(Parameter_File);

Model_Name = 'Grid_Forming_Inverters';
Was_Loaded = bdIsLoaded(Model_Name);
load_system(Model_File);
Model_Cleanup = onCleanup(@() close_model(Model_Name, Was_Loaded)); %#ok<NASGU>
Source_Block = [Model_Name '/Three-Phase Source'];
assert(getSimulinkBlockHandle(Source_Block) > 0, ...
    'The programmable three-phase source was not found.');
assert(strcmp(get_param(Source_Block, 'VariationEntity'), 'Amplitude') && ...
    strcmp(get_param(Source_Block, 'VariationType'), ...
    'Table of time-amplitude pairs'), ...
    'The formal source is not configured for a time-amplitude table.');

%% 2. 固定内电势理论参数（只读取正式参数体系）
E_GFM = GFM_Droop.E0_pu;
X_res = GFM_VI.X_res_device_pu;
X_VI = GFM_VI.X_vir_device_pu;
I_lim = GFM_VI.I_switch_threshold_pu;
U_boundary = GFM_VI.U_boundary_pu;
Release_Confirm_Time = GFM_VI.ReleaseConfirmTime;

theory = struct();
theory.E0_pu = E_GFM;
theory.R_L2_pu = R_L2/Z_base;
theory.X_L2_pu = 2*pi*f*L2/Z_base;
theory.X_res_device_pu = X_res;
theory.X_vir_pu = X_VI;
theory.I_lim_pu = I_lim;
theory.U_boundary_pu = U_boundary;
theory.ReleaseConfirmTime_s = Release_Confirm_Time;

assert(GFM_VI.Enable, 'Formal virtual-impedance limiting is disabled.');
assert(X_res > 0 && X_VI > 0 && I_lim > 0, ...
    'Formal virtual-impedance parameters must be positive.');
assert(abs(GFM_Droop.nq) < 1e-12, ...
    'Fixed-internal-voltage theory requires GFM_Droop.nq = 0.');
assert(abs(U_boundary-(E_GFM-X_res*I_lim)) < 1e-12, ...
    'Formal U_boundary_pu is inconsistent with E0-Xres*Ilim.');
assert(abs(X_res-theory.X_L2_pu) < 1e-12, ...
    'Physical L2 must provide the complete device-base X_res.');

theory.U_current_threshold_pu = ...
    find_current_threshold_voltage(theory, 0, 1);
theory.I_pre_switch_pu = calculate_gfm_port_current(U_boundary, 0, theory);
theory.I_post_switch_pu = calculate_gfm_port_current(U_boundary, 1, theory);
theory.I_boundary_drop_pu = ...
    theory.I_pre_switch_pu-theory.I_post_switch_pu;

%% 3. 故障深度和准稳态扫描设置
% DirectSag：从正常电压直接进入最终浅跌落，预期保持 Slim=0。
% LatchedSag：先以 0.20 p.u. 完成合法触发，再进入最终故障深度。
% 统计窗口只位于最终故障阶段，不包含触发脉冲或投切瞬间。
Pre_Fault_Voltage_pu = GFM_GridSource.CaseA.SourceVoltage_pu;
Direct_Sag_Targets_pu = [0.90, 0.80, 0.70, 0.60, 0.50, 0.44, 0.41];
Latched_Sag_Targets_pu = [0.10, 0.20, 0.30, 0.40, ...
    0.55, 0.68, 0.74, 0.75];
Trigger_Voltage_pu = 0.20;

Fault_Start_Time_s = 2.0;
Trigger_End_Time_s = 2.30;
% 电压外环积分增益较保守；5 s 工况会把幅值纹波已经很小、但 vMid
% 仍在慢速逼近 E_ref 的点误判为最终准稳态。10 s 可将该跟踪偏差降至
% 端口理论比较所需的量级，且不修改任何控制器参数。
Simulation_Stop_Time_s = 10.0;
Source_Transition_Time_s = GFM_GridSource.TransitionTime_s;

Analysis_Options = struct();
Analysis_Options.WindowDurations_s = [0.80, 0.60, 0.40, 0.25];
Analysis_Options.WindowEndMargin_s = 0.10;
Analysis_Options.MinimumSettling_s = 2.00;
Analysis_Options.SampleTime_s = 5e-4;
Analysis_Options.VoltageStdAbsLimit_pu = 2e-3;
Analysis_Options.VoltageStdRelLimit = 5e-3;
Analysis_Options.CurrentStdAbsLimit_pu = 3e-3;
Analysis_Options.CurrentStdRelLimit = 1e-2;
Analysis_Options.VoltageDriftAbsLimit_pu = 3e-3;
Analysis_Options.CurrentDriftAbsLimit_pu = 5e-3;

%% 4. 构造 15 个独立工况
N_Direct = numel(Direct_Sag_Targets_pu);
N_Latched = numel(Latched_Sag_Targets_pu);
N_Cases = N_Direct+N_Latched;
Case_Template = struct('CaseID', 0, 'CaseName', "", 'Protocol', "", ...
    'FinalSourceVoltage_pu', NaN, 'TriggerSourceVoltage_pu', NaN, ...
    'ExpectedSlim', NaN, 'Amplitudes_pu', [], 'TimeValues_s', [], ...
    'FinalStageStart_s', NaN);
Case_Specifications = repmat(Case_Template, N_Cases, 1);

for Case_Index = 1:N_Direct
    target = Direct_Sag_Targets_pu(Case_Index);
    Case_Specifications(Case_Index).CaseID = Case_Index;
    Case_Specifications(Case_Index).CaseName = sprintf('Direct-%02d', Case_Index);
    Case_Specifications(Case_Index).Protocol = "DirectSag";
    Case_Specifications(Case_Index).FinalSourceVoltage_pu = target;
    Case_Specifications(Case_Index).ExpectedSlim = 0;
    Case_Specifications(Case_Index).Amplitudes_pu = ...
        [Pre_Fault_Voltage_pu, Pre_Fault_Voltage_pu, target, target];
    Case_Specifications(Case_Index).TimeValues_s = ...
        [0, Fault_Start_Time_s, ...
        Fault_Start_Time_s+Source_Transition_Time_s, Simulation_Stop_Time_s];
    Case_Specifications(Case_Index).FinalStageStart_s = ...
        Fault_Start_Time_s+Source_Transition_Time_s;
end

for Local_Index = 1:N_Latched
    Case_Index = N_Direct+Local_Index;
    target = Latched_Sag_Targets_pu(Local_Index);
    Case_Specifications(Case_Index).CaseID = Case_Index;
    Case_Specifications(Case_Index).CaseName = sprintf('Latched-%02d', Local_Index);
    Case_Specifications(Case_Index).Protocol = "LatchedSag";
    Case_Specifications(Case_Index).FinalSourceVoltage_pu = target;
    Case_Specifications(Case_Index).TriggerSourceVoltage_pu = Trigger_Voltage_pu;
    Case_Specifications(Case_Index).ExpectedSlim = 1;
    Case_Specifications(Case_Index).Amplitudes_pu = ...
        [Pre_Fault_Voltage_pu, Pre_Fault_Voltage_pu, ...
        Trigger_Voltage_pu, Trigger_Voltage_pu, target, target];
    Case_Specifications(Case_Index).TimeValues_s = ...
        [0, Fault_Start_Time_s, ...
        Fault_Start_Time_s+Source_Transition_Time_s, Trigger_End_Time_s, ...
        Trigger_End_Time_s+Source_Transition_Time_s, Simulation_Stop_Time_s];
    Case_Specifications(Case_Index).FinalStageStart_s = ...
        Trigger_End_Time_s+Source_Transition_Time_s;
end

Scan_Config = struct();
Scan_Config.PreFaultVoltage_pu = Pre_Fault_Voltage_pu;
Scan_Config.DirectSagTargets_pu = Direct_Sag_Targets_pu;
Scan_Config.LatchedSagTargets_pu = Latched_Sag_Targets_pu;
Scan_Config.TriggerVoltage_pu = Trigger_Voltage_pu;
Scan_Config.FaultStartTime_s = Fault_Start_Time_s;
Scan_Config.TriggerEndTime_s = Trigger_End_Time_s;
Scan_Config.StopTime_s = Simulation_Stop_Time_s;
Scan_Config.SourceTransitionTime_s = Source_Transition_Time_s;
Scan_Config.AnalysisOptions = Analysis_Options;

if isfield(Options, 'Case_Indices')
    validateattributes(Options.Case_Indices, {'numeric'}, ...
        {'integer', 'positive', 'vector', '<=', numel(Case_Specifications)});
    Case_Specifications = Case_Specifications(Options.Case_Indices);
    N_Cases = numel(Case_Specifications);
end

%% 5. 运行所有工况并提取端口点
Scan_Points = repmat(empty_point(), N_Cases, 1);
fprintf('\n=== GFM virtual-impedance port-characteristic scan ===\n');
fprintf('Model: %s\n', Model_File);
fprintf('Parameter file: %s\n', Parameter_File);
fprintf(['E0=%.6f, nq=0, XL2=%.6f, RL2=%.6f, Xvir=%.6f, ' ...
    'Ub=%.6f, U(Ilim)=%.6f, Ilim=%.6f, ReleaseConfirmTime=%.6f s\n'], ...
    theory.E0_pu, theory.X_L2_pu, theory.R_L2_pu, ...
    theory.X_vir_pu, theory.U_boundary_pu, ...
    theory.U_current_threshold_pu, theory.I_lim_pu, Release_Confirm_Time);
fprintf('Independent source-voltage cases: %d\n\n', N_Cases);

for Case_Index = 1:N_Cases
    Case_Spec = Case_Specifications(Case_Index);
    fprintf('[%02d/%02d] %-10s final command %.3f p.u. ... ', ...
        Case_Index, N_Cases, Case_Spec.Protocol, ...
        Case_Spec.FinalSourceVoltage_pu);
    Scan_Points(Case_Index) = run_case(Model_Name, Source_Block, ...
        Case_Spec, Simulation_Stop_Time_s, Analysis_Options, theory);

    point = Scan_Points(Case_Index);
    if point.SimulationSucceeded
        fprintf(['UPCC %.4f, IGFM %.4f, Slim %.0f, ' ...
            'std(U/I) %.2e/%.2e, valid %d\n'], ...
            point.U_PCC_mean_pu, point.I_GFM_mean_pu, ...
            point.Slim_state, point.U_PCC_std_pu, ...
            point.I_GFM_std_pu, point.Valid);
    else
        fprintf('FAILED: %s\n', point.Notes);
    end
end

Points_Table = struct2table(Scan_Points);
Valid_Mask = Points_Table.Valid;
Unlimited_Mask = Valid_Mask & Points_Table.Slim_state == 0;
Limited_Mask = Valid_Mask & Points_Table.Slim_state == 1;
Boundary_Mismatch_Mask = Valid_Mask & ~Points_Table.UbPartitionConsistent;

Unlimited_Slope_D_ID_U = NaN;
Limited_Slope_D_ID_U = NaN;
if nnz(Unlimited_Mask) >= 2
    Slope_Fit = polyfit(Points_Table.U_PCC_mean_pu(Unlimited_Mask), ...
        Points_Table.I_GFM_mean_pu(Unlimited_Mask), 1);
    Unlimited_Slope_D_ID_U = Slope_Fit(1);
end
if nnz(Limited_Mask) >= 2
    Slope_Fit = polyfit(Points_Table.U_PCC_mean_pu(Limited_Mask), ...
        Points_Table.I_GFM_mean_pu(Limited_Mask), 1);
    Limited_Slope_D_ID_U = Slope_Fit(1);
end
Boundary_Current_Drop_pu = NaN;
if any(Unlimited_Mask) && any(Limited_Mask)
    Unlimited_Rows = find(Unlimited_Mask);
    Limited_Rows = find(Limited_Mask);
    [~, nearestUnlimited] = min(Points_Table.U_PCC_mean_pu(Unlimited_Rows));
    [~, nearestLimited] = max(Points_Table.U_PCC_mean_pu(Limited_Rows));
    Boundary_Current_Drop_pu = ...
        Points_Table.I_GFM_mean_pu(Unlimited_Rows(nearestUnlimited)) - ...
        Points_Table.I_GFM_mean_pu(Limited_Rows(nearestLimited));
end

Summary_Table = table(N_Cases, nnz(Valid_Mask), ...
    nnz(Unlimited_Mask), nnz(Limited_Mask), nnz(Boundary_Mismatch_Mask), ...
    mean_or_nan(Points_Table.CurrentError_percent(Unlimited_Mask)), ...
    max_or_nan(Points_Table.CurrentError_percent(Unlimited_Mask)), ...
    mean_or_nan(Points_Table.CurrentError_percent(Limited_Mask)), ...
    max_or_nan(Points_Table.CurrentError_percent(Limited_Mask)), ...
    max_or_nan(Points_Table.CurrentError_percent(Valid_Mask)), ...
    Unlimited_Slope_D_ID_U, Limited_Slope_D_ID_U, Boundary_Current_Drop_pu, ...
    theory.U_current_threshold_pu, theory.U_boundary_pu, ...
    theory.I_pre_switch_pu, theory.I_post_switch_pu, ...
    theory.I_boundary_drop_pu, ...
    'VariableNames', {'ScannedCases', 'ValidPoints', ...
    'UnlimitedPoints', 'LimitedPoints', 'UbMismatchPoints', ...
    'UnlimitedMeanError_percent', 'UnlimitedMaxError_percent', ...
    'LimitedMeanError_percent', 'LimitedMaxError_percent', ...
    'OverallMaxError_percent', 'UnlimitedSlope_dIdU', ...
    'LimitedSlope_dIdU', 'BoundaryCurrentDrop_pu', ...
    'CurrentThresholdVoltage_pu', 'FormalBoundaryVoltage_pu', ...
    'FormalBoundaryPreSwitchCurrent_pu', ...
    'FormalBoundaryPostSwitchCurrent_pu', ...
    'TheoreticalBoundaryCurrentDrop_pu'});

%% 6. 保存数值结果和图件目标位置
figureFile = fullfile(Figure_Dir, ...
    'GFM_VI_Port_Characteristic_Validation.fig');
resultFile = fullfile(Result_Dir, ...
    'GFM_VI_Port_Characteristic_Validation_Result.mat');
Points_CSV_File = fullfile(Result_Dir, ...
    'GFM_VI_Port_Characteristic_Validation_Points.csv');
Summary_CSV_File = fullfile(Result_Dir, ...
    'GFM_VI_Port_Characteristic_Validation_Summary.csv');

writetable(Points_Table, Points_CSV_File, 'Encoding', 'UTF-8');
writetable(Summary_Table, Summary_CSV_File, 'Encoding', 'UTF-8');

ValidationResult = struct();
ValidationResult.GeneratedAt = datetime('now', ...
    'TimeZone', 'Asia/Shanghai');
ValidationResult.ModelFile = Model_File;
ValidationResult.ParameterFile = Parameter_File;
ValidationResult.ReferencePlotFile = Reference_Plot_File;
ValidationResult.SourceBlock = Source_Block;
ValidationResult.Theory = theory;
ValidationResult.ScanConfig = Scan_Config;
ValidationResult.CaseSpecifications = Case_Specifications;
ValidationResult.Points = Points_Table;
ValidationResult.Summary = Summary_Table;
ValidationResult.OutputFiles = struct('FIG', figureFile, ...
    'PointsCSV', Points_CSV_File, 'SummaryCSV', Summary_CSV_File);
save(resultFile, 'ValidationResult', '-v7.3');

fprintf('\n=== Port-characteristic validation summary ===\n');
disp(Summary_Table);
fprintf('MAT: %s\n', resultFile);
fprintf('Points CSV: %s\n', Points_CSV_File);
fprintf('Summary CSV: %s\n', Summary_CSV_File);

Result_File = resultFile;
end

function close_model(Model_Name, Was_Loaded)
%% 仅关闭本次调用新加载的模型，不保存临时修改。
if ~Was_Loaded && bdIsLoaded(Model_Name)
    close_system(Model_Name, 0);
end
end

function point = run_case(Model_Name, Source_Block, Case_Spec, ...
    Stop_Time_s, options, theory)
%% 设置单个故障协议，执行仿真并提取端口验收指标。
point = empty_point();
point.CaseID = Case_Spec.CaseID;
point.CaseName = string(Case_Spec.CaseName);
point.Protocol = string(Case_Spec.Protocol);
point.FinalSourceVoltage_pu = Case_Spec.FinalSourceVoltage_pu;
point.TriggerSourceVoltage_pu = Case_Spec.TriggerSourceVoltage_pu;
point.ExpectedSlim = Case_Spec.ExpectedSlim;

try
    Simulation_Input = Simulink.SimulationInput(Model_Name);
    Simulation_Input = Simulation_Input.setBlockParameter( ...
        Source_Block, 'Amplitudes', ...
        mat2str(Case_Spec.Amplitudes_pu, 17));
    Simulation_Input = Simulation_Input.setBlockParameter( ...
        Source_Block, 'TimeValues', ...
        mat2str(Case_Spec.TimeValues_s, 17));
    Simulation_Input = Simulation_Input.setModelParameter( ...
        'StopTime', num2str(Stop_Time_s, 17), ...
        'ReturnWorkspaceOutputs', 'on');

    Elapsed_Timer = tic;
    Simulation_Output = sim(Simulation_Input);
    point.SimulationElapsed_s = toc(Elapsed_Timer);
    point.SimulationSucceeded = true;

    logs = Simulation_Output.logsout;
    assert(isa(logs, 'Simulink.SimulationData.Dataset'), ...
        'logsout is not a Dataset.');
    Signal_Names = logs.getElementNames;
    required = {'U_PCC_pu', 'I_GFM_mag_pu', 'Slim'};
    missing = required(~ismember(required, Signal_Names));
    assert(isempty(missing), ...
        'Missing logged signals: %s', strjoin(missing, ', '));

    Voltage_Signal = logs.getElement('U_PCC_pu').Values;
    Current_Signal = logs.getElement('I_GFM_mag_pu').Values;
    Slim_Signal = logs.getElement('Slim').Values;
    [~, Slim_Data] = signal_data(Slim_Signal, 'Slim');
    point.TotalSlimTransitions = ...
        nnz(diff(double(Slim_Data >= 0.5)) ~= 0);

    window = select_window(Voltage_Signal, Current_Signal, ...
        Slim_Signal, Case_Spec.FinalStageStart_s, Stop_Time_s, options);
    point.WindowStart_s = window.StartTime_s;
    point.WindowEnd_s = window.EndTime_s;
    point.WindowDuration_s = window.EndTime_s-window.StartTime_s;
    point.U_PCC_mean_pu = window.VoltageMean_pu;
    point.U_PCC_median_pu = window.VoltageMedian_pu;
    point.U_PCC_std_pu = window.VoltageStd_pu;
    point.U_PCC_peak_to_peak_pu = window.VoltagePeakToPeak_pu;
    point.U_PCC_drift_pu = window.VoltageDrift_pu;
    point.I_GFM_mean_pu = window.CurrentMean_pu;
    point.I_GFM_median_pu = window.CurrentMedian_pu;
    point.I_GFM_std_pu = window.CurrentStd_pu;
    point.I_GFM_peak_to_peak_pu = window.CurrentPeakToPeak_pu;
    point.I_GFM_drift_pu = window.CurrentDrift_pu;
    point.Slim_mean = window.SlimMean;
    point.Slim_state = window.SlimState;
    point.WindowSlimTransitions = window.SlimTransitions;
    point.StateStable = window.StateStable;
    point.QuasiSteady = window.QuasiSteady;
    point.FiniteSignals = window.FiniteSignals;

    if point.Slim_state == 0
        point.Branch = "Unlimited";
        [point.I_GFM_theory_pu, point.E_ref_theory_pu, ...
            point.TheoryErefSaturated] = calculate_gfm_port_current( ...
            point.U_PCC_mean_pu, 0, theory);
        point.UbPartitionConsistent = ...
            point.U_PCC_mean_pu >= theory.U_boundary_pu;
    elseif point.Slim_state == 1
        point.Branch = "Limited";
        [point.I_GFM_theory_pu, point.E_ref_theory_pu, ...
            point.TheoryErefSaturated] = calculate_gfm_port_current( ...
            point.U_PCC_mean_pu, 1, theory);
        point.UbPartitionConsistent = ...
            point.U_PCC_mean_pu < theory.U_boundary_pu;
    else
        point.Branch = "Mixed";
        point.I_GFM_theory_pu = NaN;
        point.E_ref_theory_pu = NaN;
        point.TheoryErefSaturated = false;
        point.UbPartitionConsistent = false;
    end

    point.ExpectedStateMatch = ...
        point.Slim_state == Case_Spec.ExpectedSlim;
    point.CurrentError_percent = 100*abs( ...
        point.I_GFM_mean_pu-point.I_GFM_theory_pu) / ...
        max(abs(point.I_GFM_mean_pu), 1e-9);
    point.Valid = point.FiniteSignals && ...
        point.StateStable && point.QuasiSteady;

    notes = strings(0, 1);
    if ~point.QuasiSteady
        notes(end+1) = "Quasi-steady limits not satisfied";
    end
    if ~point.StateStable
        notes(end+1) = "Slim changed inside statistics window";
    end
    if ~point.UbPartitionConsistent
        notes(end+1) = "Actual Slim disagrees with Ub partition";
    end
    if ~point.ExpectedStateMatch
        notes(end+1) = "Actual Slim differs from scan expectation";
    end
    if isempty(notes)
        point.Notes = "Valid quasi-steady point";
    else
        point.Notes = strjoin(notes, ' | ');
    end
catch exception
    point.SimulationSucceeded = false;
    point.Valid = false;
    point.Notes = string(exception.message);
end
end

function voltage = find_current_threshold_voltage(theory, Umin, Umax)
%% 求解端口电流达到限流阈值时的残余电压。
radicand = theory.E0_pu^2 ...
    -(theory.R_L2_pu*theory.I_lim_pu)^2;
assert(radicand >= 0, ...
    'I_lim is outside the feasible fixed-E port equation.');
voltage = sqrt(radicand) ...
    -theory.X_L2_pu*theory.I_lim_pu;
assert(voltage >= Umin && voltage <= Umax, ...
    'No I_GFM=I_lim crossing exists in the voltage scan range.');
end
function window = select_window(Voltage_Signal, Current_Signal, ...
    Slim_Signal, Final_Stage_Start_s, Stop_Time_s, options)
%% 从候选末段窗口中选取满足状态和准稳态要求的采样。
[Voltage_Time, Voltage_Data] = ...
    signal_data(Voltage_Signal, 'U_PCC_pu');
[Current_Time, Current_Data] = ...
    signal_data(Current_Signal, 'I_GFM_mag_pu');
[Slim_Time, Slim_Data] = signal_data(Slim_Signal, 'Slim');

Window_End = Stop_Time_s-options.WindowEndMargin_s;
Earliest_Start = Final_Stage_Start_s+options.MinimumSettling_s;
selected = struct();

for Duration_Index = 1:numel(options.WindowDurations_s)
    Window_Start = max(Earliest_Start, ...
        Window_End-options.WindowDurations_s(Duration_Index));
    if Window_End-Window_Start < 0.20
        continue;
    end
    candidate = window_metrics(Voltage_Time, Voltage_Data, ...
        Current_Time, Current_Data, Slim_Time, Slim_Data, ...
        Window_Start, Window_End, options);
    selected = candidate;
    if candidate.QuasiSteady && candidate.StateStable && ...
            candidate.FiniteSignals
        break;
    end
end

if isempty(fieldnames(selected))
    error('No usable steady-state statistics window was available.');
end
window = selected;
end

function metrics = window_metrics(Voltage_Time, Voltage_Data, ...
    Current_Time, Current_Data, Slim_Time, Slim_Data, ...
    Window_Start, Window_End, options)
%% 计算指定窗口内的电压、电流漂移及限流状态稳定性。
Query_Time = (Window_Start:options.SampleTime_s:Window_End).';
if Query_Time(end) < Window_End
    Query_Time(end+1, 1) = Window_End;
end

voltage = interp1(Voltage_Time, Voltage_Data, ...
    Query_Time, 'linear', 'extrap');
current = interp1(Current_Time, Current_Data, ...
    Query_Time, 'linear', 'extrap');
slim = interp1(Slim_Time, Slim_Data, ...
    Query_Time, 'previous', 'extrap');
slim = double(slim >= 0.5);

Finite_Signals = all(isfinite(voltage)) && ...
    all(isfinite(current)) && all(isfinite(slim));
Voltage_Mean = mean(voltage);
Current_Mean = mean(current);
Voltage_STD = std(voltage);
Current_STD = std(current);
Section_Length = max(2, floor(0.20*numel(Query_Time)));
Voltage_Drift = abs(mean(voltage(end-Section_Length+1:end)) - ...
    mean(voltage(1:Section_Length)));
Current_Drift = abs(mean(current(end-Section_Length+1:end)) - ...
    mean(current(1:Section_Length)));

Voltage_STD_Limit = max(options.VoltageStdAbsLimit_pu, ...
    options.VoltageStdRelLimit*max(abs(Voltage_Mean), 1e-6));
Current_STD_Limit = max(options.CurrentStdAbsLimit_pu, ...
    options.CurrentStdRelLimit*max(abs(Current_Mean), 1e-6));
Quasi_Steady = Voltage_STD <= Voltage_STD_Limit && ...
    Current_STD <= Current_STD_Limit && ...
    Voltage_Drift <= options.VoltageDriftAbsLimit_pu && ...
    Current_Drift <= options.CurrentDriftAbsLimit_pu;
Slim_Transitions = nnz(diff(slim) ~= 0);

metrics = struct();
metrics.StartTime_s = Window_Start;
metrics.EndTime_s = Window_End;
metrics.VoltageMean_pu = Voltage_Mean;
metrics.VoltageMedian_pu = median(voltage);
metrics.VoltageStd_pu = Voltage_STD;
metrics.VoltagePeakToPeak_pu = max(voltage)-min(voltage);
metrics.VoltageDrift_pu = Voltage_Drift;
metrics.CurrentMean_pu = Current_Mean;
metrics.CurrentMedian_pu = median(current);
metrics.CurrentStd_pu = Current_STD;
metrics.CurrentPeakToPeak_pu = max(current)-min(current);
metrics.CurrentDrift_pu = Current_Drift;
metrics.SlimMean = mean(slim);
metrics.SlimState = round(median(slim));
metrics.SlimTransitions = Slim_Transitions;
metrics.StateStable = Slim_Transitions == 0;
metrics.QuasiSteady = Quasi_Steady;
metrics.FiniteSignals = Finite_Signals;
end

function [time, data] = signal_data(signal, Signal_Name)
%% 读取标量timeseries，保留重复时刻的最后一个样本。
assert(isa(signal, 'timeseries'), ...
    '%s must be a timeseries.', Signal_Name);
time = double(signal.Time(:));
data = double(squeeze(signal.Data));
data = data(:);
assert(numel(data) == numel(time), ...
    '%s time and data lengths differ.', Signal_Name);
[time, uniqueIndex] = unique(time, 'last');
data = data(uniqueIndex);
assert(numel(time) >= 2, '%s has insufficient data.', Signal_Name);
end

function value = mean_or_nan(values)
%% 返回有限数值的均值，无有效样本时返回NaN。
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = mean(values);
end
end

function value = max_or_nan(values)
%% 返回有效数据的最大值，空输入返回NaN。
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = max(values);
end
end

function point = empty_point()
%% 初始化单个端口验证工况的结果与诊断字段。
point = struct( ...
    'CaseID', 0, 'CaseName', "", 'Protocol', "", ...
    'FinalSourceVoltage_pu', NaN, ...
    'TriggerSourceVoltage_pu', NaN, 'ExpectedSlim', NaN, ...
    'SimulationSucceeded', false, 'SimulationElapsed_s', NaN, ...
    'WindowStart_s', NaN, 'WindowEnd_s', NaN, ...
    'WindowDuration_s', NaN, ...
    'U_PCC_mean_pu', NaN, 'U_PCC_median_pu', NaN, ...
    'U_PCC_std_pu', NaN, 'U_PCC_peak_to_peak_pu', NaN, ...
    'U_PCC_drift_pu', NaN, ...
    'I_GFM_mean_pu', NaN, 'I_GFM_median_pu', NaN, ...
    'I_GFM_std_pu', NaN, 'I_GFM_peak_to_peak_pu', NaN, ...
    'I_GFM_drift_pu', NaN, ...
    'Slim_mean', NaN, 'Slim_state', NaN, 'Branch', "", ...
    'TotalSlimTransitions', 0, 'WindowSlimTransitions', 0, ...
    'FiniteSignals', false, 'StateStable', false, ...
    'QuasiSteady', false, 'UbPartitionConsistent', false, ...
    'ExpectedStateMatch', false, 'I_GFM_theory_pu', NaN, ...
    'E_ref_theory_pu', NaN, 'TheoryErefSaturated', false, ...
    'CurrentError_percent', NaN, 'Valid', false, 'Notes', "");
end
