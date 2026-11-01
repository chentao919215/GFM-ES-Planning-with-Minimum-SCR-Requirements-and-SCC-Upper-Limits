function [VL, Diagnostics] = tune_gfm_voltage_loop(LCL, CurrentLoop, Design)
%% 给定Kp和目标交越频率，计算GFM中点电压环Ki并校核实际LCL闭环。
% LCL必填字段（SI）：L1/R_L1/Cf/R_C/L2/R_L2/f，须与仿真实际参数一致。
% CurrentLoop为tune_gfm_current_loop针对同一LCL返回的结果，不在此重新整定。
% Design必填字段：TargetBandwidthHz、Kp、MinimumPhaseMarginDeg、
% UseI2Feedforward、UseDQDecouplingInTuning、ShowRGAPlots、ShowValidationPlots、Verbose。
% Ki按标称电压通道单位开环幅值计算，再检查2×2电压闭环及十阶LCL模型。
% 十阶模型不包含外部电网、下垂、虚拟阻抗投切和PWM/测量延迟的全部动态。
% 无默认参数、固定Ki或失败回退；不通过校核时不发布可采用的PI。
arguments
    LCL (1, 1) struct
    CurrentLoop (1, 1) struct
    Design (1, 1) struct
end
validate_inputs(LCL, CurrentLoop, Design);
w0 = 2*pi*LCL.f;
wv = 2*pi*Design.TargetBandwidthHz;

%% 1. 使用已整定电流PI闭合i1内环。
switch CurrentLoop.VoltageFeedforwardMode
    case 'midpoint_voltage'
        R_i1 = LCL.R_L1;
    case 'capacitor_voltage'
        R_i1 = LCL.R_L1+LCL.R_C;
    otherwise
        error('EquipmentTuning:InvalidFeedforward', '未知电流环电压前馈方式。');
end
if CurrentLoop.UseDQDecouplingInTuning
    A_i1 = [-R_i1/LCL.L1, 0; 0, -R_i1/LCL.L1];
else
    A_i1 = [-R_i1/LCL.L1, w0; -w0, -R_i1/LCL.L1];
end
G_i1 = ss(A_i1, eye(2)/LCL.L1, eye(2), zeros(2));
G_i1.InputName = {'v_ctrl_d', 'v_ctrl_q'};
G_i1.OutputName = {'i1_d', 'i1_q'};
Cpi_i = pid(CurrentLoop.Kp, CurrentLoop.Ki);
K_i = append(Cpi_i, Cpi_i);
K_i.InputName = {'e_i1_d', 'e_i1_q'};
K_i.OutputName = {'v_ctrl_d', 'v_ctrl_q'};
T_i1 = feedback(G_i1*K_i, eye(2));
T_i1.InputName = {'i1_d_ref', 'i1_q_ref'};
T_i1.OutputName = {'i1_d', 'i1_q'};
assert(isstable(T_i1), 'EquipmentTuning:UnstableCurrentLoop', ...
    '传入的电流PI未通过当前对象的dq闭环校核。');

%% 2. 建立标称中点电压对象；i2作为独立扰动，L2用于完整闭环校核。
A_cap_raw = [0, w0; -w0, 0];
if Design.UseDQDecouplingInTuning
    A_cap = zeros(2);
else
    A_cap = A_cap_raw;
end
B_cap = eye(2)/LCL.Cf;
G_cap = ss(A_cap, B_cap, eye(2), zeros(2));
G_cap.InputName = {'delta_i1_d', 'delta_i1_q'};
G_cap.OutputName = {'vC_d', 'vC_q'};
G_RC = ss([], [], [], LCL.R_C*eye(2));
G_mid = minreal((G_cap+G_RC)*T_i1);
G_mid.InputName = {'i1_d_ref_corr', 'i1_q_ref_corr'};
G_mid.OutputName = {'vMid_d', 'vMid_q'};
G_wv = squeeze(freqresp(G_mid, wv));
assert(all(isfinite(G_wv), 'all') && rcond(G_wv) >= 1e-12, ...
    'EquipmentTuning:SingularPlant', '目标频率处的电压对象不可逆。');
