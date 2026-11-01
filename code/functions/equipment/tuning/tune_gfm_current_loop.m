function [CL, Diagnostics] = tune_gfm_current_loop(LCL, Design)
%% 给定LCL参数、Kp和目标交越频率，计算GFM逆变器侧i1电流环Ki并校核。
% LCL必填字段（SI）：L1/R_L1/Cf/R_C/L2/R_L2/f。
% Design必填字段：TargetBandwidthHz、Kp、MinimumPhaseMarginDeg、
% VoltageFeedforwardMode、UseDQDecouplingInTuning、ShowRGAPlots、
% ShowValidationPlots、Verbose。无默认物理参数、目标或控制配置。
% 外部拓扑保持LCL；中点电压前馈下，i1标称对象化简为L1/R_L1支路。
% 输出CL供电压环直接使用；不读写基础工作区。
arguments
    LCL (1, 1) struct
    Design (1, 1) struct
end
validate_inputs(LCL, Design);
w0 = 2*pi*LCL.f;
wc = 2*pi*Design.TargetBandwidthHz;

%% 1. 按前馈、dq解耦配置建立2×2 i1对象。
switch Design.VoltageFeedforwardMode
    case 'midpoint_voltage'
        R_i1 = LCL.R_L1;
    case 'capacitor_voltage'
        R_i1 = LCL.R_L1+LCL.R_C;
    otherwise
        error('EquipmentTuning:InvalidFeedforward', '未知电压前馈方式。');
end
Cross_Coupling = (1-double(Design.UseDQDecouplingInTuning))*w0;
A = [-R_i1/LCL.L1, Cross_Coupling; -Cross_Coupling, -R_i1/LCL.L1];
G = ss(A, eye(2)/LCL.L1, eye(2), zeros(2));
G.InputName = {'v_ctrl_d', 'v_ctrl_q'};
G.OutputName = {'i1_d', 'i1_q'};

%% 2. 固定外部Kp，由目标频率处的单位开环幅值计算Ki。
G_wc = squeeze(freqresp(G, wc));
assert(rcond(G_wc) >= 1e-12, 'EquipmentTuning:SingularPlant', ...
    '目标频率处的GFM电流对象不可逆。');
rga = G_wc .* transpose(G_wc\eye(2));
[plantMagnitude, ~] = bode(G(1, 1), wc);
Controller_Magnitude = 1/squeeze(plantMagnitude);
assert(isfinite(Controller_Magnitude) && Design.Kp < Controller_Magnitude, ...
    'EquipmentTuning:InfeasibleKp', ...
    '给定目标频率下，GFM电流环Kp必须小于%.12g V/A。', Controller_Magnitude);
Ki = wc*sqrt(Controller_Magnitude^2-Design.Kp^2);
Cpi = pid(Design.Kp, Ki);

%% 3. 校核标称SISO裕度和2×2 dq闭环。
K = append(Cpi, Cpi);
T = feedback(G*K, eye(2));
T.InputName = {'i1_d_ref', 'i1_q_ref'};
T.OutputName = {'i1_d', 'i1_q'};
[gm, pm, wcg, wcp] = margin(Cpi*G(1, 1));
assert(isstable(T), 'EquipmentTuning:UnstableCurrentLoop', ...
    '给定设计未通过GFM电流环dq闭环稳定性校核。');
assert(isfinite(pm) && pm >= Design.MinimumPhaseMarginDeg, ...
    'EquipmentTuning:InsufficientPhaseMargin', ...
    'GFM电流环SISO相位裕度%.6g度低于要求%.6g度。', pm, Design.MinimumPhaseMarginDeg);
T_wc = squeeze(freqresp(T, wc));
coupling = max(abs([T_wc(1, 2), T_wc(2, 1)])) ...
    /max(abs([T_wc(1, 1), T_wc(2, 2)]));
CL = struct('Kp', Design.Kp, 'Ki', Ki, ...
    'TargetBandwidthHz', Design.TargetBandwidthHz, ...
    'VoltageFeedforwardMode', Design.VoltageFeedforwardMode, ...
    'UseDQDecouplingInTuning', Design.UseDQDecouplingInTuning, ...
    'R_equivalent', R_i1, 'RGAatTarget', rga, ...
    'ClosedLoopCouplingRatio', coupling, 'PhaseMarginDeg', pm, ...
    'IsStable', true, 'LCL', LCL);
