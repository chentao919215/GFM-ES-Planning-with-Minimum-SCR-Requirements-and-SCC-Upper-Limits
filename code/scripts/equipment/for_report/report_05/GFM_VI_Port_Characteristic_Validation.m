%% GFM 虚拟阻抗限流端口外特性验证
% 使用正式 Grid_Forming_Inverters.slx 和正式 GFM_Parameters.m，扫描
% 不同外部三相电源电压工况，提取故障持续阶段的准稳态 UPCC、IGFM 和
% 实际 Slim，并与 P6 严格两状态分段理论模型比较。
%
% 本脚本不修改或保存 Simulink 模型，不覆盖 ReleaseConfirmTime、Ub、
% 虚拟阻抗参数或主控制器参数。故障深度仅通过 SimulationInput 临时覆盖
% 可编程三相电源的 Amplitudes/TimeValues。

clear;
close all;
clc;

%% 路径和正式参数初始化
validationScript = mfilename('fullpath');
outputDir = fileparts(validationScript);
projectRoot = outputDir;
for pathLevel = 1:5
    projectRoot = fileparts(projectRoot);
end

modelFile = fullfile(projectRoot, 'simulink', 'models', ...
    'Grid_Forming_Inverters.slx');
parameterFile = fullfile(projectRoot, 'code', 'scripts', 'equipment', ...
    'GFM', 'GFM_Parameters.m');
referencePlotFile = fullfile(projectRoot, 'code', 'scripts', 'figure', ...
    'for_report', 'report_05', 'GFM_VI_Limited.m');

assert(isfile(modelFile), 'Formal GFM model was not found: %s', modelFile);
assert(isfile(parameterFile), ...
    'Formal GFM parameter script was not found: %s', parameterFile);
assert(isfile(referencePlotFile), ...
    'P6 reference plot script was not found: %s', referencePlotFile);

addpath(fullfile(projectRoot, 'code', 'functions', 'equipment'));
addpath(fullfile(projectRoot, 'code', 'scripts', 'equipment', 'GFM'));
run(parameterFile);

modelName = 'Grid_Forming_Inverters';
load_system(modelFile);
sourceBlock = [modelName '/Three-Phase Source'];
assert(getSimulinkBlockHandle(sourceBlock) > 0, ...
    'The programmable three-phase source was not found.');
assert(strcmp(get_param(sourceBlock, 'VariationEntity'), 'Amplitude') && ...
    strcmp(get_param(sourceBlock, 'VariationType'), ...
    'Table of time-amplitude pairs'), ...
    'The formal source is not configured for a time-amplitude table.');

%% 固定内电势理论参数（只读取正式参数体系）
E_GFM = GFM_Droop.E0_pu;
X_res = GFM_VI.X_res_device_pu;
X_VI = GFM_VI.X_vir_device_pu;
I_lim = GFM_VI.I_switch_threshold_pu;
U_boundary = GFM_VI.U_boundary_pu;
releaseConfirmTime = GFM_VI.ReleaseConfirmTime;

theory = struct();
theory.E0_pu = E_GFM;
theory.R_L2_pu = R_L2/Z_base;
theory.X_L2_pu = 2*pi*f*L2/Z_base;
theory.X_res_device_pu = X_res;
theory.X_vir_pu = X_VI;
theory.I_lim_pu = I_lim;
theory.U_boundary_pu = U_boundary;
theory.ReleaseConfirmTime_s = releaseConfirmTime;

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
    localFindCurrentThresholdVoltage(theory, 0, 1);
theory.I_pre_switch_pu = localPortCurrent(U_boundary, 0, theory);
theory.I_post_switch_pu = localPortCurrent(U_boundary, 1, theory);
theory.I_boundary_drop_pu = ...
    theory.I_pre_switch_pu-theory.I_post_switch_pu;

%% 故障深度和准稳态扫描设置
% DirectSag：从正常电压直接进入最终浅跌落，预期保持 Slim=0。
% LatchedSag：先以 0.20 p.u. 完成合法触发，再进入最终故障深度。
% 统计窗口只位于最终故障阶段，不包含触发脉冲或投切瞬间。
preFaultVoltage_pu = GFM_GridSource.CaseA.U_PCC_target_pu;
directSagTargets_pu = [0.90, 0.80, 0.70, 0.60, 0.50, 0.44, 0.41];
latchedSagTargets_pu = [0.10, 0.20, 0.30, 0.40, ...
    0.55, 0.68, 0.74, 0.75];