rga = G_wv .* transpose(G_wv\eye(2));

%% 3. 固定外部Kp，由单位开环幅值计算Ki；没有固定增益覆盖分支。
[plantMagnitude, ~] = bode(G_mid(1, 1), wv);
Controller_Magnitude = 1/squeeze(plantMagnitude);
assert(isfinite(Controller_Magnitude) && Design.Kp < Controller_Magnitude, ...
    'EquipmentTuning:InfeasibleKp', ...
    '给定目标频率下，GFM电压环Kp必须小于%.12g A/V。', Controller_Magnitude);
Ki = wv*sqrt(Controller_Magnitude^2-Design.Kp^2);
Cpi_v = pid(Design.Kp, Ki);

%% 4. 用同一组PI及实际LCL参数校核十阶完整闭环。
A_full = full_lcl_closed_loop(LCL, CurrentLoop, Design, Ki);
Full_Poles = eig(A_full);
Max_Pole_Real = max(real(Full_Poles));
assert(Max_Pole_Real < 0, 'EquipmentTuning:UnstableFullLCL', ...
    ['GFM电压PI未通过实际LCL校核：Kp=%.12g，Ki=%.12g，' ...
    '最大极点实部=%.12g。请调整外部Kp或目标频率。'], Design.Kp, Ki, Max_Pole_Real);
K_v = append(Cpi_v, Cpi_v);
K_v.InputName = {'e_vMid_d', 'e_vMid_q'};
K_v.OutputName = {'i1_d_ref_corr', 'i1_q_ref_corr'};
T_mid = feedback(G_mid*K_v, eye(2));
T_mid.InputName = {'vMid_d_ref', 'vMid_q_ref'};
T_mid.OutputName = {'vMid_d', 'vMid_q'};
assert(isstable(T_mid), 'EquipmentTuning:UnstableVoltageLoop', ...
    '给定设计未通过标称2×2电压闭环稳定性校核。');
% 标称通道可能存在数值上的临界极点；裕度用于SISO验收，稳定性由闭环极点判定。
[gm, pm, wcg, wcp] = margins(Cpi_v*G_mid(1, 1));
assert(isfinite(pm) && pm >= Design.MinimumPhaseMarginDeg, ...
    'EquipmentTuning:InsufficientPhaseMargin', ...
    'GFM电压环SISO相位裕度%.6g度低于要求%.6g度。', pm, Design.MinimumPhaseMarginDeg);
T_wv = squeeze(freqresp(T_mid, wv));
coupling = max(abs([T_wv(1, 2), T_wv(2, 1)])) ...
    /max(abs([T_wv(1, 1), T_wv(2, 2)]));
VL = struct('Kp', Design.Kp, 'Ki', Ki, ...
    'TargetBandwidthHz', Design.TargetBandwidthHz, ...
    'CurrentToVoltageBandwidthRatio', CurrentLoop.TargetBandwidthHz/Design.TargetBandwidthHz, ...
    'FeedbackVoltage', 'midpoint_voltage', 'InternalVoltageDefinition', 'midpoint_voltage', ...
    'UseI2Feedforward', Design.UseI2Feedforward, ...
    'UseDQDecouplingInTuning', Design.UseDQDecouplingInTuning, ...
    'RGAatTarget', rga, 'ClosedLoopCouplingRatio', coupling, ...
    'PhaseMarginDeg', pm, 'AchievedNominalCrossoverHz', wcp/(2*pi), ...
    'FullLCLMaxPoleReal', Max_Pole_Real, 'IsFullLCLStable', true, 'IsStable', true);
Diagnostics = struct('LCL', LCL, 'CurrentLoop', CurrentLoop, 'Design', Design, ...
    'Plant', G_mid, 'ClosedLoop', T_mid, 'ClosedLoopPoles', pole(T_mid), ...
    'FullLCLStateMatrix', A_full, 'FullLCLPoles', Full_Poles, ...
    'FullLCLMaxPoleReal', Max_Pole_Real, 'GainMargin', gm, 'PhaseMarginDeg', pm, ...
    'GainMarginFrequencyRad_s', wcg, 'CrossoverHz', wcp/(2*pi), ...
    'KpUpperBound', Controller_Magnitude, 'RGAatTarget', rga);