Diagnostics = struct('LCL', LCL, 'Design', Design, 'Plant', G, ...
    'ClosedLoop', T, 'ClosedLoopPoles', pole(T), ...
    'GainMargin', gm, 'PhaseMarginDeg', pm, ...
    'GainMarginFrequencyRad_s', wcg, 'CrossoverHz', wcp/(2*pi), ...
    'KpUpperBound', Controller_Magnitude, 'RGAatTarget', rga);
if Design.Verbose
    fprintf('GFM i1: target %.6g Hz, Kp %.12g, Ki %.12g, PM %.6g deg, stable=1\n', ...
        Design.TargetBandwidthHz, CL.Kp, CL.Ki, pm);
end

%% 4. 按外部开关显示原有RGA及开闭环图。
if Design.ShowRGAPlots
    frequencies = logspace(0, 4, 2000);
    RGA_Values = NaN(2, 2, numel(frequencies));
    response = freqresp(G, 2*pi*frequencies);
    for k = 1:numel(frequencies)
        Gjw = response(:, :, k);
        if rcond(Gjw) >= 1e-12
            RGA_Values(:, :, k) = Gjw .* transpose(Gjw\eye(2));
        end
    end
    figure;
    semilogx(frequencies, squeeze(abs(RGA_Values(1, 1, :))), 'LineWidth', 1.2); hold on;
    semilogx(frequencies, squeeze(abs(RGA_Values(1, 2, :))), 'LineWidth', 1.2);
    semilogx(frequencies, squeeze(abs(RGA_Values(2, 1, :))), 'LineWidth', 1.2);
    semilogx(frequencies, squeeze(abs(RGA_Values(2, 2, :))), 'LineWidth', 1.2);
    xline(Design.TargetBandwidthHz, '--', 'Target bandwidth'); grid on;
    xlabel('Frequency [Hz]'); ylabel('RGA magnitude');
    legend('|lambda_{dd}|', '|lambda_{dq}|', '|lambda_{qd}|', '|lambda_{qq}|', 'Location', 'best');
    title('GFM current-loop RGA');
end
if Design.ShowValidationPlots
    figure; margin(Cpi*G(1, 1)); grid on; title('GFM current-loop open-loop margins');
    figure;
    bodemag(T(1, 1), T(1, 2), T(2, 1), T(2, 2), 2*pi*logspace(0, 4, 2000)); grid on;
    legend('i1_d/i1_d_ref', 'i1_d/i1_q_ref', 'i1_q/i1_d_ref', 'i1_q/i1_q_ref', 'Location', 'best');
    title('GFM current-loop closed-loop response');
end
end

function validate_inputs(LCL, Design)
%% 校验控制环整定所需的物理参数、设计输入及稳定性前提。
Required_LCL = {'L1', 'R_L1', 'Cf', 'R_C', 'L2', 'R_L2', 'f'};
Required_Design = {'TargetBandwidthHz', 'Kp', 'MinimumPhaseMarginDeg', ...
    'VoltageFeedforwardMode', 'UseDQDecouplingInTuning', ...
    'ShowRGAPlots', 'ShowValidationPlots', 'Verbose'};
assert(all(isfield(LCL, Required_LCL)) && all(isfield(Design, Required_Design)), ...
    'EquipmentTuning:MissingInput', 'LCL或Design缺少必填字段，整定函数不补入默认值。');
for k = 1:numel(Required_LCL)
    name = Required_LCL{k};
    validateattributes(LCL.(name), {'numeric'}, {'real', 'finite', 'scalar', 'nonnegative'}, mfilename, ...
        ['LCL.' name]);
    if ~startsWith(name, 'R_')
        assert(LCL.(name) > 0, 'EquipmentTuning:InvalidLCL', '%s必须为正值。', name);
    end
end
validateattributes(Design.TargetBandwidthHz, {'numeric'}, {'real', 'finite', 'scalar', 'positive'});
validateattributes(Design.Kp, {'numeric'}, {'real', 'finite', 'scalar', 'positive'});
validateattributes(Design.MinimumPhaseMarginDeg, {'numeric'}, {'real', 'finite', 'scalar', 'nonnegative', ...
    '<', 180});
for name = {'UseDQDecouplingInTuning', 'ShowRGAPlots', 'ShowValidationPlots', 'Verbose'}
    validateattributes(Design.(name{1}), {'logical'}, {'scalar'});
end
end