triggerVoltage_pu = 0.20;

faultStartTime_s = 2.0;
triggerEndTime_s = 2.30;
% 电压外环积分增益较保守；5 s 工况会把幅值纹波已经很小、但 vMid
% 仍在慢速逼近 E_ref 的点误判为最终准稳态。10 s 可将该跟踪偏差降至
% 端口理论比较所需的量级，且不修改任何控制器参数。
simulationStopTime_s = 10.0;
sourceTransitionTime_s = GFM_GridSource.TransitionTime_s;

analysisOptions = struct();
analysisOptions.WindowDurations_s = [0.80, 0.60, 0.40, 0.25];
analysisOptions.WindowEndMargin_s = 0.10;
analysisOptions.MinimumSettling_s = 2.00;
analysisOptions.SampleTime_s = 5e-4;
analysisOptions.VoltageStdAbsLimit_pu = 2e-3;
analysisOptions.VoltageStdRelLimit = 5e-3;
analysisOptions.CurrentStdAbsLimit_pu = 3e-3;
analysisOptions.CurrentStdRelLimit = 1e-2;
analysisOptions.VoltageDriftAbsLimit_pu = 3e-3;
analysisOptions.CurrentDriftAbsLimit_pu = 5e-3;

%% 构造 15 个独立工况
nDirect = numel(directSagTargets_pu);
nLatched = numel(latchedSagTargets_pu);
nCases = nDirect+nLatched;
caseTemplate = struct('CaseID', 0, 'CaseName', "", 'Protocol', "", ...
    'FinalSourceVoltage_pu', NaN, 'TriggerSourceVoltage_pu', NaN, ...
    'ExpectedSlim', NaN, 'Amplitudes_pu', [], 'TimeValues_s', [], ...
    'FinalStageStart_s', NaN);
caseSpecifications = repmat(caseTemplate, nCases, 1);

for caseIndex = 1:nDirect
    target = directSagTargets_pu(caseIndex);
    caseSpecifications(caseIndex).CaseID = caseIndex;
    caseSpecifications(caseIndex).CaseName = sprintf('Direct-%02d', caseIndex);
    caseSpecifications(caseIndex).Protocol = "DirectSag";
    caseSpecifications(caseIndex).FinalSourceVoltage_pu = target;
    caseSpecifications(caseIndex).ExpectedSlim = 0;
    caseSpecifications(caseIndex).Amplitudes_pu = ...
        [preFaultVoltage_pu, preFaultVoltage_pu, target, target];
    caseSpecifications(caseIndex).TimeValues_s = ...
        [0, faultStartTime_s, ...
        faultStartTime_s+sourceTransitionTime_s, simulationStopTime_s];
    caseSpecifications(caseIndex).FinalStageStart_s = ...
        faultStartTime_s+sourceTransitionTime_s;
end

for localIndex = 1:nLatched
    caseIndex = nDirect+localIndex;
    target = latchedSagTargets_pu(localIndex);
    caseSpecifications(caseIndex).CaseID = caseIndex;
    caseSpecifications(caseIndex).CaseName = sprintf('Latched-%02d', localIndex);
    caseSpecifications(caseIndex).Protocol = "LatchedSag";
    caseSpecifications(caseIndex).FinalSourceVoltage_pu = target;
    caseSpecifications(caseIndex).TriggerSourceVoltage_pu = triggerVoltage_pu;
    caseSpecifications(caseIndex).ExpectedSlim = 1;
    caseSpecifications(caseIndex).Amplitudes_pu = ...
        [preFaultVoltage_pu, preFaultVoltage_pu, ...
        triggerVoltage_pu, triggerVoltage_pu, target, target];
    caseSpecifications(caseIndex).TimeValues_s = ...
        [0, faultStartTime_s, ...
        faultStartTime_s+sourceTransitionTime_s, triggerEndTime_s, ...
        triggerEndTime_s+sourceTransitionTime_s, simulationStopTime_s];
    caseSpecifications(caseIndex).FinalStageStart_s = ...
        triggerEndTime_s+sourceTransitionTime_s;
end