if Design.Verbose
    fprintf('GFM vMid: target %.6g Hz, Kp %.12g, Ki %.12g, PM %.6g deg, maxRe %.6g\n', ...
        Design.TargetBandwidthHz, VL.Kp, VL.Ki, pm, Max_Pole_Real);
end

%% 5. 按外部开关显示原有RGA及开闭环图。
frequencies = logspace(-1, 3, 2000);
if Design.ShowRGAPlots
    RGA_Values = NaN(2, 2, numel(frequencies));
    response = freqresp(G_mid, 2*pi*frequencies);
    for k = 1:numel(frequencies)
        Gjw = response(:, :, k);
        if all(isfinite(Gjw), 'all') && rcond(Gjw) >= 1e-12
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
    title('GFM midpoint-voltage-loop RGA');
end
if Design.ShowValidationPlots
    figure; bode(Cpi_v*G_mid(1, 1)); grid on;
    title('GFM midpoint-voltage-loop nominal SISO open-loop response');
    figure; bodemag(T_mid(1, 1), T_mid(1, 2), T_mid(2, 1), T_mid(2, 2), 2*pi*frequencies); grid on;
    legend('vMid_d/vMid_d_ref', 'vMid_d/vMid_q_ref', ...
        'vMid_q/vMid_d_ref', 'vMid_q/vMid_q_ref', 'Location', 'best');
    title('GFM midpoint-voltage-loop closed-loop response');
    G_cap_raw = ss(A_cap_raw, B_cap, eye(2), zeros(2));
    G_mid_raw = minreal((G_cap_raw+G_RC)*T_i1);
    figure; bodemag(G_mid(1, 1), G_mid_raw(1, 1), 2*pi*frequencies); grid on;
    legend('Tuned voltage plant', 'Raw voltage plant', 'Location', 'best');
    title('Voltage-loop tuning-plant comparison');
end
end

function A = full_lcl_closed_loop(LCL, CurrentLoop, Design, Ki)
% 状态：[i1_d i1_q vC_d vC_q i2_d i2_q xi_id xi_iq xi_vd xi_vq]。
L1 = LCL.L1; R_L1 = LCL.R_L1; Cf = LCL.Cf; R_C = LCL.R_C;
L2 = LCL.L2; R_L2 = LCL.R_L2; w0 = 2*pi*LCL.f;
selector = eye(10);
i1d = selector(1, :); i1q = selector(2, :);
vCd = selector(3, :); vCq = selector(4, :);
i2d = selector(5, :); i2q = selector(6, :);
xiId = selector(7, :); xiIq = selector(8, :);
xiVd = selector(9, :); xiVq = selector(10, :);
vMidd = vCd+R_C*(i1d-i2d);
vMidq = vCq+R_C*(i1q-i2q);
i1dRef = -Design.Kp*vMidd+Ki*xiVd+double(Design.UseI2Feedforward)*i2d ...
    -double(Design.UseDQDecouplingInTuning)*Cf*w0*vCq;
i1qRef = -Design.Kp*vMidq+Ki*xiVq+double(Design.UseI2Feedforward)*i2q ...
    +double(Design.UseDQDecouplingInTuning)*Cf*w0*vCd;
errorId = i1dRef-i1d;
errorIq = i1qRef-i1q;
controlVd = CurrentLoop.Kp*errorId+CurrentLoop.Ki*xiId;
controlVq = CurrentLoop.Kp*errorIq+CurrentLoop.Ki*xiIq;
coupling = (1-double(CurrentLoop.UseDQDecouplingInTuning))*w0;
A = zeros(10);
if strcmp(CurrentLoop.VoltageFeedforwardMode, 'midpoint_voltage')
    A(1, :) = (controlVd-R_L1*i1d)/L1+coupling*i1q;
    A(2, :) = (controlVq-R_L1*i1q)/L1-coupling*i1d;
