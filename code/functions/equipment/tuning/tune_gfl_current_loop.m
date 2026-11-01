function [CL, Diagnostics] = tune_gfl_current_loop(LCL, Design)
%% 给定LCL参数、Kp和目标交越频率，计算GFL网侧i2电流环Ki并校核。
% LCL必填字段（SI）：L1/R_L1/Cf/R_C/L2/R_L2/f。
% Design必填字段：TargetBandwidthHz、Kp、MinimumPhaseMarginDeg、
% ShowRGAPlots、ShowValidationPlots、Verbose。所有字段均由调用方提供。
% 对象保留LCL内部损耗及dq耦合，不包含外部电网阻抗和PWM延时。
% 不读写基础工作区；不通过校核时不返回可供模型采用的PI。
arguments
    LCL (1, 1) struct
    Design (1, 1) struct
end
validate_inputs(LCL, Design);
L1 = LCL.L1; R_L1 = LCL.R_L1;
L2 = LCL.L2; R_L2 = LCL.R_L2;
Cf = LCL.Cf; R_C = LCL.R_C;
w0 = 2*pi*LCL.f;
wc = 2*pi*Design.TargetBandwidthHz;

%% 1. 建立LCL的2×2 dq对象，状态为[i1_d i1_q vC_d vC_q i2_d i2_q]。
A = [-(R_L1+R_C)/L1, w0, -1/L1, 0, R_C/L1, 0;
    -w0, -(R_L1+R_C)/L1, 0, -1/L1, 0, R_C/L1;
    1/Cf, 0, 0, w0, -1/Cf, 0;
    0, 1/Cf, -w0, 0, 0, -1/Cf;
    R_C/L2, 0, 1/L2, 0, -(R_L2+R_C)/L2, w0;
    0, R_C/L2, 0, 1/L2, -w0, -(R_L2+R_C)/L2];
B = [1/L1, 0; 0, 1/L1; zeros(4, 2)];
C = [0, 0, 0, 0, 1, 0; 0, 0, 0, 0, 0, 1];
G = ss(A, B, C, zeros(2));
G.InputName = {'v_ctrl_d', 'v_ctrl_q'};
G.OutputName = {'i2_d', 'i2_q'};
G.StateName = {'i1_d', 'i1_q', 'vC_d', 'vC_q', 'i2_d', 'i2_q'};

%% 2. 用d轴标称通道的单位开环幅值条件计算Ki。
G_wc = squeeze(freqresp(G, wc));
assert(rcond(G_wc) >= 1e-12, 'EquipmentTuning:SingularPlant', ...
    '目标频率处的GFL电流对象不可逆。');
rga = G_wc .* transpose(G_wc\eye(2));
[plantMagnitude, ~] = bode(G(1, 1), wc);
Controller_Magnitude = 1/squeeze(plantMagnitude);
assert(isfinite(Controller_Magnitude) && Design.Kp < Controller_Magnitude, ...
    'EquipmentTuning:InfeasibleKp', ...
    '给定目标频率下，GFL电流环Kp必须小于%.12g V/A。', Controller_Magnitude);
Ki = wc*sqrt(Controller_Magnitude^2-Design.Kp^2);
Cpi = pid(Design.Kp, Ki);

%% 3. 校核SISO裕度及2×2 dq闭环，失败时停止采用。
K = append(Cpi, Cpi);
T = feedback(G*K, eye(2));
T.InputName = {'i2_d_ref', 'i2_q_ref'};
T.OutputName = {'i2_d', 'i2_q'};
[gm, pm, wcg, wcp] = margin(Cpi*G(1, 1));
assert(isstable(T), 'EquipmentTuning:UnstableCurrentLoop', ...
    '给定设计未通过GFL电流环dq闭环稳定性校核。');
assert(isfinite(pm) && pm >= Design.MinimumPhaseMarginDeg, ...
    'EquipmentTuning:InsufficientPhaseMargin', ...
    'GFL电流环SISO相位裕度%.6g度低于要求%.6g度。', pm, Design.MinimumPhaseMarginDeg);
T_wc = squeeze(freqresp(T, wc));
coupling = max(abs([T_wc(1, 2), T_wc(2, 1)])) ...
    /max(abs([T_wc(1, 1), T_wc(2, 2)]));
CL = struct('Kp', Design.Kp, 'Ki', Ki, ...
    'TargetBandwidthHz', Design.TargetBandwidthHz, 'PhaseMarginDeg', pm, ...
    'RGAatTarget', rga, 'ClosedLoopCouplingRatio', coupling, 'IsStable', true);
Diagnostics = struct('LCL', LCL, 'Design', Design, 'Plant', G, ...
    'ClosedLoop', T, 'ClosedLoopPoles', pole(T), ...
    'GainMargin', gm, 'PhaseMarginDeg', pm, ...
    'GainMarginFrequencyRad_s', wcg, 'CrossoverHz', wcp/(2*pi), ...
    'KpUpperBound', Controller_Magnitude, 'RGAatTarget', rga);
if Design.Verbose
    fprintf('GFL i2: target %.6g Hz, Kp %.12g, Ki %.12g, PM %.6g deg, stable=1\n', ...
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
    xlabel('Frequency (Hz)'); ylabel('RGA magnitude');
    legend('|lambda_{dd}|', '|lambda_{dq}|', '|lambda_{qd}|', '|lambda_{qq}|', 'Location', 'best');
    title('RGA magnitude versus frequency');
end
if Design.ShowValidationPlots
    figure; margin(Cpi*G(1, 1)); grid on; title('d-axis open-loop margins');
    figure;
    bodemag(T(1, 1), T(1, 2), T(2, 1), T(2, 2), 2*pi*logspace(0, 4, 2000)); grid on;
    legend('i_{2,d}/i_{2,d}^{ref}', 'i_{2,d}/i_{2,q}^{ref}', ...
        'i_{2,q}/i_{2,d}^{ref}', 'i_{2,q}/i_{2,q}^{ref}', 'Location', 'best');
    title('dq closed-loop response');
end
end

function validate_inputs(LCL, Design)
%% 校验控制环整定所需的物理参数、设计输入及稳定性前提。
Required_LCL = {'L1', 'R_L1', 'Cf', 'R_C', 'L2', 'R_L2', 'f'};
Required_Design = {'TargetBandwidthHz', 'Kp', 'MinimumPhaseMarginDeg', ...
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
for name = {'ShowRGAPlots', 'ShowValidationPlots', 'Verbose'}
    validateattributes(Design.(name{1}), {'logical'}, {'scalar'});
end
end