scanConfig = struct();
scanConfig.PreFaultVoltage_pu = preFaultVoltage_pu;
scanConfig.DirectSagTargets_pu = directSagTargets_pu;
scanConfig.LatchedSagTargets_pu = latchedSagTargets_pu;
scanConfig.TriggerVoltage_pu = triggerVoltage_pu;
scanConfig.FaultStartTime_s = faultStartTime_s;
scanConfig.TriggerEndTime_s = triggerEndTime_s;
scanConfig.StopTime_s = simulationStopTime_s;
scanConfig.SourceTransitionTime_s = sourceTransitionTime_s;
scanConfig.AnalysisOptions = analysisOptions;

%% 运行所有工况并提取端口点
scanPoints = repmat(localEmptyPoint(), nCases, 1);
fprintf('\n=== GFM virtual-impedance port-characteristic scan ===\n');
fprintf('Model: %s\n', modelFile);
fprintf('Parameter file: %s\n', parameterFile);
fprintf(['E0=%.6f, nq=0, XL2=%.6f, RL2=%.6f, Xvir=%.6f, ' ...
    'Ub=%.6f, U(Ilim)=%.6f, Ilim=%.6f, ReleaseConfirmTime=%.6f s\n'], ...
    theory.E0_pu, theory.X_L2_pu, theory.R_L2_pu, ...
    theory.X_vir_pu, theory.U_boundary_pu, ...
    theory.U_current_threshold_pu, theory.I_lim_pu, releaseConfirmTime);
fprintf('Independent source-voltage cases: %d\n\n', nCases);

for caseIndex = 1:nCases
    caseSpec = caseSpecifications(caseIndex);
    fprintf('[%02d/%02d] %-10s final command %.3f p.u. ... ', ...
        caseIndex, nCases, caseSpec.Protocol, ...
        caseSpec.FinalSourceVoltage_pu);
    scanPoints(caseIndex) = localRunCase(modelName, sourceBlock, ...
        caseSpec, simulationStopTime_s, analysisOptions, theory);

    point = scanPoints(caseIndex);
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

pointsTable = struct2table(scanPoints);
validMask = pointsTable.Valid;
unlimitedMask = validMask & pointsTable.Slim_state == 0;
limitedMask = validMask & pointsTable.Slim_state == 1;
boundaryMismatchMask = validMask & ~pointsTable.UbPartitionConsistent;

unlimitedSlope_dIdU = NaN;
limitedSlope_dIdU = NaN;
if nnz(unlimitedMask) >= 2
    slopeFit = polyfit(pointsTable.U_PCC_mean_pu(unlimitedMask), ...
        pointsTable.I_GFM_mean_pu(unlimitedMask), 1);
    unlimitedSlope_dIdU = slopeFit(1);
end
if nnz(limitedMask) >= 2
    slopeFit = polyfit(pointsTable.U_PCC_mean_pu(limitedMask), ...
        pointsTable.I_GFM_mean_pu(limitedMask), 1);
    limitedSlope_dIdU = slopeFit(1);
end
boundaryCurrentDrop_pu = NaN;
if any(unlimitedMask) && any(limitedMask)
    unlimitedRows = find(unlimitedMask);
    limitedRows = find(limitedMask);
    [~, nearestUnlimited] = min(pointsTable.U_PCC_mean_pu(unlimitedRows));
    [~, nearestLimited] = max(pointsTable.U_PCC_mean_pu(limitedRows));
    boundaryCurrentDrop_pu = ...
        pointsTable.I_GFM_mean_pu(unlimitedRows(nearestUnlimited)) - ...
        pointsTable.I_GFM_mean_pu(limitedRows(nearestLimited));
end