else
    A(1, :) = (controlVd-R_C*(i1d-i2d)-R_L1*i1d)/L1+coupling*i1q;
    A(2, :) = (controlVq-R_C*(i1q-i2q)-R_L1*i1q)/L1-coupling*i1d;
end
A(3, :) = (i1d-i2d)/Cf+w0*vCq;
A(4, :) = (i1q-i2q)/Cf-w0*vCd;
A(5, :) = (vCd+R_C*(i1d-i2d)-R_L2*i2d)/L2+w0*i2q;
A(6, :) = (vCq+R_C*(i1q-i2q)-R_L2*i2q)/L2-w0*i2d;
A(7, :) = errorId; A(8, :) = errorIq;
A(9, :) = -vMidd; A(10, :) = -vMidq;
end

function [gm, pm, wcg, wcp] = margins(Open_Loop)
%% 计算开环稳定裕度，并在结束时恢复警告设置。
state = warning;
cleanup = onCleanup(@() warning(state)); %#ok<NASGU>
warning('off', 'all');
[gm, pm, wcg, wcp] = margin(Open_Loop);
end

function validate_inputs(LCL, CurrentLoop, Design)
%% 校验控制环整定所需的物理参数、设计输入及稳定性前提。
Required_LCL = {'L1', 'R_L1', 'Cf', 'R_C', 'L2', 'R_L2', 'f'};
Required_Current = {'Kp', 'Ki', 'TargetBandwidthHz', 'VoltageFeedforwardMode', ...
    'UseDQDecouplingInTuning', 'LCL', 'IsStable'};
Required_Design = {'TargetBandwidthHz', 'Kp', 'MinimumPhaseMarginDeg', ...
    'UseI2Feedforward', 'UseDQDecouplingInTuning', 'ShowRGAPlots', 'ShowValidationPlots', 'Verbose'};
assert(all(isfield(LCL, Required_LCL)) && all(isfield(CurrentLoop, Required_Current)) && ...
    all(isfield(Design, Required_Design)), 'EquipmentTuning:MissingInput', ...
    'LCL、CurrentLoop或Design缺少必填字段，整定函数不补入默认值。');
for k = 1:numel(Required_LCL)
    name = Required_LCL{k};
    validateattributes(LCL.(name), {'numeric'}, {'real', 'finite', 'scalar', 'nonnegative'}, mfilename, ...
        ['LCL.' name]);
    if ~startsWith(name, 'R_')
        assert(LCL.(name) > 0, 'EquipmentTuning:InvalidLCL', '%s必须为正值。', name);
    end
end
assert(isequaln(orderfields(CurrentLoop.LCL), orderfields(LCL)), ...
    'EquipmentTuning:PlantMismatch', '电压环与传入电流环必须使用同一组实际LCL参数。');
assert(CurrentLoop.IsStable, 'EquipmentTuning:UnstableCurrentLoop', '传入电流环未通过稳定性校核。');
for name = {'Kp', 'Ki', 'TargetBandwidthHz'}
    validateattributes(CurrentLoop.(name{1}), {'numeric'}, {'real', 'finite', 'scalar', 'positive'});
end
validateattributes(CurrentLoop.UseDQDecouplingInTuning, {'logical'}, {'scalar'});
validateattributes(Design.TargetBandwidthHz, {'numeric'}, {'real', 'finite', 'scalar', 'positive'});
validateattributes(Design.Kp, {'numeric'}, {'real', 'finite', 'scalar', 'positive'});
validateattributes(Design.MinimumPhaseMarginDeg, {'numeric'}, {'real', 'finite', 'scalar', 'nonnegative', ...
    '<', 180});
for name = {'UseI2Feedforward', 'UseDQDecouplingInTuning', 'ShowRGAPlots', 'ShowValidationPlots', 'Verbose'}
    validateattributes(Design.(name{1}), {'logical'}, {'scalar'});
end
end