summaryTable = table(nCases, nnz(validMask), ...
    nnz(unlimitedMask), nnz(limitedMask), nnz(boundaryMismatchMask), ...
    localMeanOrNaN(pointsTable.CurrentError_percent(unlimitedMask)), ...
    localMaxOrNaN(pointsTable.CurrentError_percent(unlimitedMask)), ...
    localMeanOrNaN(pointsTable.CurrentError_percent(limitedMask)), ...
    localMaxOrNaN(pointsTable.CurrentError_percent(limitedMask)), ...
    localMaxOrNaN(pointsTable.CurrentError_percent(validMask)), ...
    unlimitedSlope_dIdU, limitedSlope_dIdU, boundaryCurrentDrop_pu, ...
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

%% P6 理论曲线 + Simulink 散点
% 图窗、坐标范围、网格、曲线及文字风格沿用 GFM_VI_Limited.m。
U_PCC_min = 0.00;
U_PCC_max = 1.00;
num_points = 501;
figure_width_cm = 18.0;
figure_height_cm = 5.6;
axis_font_size = 11;
label_font_size = 14;

U_current_threshold = theory.U_current_threshold_pu;
I_pre_switch = theory.I_pre_switch_pu;
I_post_switch = theory.I_post_switch_pu;
U_PCC_limited = linspace(U_PCC_min, U_boundary, num_points);
I_GFM_limited = localPortCurrent(U_PCC_limited, 1, theory);
U_PCC_unlimited = linspace(U_boundary, U_PCC_max, num_points);
I_GFM_unlimited = localPortCurrent(U_PCC_unlimited, 0, theory);
I_axis_max = 5/3*I_lim;

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

figure_handle = figure('Color', 'w', 'Units', 'centimeters', ...
    'Position', [2.0, 2.0, figure_width_cm, figure_height_cm], ...
    'PaperPositionMode', 'auto');
axes_handle = axes('Parent', figure_handle, ...
    'Color', [0.98, 0.985, 0.99], ...
    'FontName', 'Times New Roman', 'FontSize', axis_font_size, ...
    'LineWidth', 1.1, 'TickDir', 'out', 'Box', 'on');
hold(axes_handle, 'on');
grid(axes_handle, 'on');
axes_handle.XMinorGrid = 'on';
axes_handle.YMinorGrid = 'on';
axes_handle.GridLineStyle = '--';
axes_handle.MinorGridLineStyle = ':';
axes_handle.GridColor = [0.72, 0.82, 0.90];
axes_handle.MinorGridColor = [0.80, 0.87, 0.93];
axes_handle.GridAlpha = 0.70;
axes_handle.MinorGridAlpha = 0.65;

blue_color = [0.0000, 0.4470, 0.7410];
red_color = [0.85, 0.15, 0.15];

plot(axes_handle, U_PCC_unlimited, I_GFM_unlimited, '-', ...
    'Color', blue_color, 'LineWidth', 2.2, ...
    'HandleVisibility', 'off');
plot(axes_handle, U_PCC_limited, I_GFM_limited, '-', ...
    'Color', blue_color, 'LineWidth', 2.2, ...
    'HandleVisibility', 'off');
plot(axes_handle, [U_boundary, U_boundary], ...
    [I_post_switch, I_pre_switch], '-', ...
    'Color', blue_color, 'LineWidth', 2.2, ...
    'HandleVisibility', 'off');

xlim(axes_handle, [U_PCC_min, U_PCC_max]);
ylim(axes_handle, [0, I_axis_max]);
xticks(axes_handle, linspace(U_PCC_min, U_PCC_max, 5));
yticks(axes_handle, 0:0.5:ceil(I_axis_max/0.5)*0.5);

plot(axes_handle, [U_PCC_min, U_PCC_max], [I_lim, I_lim], '--', ...
    'Color', red_color, 'LineWidth', 1.5, 'HandleVisibility', 'off');
plot(axes_handle, [U_boundary, U_boundary], [0, I_axis_max], '--', ...
    'Color', red_color, 'LineWidth', 1.5, 'HandleVisibility', 'off');
plot(axes_handle, U_current_threshold, I_lim, 'o', ...
    'MarkerSize', 7, 'MarkerFaceColor', 'w', ...
    'MarkerEdgeColor', red_color, 'LineWidth', 1.2, ...
    'HandleVisibility', 'off');
plot(axes_handle, U_boundary, I_pre_switch, 'o', ...
    'MarkerSize', 7, 'MarkerFaceColor', red_color, ...
    'MarkerEdgeColor', red_color, 'LineWidth', 1.0, ...
    'HandleVisibility', 'off');

validUPCC = pointsTable.U_PCC_mean_pu(validMask);
validIGFM = pointsTable.I_GFM_mean_pu(validMask);
scatter_handle = plot(axes_handle, validUPCC, validIGFM, 'o', ...
    'LineStyle', 'none', 'MarkerSize', 6.5, ...
    'MarkerFaceColor', red_color, 'MarkerEdgeColor', red_color, ...
    'LineWidth', 0.8, 'DisplayName', '\fontname{Times New Roman}Simulink\fontname{font_name}仿真结果');
legend(axes_handle, scatter_handle, 'Location', 'northwest', ...
    'Box', 'off', 'FontName', font_name, 'FontSize', 10);

xlabel(axes_handle, '{\itU}^{PCC}/{\itU}^N', ...
    'FontName', 'Times New Roman', 'FontSize', label_font_size, ...
    'Color', 'k');
ylabel(axes_handle, '{\itI}^{GFM}/{\itI}^N', ...
    'FontName', 'Times New Roman', 'FontSize', label_font_size, ...
    'Color', 'k');

text(axes_handle, U_boundary+0.43*(U_PCC_max-U_boundary), ...
    0.32*I_lim, '未限流区', 'Color', blue_color, ...
    'FontName', font_name, 'FontSize', 12, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
text(axes_handle, U_PCC_min+0.50*(U_boundary-U_PCC_min), ...
    0.28*I_lim, '虚拟阻抗限流区', 'Color', [0.25, 0.25, 0.25], ...
    'FontName', font_name, 'FontSize', 11, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
text(axes_handle, U_PCC_min+0.50*(U_boundary-U_PCC_min), ...
    0.80*I_lim, '虚拟阻抗投入后斜率减小', ...
    'Color', blue_color, 'FontName', font_name, 'FontSize', 10, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
text(axes_handle, 0.3*(U_PCC_max-U_PCC_min), I_lim, ...
    '限流触发阈值\fontname{Times New Roman}{\itI}^{lim}', ...
    'Color', red_color, 'FontName', font_name, 'FontSize', 11, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');
text(axes_handle, U_boundary-0.22*(U_PCC_max-U_PCC_min), ...
    0.80*I_axis_max, ...
    '状态电压边界\fontname{Times New Roman}{\itU}_b', ...
    'Color', red_color, 'FontName', font_name, 'FontSize', 11, ...
    'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom');
text(axes_handle, U_current_threshold+0.012*(U_PCC_max-U_PCC_min), ...
    I_lim, '达到电流阈值', 'Color', red_color, ...
    'FontName', font_name, 'FontSize', 10, ...
    'HorizontalAlignment', 'left', 'VerticalAlignment', 'top');
text(axes_handle, U_boundary-0.012*(U_PCC_max-U_PCC_min), ...
    I_pre_switch, '状态切换点', 'Color', red_color, ...
    'FontName', font_name, 'FontSize', 10, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');

%% 保存图和结构化结果
pngFile = fullfile(outputDir, ...
    'GFM_VI_Port_Characteristic_Validation.png');
resultFile = fullfile(outputDir, ...
    'GFM_VI_Port_Characteristic_Validation_Result.mat');
pointsCsvFile = fullfile(outputDir, ...
    'GFM_VI_Port_Characteristic_Validation_Points.csv');
summaryCsvFile = fullfile(outputDir, ...
    'GFM_VI_Port_Characteristic_Validation_Summary.csv');

exportgraphics(figure_handle, pngFile, ...
    'Resolution', 300, 'BackgroundColor', 'white');
writetable(pointsTable, pointsCsvFile, 'Encoding', 'UTF-8');
writetable(summaryTable, summaryCsvFile, 'Encoding', 'UTF-8');

ValidationResult = struct();
ValidationResult.GeneratedAt = datetime('now', ...
    'TimeZone', 'Asia/Shanghai');
ValidationResult.ModelFile = modelFile;
ValidationResult.ParameterFile = parameterFile;
ValidationResult.ReferencePlotFile = referencePlotFile;
ValidationResult.SourceBlock = sourceBlock;
ValidationResult.Theory = theory;
ValidationResult.ScanConfig = scanConfig;
ValidationResult.CaseSpecifications = caseSpecifications;
ValidationResult.Points = pointsTable;
ValidationResult.Summary = summaryTable;
ValidationResult.OutputFiles = struct('PNG', pngFile, ...
    'PointsCSV', pointsCsvFile, 'SummaryCSV', summaryCsvFile);
save(resultFile, 'ValidationResult', '-v7.3');

fprintf('\n=== Port-characteristic validation summary ===\n');
disp(summaryTable);
fprintf('PNG: %s\n', pngFile);
fprintf('MAT: %s\n', resultFile);
fprintf('Points CSV: %s\n', pointsCsvFile);
fprintf('Summary CSV: %s\n', summaryCsvFile);

close_system(modelName, 0);

%% Local functions
function point = localRunCase(modelName, sourceBlock, caseSpec, ...
        stopTime_s, options, theory)
    point = localEmptyPoint();
    point.CaseID = caseSpec.CaseID;
    point.CaseName = string(caseSpec.CaseName);
    point.Protocol = string(caseSpec.Protocol);
    point.FinalSourceVoltage_pu = caseSpec.FinalSourceVoltage_pu;
    point.TriggerSourceVoltage_pu = caseSpec.TriggerSourceVoltage_pu;
    point.ExpectedSlim = caseSpec.ExpectedSlim;

    try
        simulationInput = Simulink.SimulationInput(modelName);
        simulationInput = simulationInput.setBlockParameter( ...
            sourceBlock, 'Amplitudes', ...
            mat2str(caseSpec.Amplitudes_pu, 17));
        simulationInput = simulationInput.setBlockParameter( ...
            sourceBlock, 'TimeValues', ...
            mat2str(caseSpec.TimeValues_s, 17));
        simulationInput = simulationInput.setModelParameter( ...
            'StopTime', num2str(stopTime_s, 17), ...
            'ReturnWorkspaceOutputs', 'on');

        elapsedTimer = tic;
        simulationOutput = sim(simulationInput);
        point.SimulationElapsed_s = toc(elapsedTimer);
        point.SimulationSucceeded = true;

        logs = simulationOutput.logsout;
        assert(isa(logs, 'Simulink.SimulationData.Dataset'), ...
            'logsout is not a Dataset.');
        signalNames = logs.getElementNames;
        required = {'U_PCC_pu', 'I_GFM_mag_pu', 'Slim'};
        missing = required(~ismember(required, signalNames));
        assert(isempty(missing), ...
            'Missing logged signals: %s', strjoin(missing, ', '));

        voltageSignal = logs.getElement('U_PCC_pu').Values;
        currentSignal = logs.getElement('I_GFM_mag_pu').Values;
        slimSignal = logs.getElement('Slim').Values;
        [~, slimData] = localSignalData(slimSignal, 'Slim');
        point.TotalSlimTransitions = ...
            nnz(diff(double(slimData >= 0.5)) ~= 0);

        window = localSelectWindow(voltageSignal, currentSignal, ...
            slimSignal, caseSpec.FinalStageStart_s, stopTime_s, options);
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
                point.TheoryErefSaturated] = localPortCurrent( ...
                point.U_PCC_mean_pu, 0, theory);
            point.UbPartitionConsistent = ...
                point.U_PCC_mean_pu >= theory.U_boundary_pu;
        elseif point.Slim_state == 1
            point.Branch = "Limited";
            [point.I_GFM_theory_pu, point.E_ref_theory_pu, ...
                point.TheoryErefSaturated] = localPortCurrent( ...
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
            point.Slim_state == caseSpec.ExpectedSlim;
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

function [current, Eref, saturated] = localPortCurrent(voltage, slim, theory)
    originalSize = size(voltage);
    voltage = voltage(:);
    if isscalar(slim)
        slim = repmat(slim, size(voltage));
    else
        slim = slim(:);
    end
    assert(numel(slim) == numel(voltage), ...
        'Slim and voltage sizes differ.');

    X = theory.X_L2_pu+slim*theory.X_vir_pu;
    impedanceSquared = theory.R_L2_pu^2+X.^2;
    discriminant = (voltage.*X).^2 ...
        -impedanceSquared.*(voltage.^2-theory.E0_pu^2);
    assert(all(discriminant >= -1e-12), ...
        'Fixed-E port equation has no real current solution.');
    current = (-voltage.*X+sqrt(max(discriminant, 0))) ...
        ./impedanceSquared;
    current = reshape(max(current, 0), originalSize);
    Eref = repmat(theory.E0_pu, originalSize);
    saturated = false(originalSize);
end

function voltage = localFindCurrentThresholdVoltage(theory, Umin, Umax)
    radicand = theory.E0_pu^2 ...
        -(theory.R_L2_pu*theory.I_lim_pu)^2;
    assert(radicand >= 0, ...
        'I_lim is outside the feasible fixed-E port equation.');
    voltage = sqrt(radicand) ...
        -theory.X_L2_pu*theory.I_lim_pu;
    assert(voltage >= Umin && voltage <= Umax, ...
        'No I_GFM=I_lim crossing exists in the voltage scan range.');
end
function window = localSelectWindow(voltageSignal, currentSignal, ...
        slimSignal, finalStageStart_s, stopTime_s, options)
    [voltageTime, voltageData] = ...
        localSignalData(voltageSignal, 'U_PCC_pu');
    [currentTime, currentData] = ...
        localSignalData(currentSignal, 'I_GFM_mag_pu');
    [slimTime, slimData] = localSignalData(slimSignal, 'Slim');

    windowEnd = stopTime_s-options.WindowEndMargin_s;
    earliestStart = finalStageStart_s+options.MinimumSettling_s;
    selected = struct();

    for durationIndex = 1:numel(options.WindowDurations_s)
        windowStart = max(earliestStart, ...
            windowEnd-options.WindowDurations_s(durationIndex));
        if windowEnd-windowStart < 0.20
            continue;
        end
        candidate = localWindowMetrics(voltageTime, voltageData, ...
            currentTime, currentData, slimTime, slimData, ...
            windowStart, windowEnd, options);
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

function metrics = localWindowMetrics(voltageTime, voltageData, ...
        currentTime, currentData, slimTime, slimData, ...
        windowStart, windowEnd, options)
    queryTime = (windowStart:options.SampleTime_s:windowEnd).';
    if queryTime(end) < windowEnd
        queryTime(end+1, 1) = windowEnd;
    end

    voltage = interp1(voltageTime, voltageData, ...
        queryTime, 'linear', 'extrap');
    current = interp1(currentTime, currentData, ...
        queryTime, 'linear', 'extrap');
    slim = interp1(slimTime, slimData, ...
        queryTime, 'previous', 'extrap');
    slim = double(slim >= 0.5);

    finiteSignals = all(isfinite(voltage)) && ...
        all(isfinite(current)) && all(isfinite(slim));
    voltageMean = mean(voltage);
    currentMean = mean(current);
    voltageStd = std(voltage);
    currentStd = std(current);
    sectionLength = max(2, floor(0.20*numel(queryTime)));
    voltageDrift = abs(mean(voltage(end-sectionLength+1:end)) - ...
        mean(voltage(1:sectionLength)));
    currentDrift = abs(mean(current(end-sectionLength+1:end)) - ...
        mean(current(1:sectionLength)));

    voltageStdLimit = max(options.VoltageStdAbsLimit_pu, ...
        options.VoltageStdRelLimit*max(abs(voltageMean), 1e-6));
    currentStdLimit = max(options.CurrentStdAbsLimit_pu, ...
        options.CurrentStdRelLimit*max(abs(currentMean), 1e-6));
    quasiSteady = voltageStd <= voltageStdLimit && ...
        currentStd <= currentStdLimit && ...
        voltageDrift <= options.VoltageDriftAbsLimit_pu && ...
        currentDrift <= options.CurrentDriftAbsLimit_pu;
    slimTransitions = nnz(diff(slim) ~= 0);

    metrics = struct();
    metrics.StartTime_s = windowStart;
    metrics.EndTime_s = windowEnd;
    metrics.VoltageMean_pu = voltageMean;
    metrics.VoltageMedian_pu = median(voltage);
    metrics.VoltageStd_pu = voltageStd;
    metrics.VoltagePeakToPeak_pu = max(voltage)-min(voltage);
    metrics.VoltageDrift_pu = voltageDrift;
    metrics.CurrentMean_pu = currentMean;
    metrics.CurrentMedian_pu = median(current);
    metrics.CurrentStd_pu = currentStd;
    metrics.CurrentPeakToPeak_pu = max(current)-min(current);
    metrics.CurrentDrift_pu = currentDrift;
    metrics.SlimMean = mean(slim);
    metrics.SlimState = round(median(slim));
    metrics.SlimTransitions = slimTransitions;
    metrics.StateStable = slimTransitions == 0;
    metrics.QuasiSteady = quasiSteady;
    metrics.FiniteSignals = finiteSignals;
end

function [time, data] = localSignalData(signal, signalName)
    assert(isa(signal, 'timeseries'), ...
        '%s must be a timeseries.', signalName);
    time = double(signal.Time(:));
    data = double(squeeze(signal.Data));
    data = data(:);
    assert(numel(data) == numel(time), ...
        '%s time and data lengths differ.', signalName);
    [time, uniqueIndex] = unique(time, 'last');
    data = data(uniqueIndex);
    assert(numel(time) >= 2, '%s has insufficient data.', signalName);
end

function value = localMeanOrNaN(values)
    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
    else
        value = mean(values);
    end
end

function value = localMaxOrNaN(values)
    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
    else
        value = max(values);
    end
end

function point = localEmptyPoint()
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
