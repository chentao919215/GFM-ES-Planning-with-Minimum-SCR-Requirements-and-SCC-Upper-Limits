%% 构网型变流器 vMid 电压外环 PI 参数整定
% 本脚本在逆变器侧 i1 电流内环闭环后，整定 vMid_d/vMid_q 电压外环。
%
% 建模口径：
% 1. 标称电压环对象不包含网侧阻抗，将 i2 视为外部扰动。
% 2. L2 与 R_L2 保留在参数中，用于完整 LCL 闭环稳定性校核。
% 3. 电压环输出为 i1 参考值，并包含 i2 前馈与电容 dq 耦合补偿。
% 4. 最终结果写入 GFM_VL 结构体，供 GFM_Parameters.m 复核使用。

clear; clc; close all;

%% 1. 控制对象与整定参数
L1   = 1e-3;       % 逆变器侧电感 [H]
R_L1 = 10;         % 逆变器侧串联电阻 [ohm]
Cf   = 40e-6;      % 滤波电容 [F]
R_C  = 3;          % 电容支路串联阻尼电阻 [ohm]
L2   = 600e-6;     % 网侧电感，用于完整 LCL 稳定性校核 [H]
R_L2 = 0.05;       % 网侧电阻，用于完整 LCL 稳定性校核 [ohm]

fg = 50;           % 额定电网频率 [Hz]
w0 = 2*pi*fg;      % 同步 dq 坐标系角频率 [rad/s]

target_current_bandwidth_hz = 200;
voltage_to_current_bw_ratio = 4;
target_voltage_bandwidth_hz = ...
    target_current_bandwidth_hz / voltage_to_current_bw_ratio;
wv = 2*pi*target_voltage_bandwidth_hz;

% 电流环参数来源：
% 'recalculate' 表示按电流环脚本的相同口径重新计算；
% 'manual' 表示直接使用下方给定的电流环 PI 参数。
current_pi_source = 'recalculate';
current_Kp_manual = 5;
current_Ki_manual = 5000;
current_voltage_feedforward_mode = 'midpoint_voltage';
use_current_dq_decoupling_in_tuning = false;
use_current_manual_kp_constraint = true;
current_Kp_constraint = 5;

% 电压环实现选项：
% i2 前馈用于补偿电容节点电流平衡；
% dq 解耦用于补偿同步旋转坐标系中的电容电压交叉耦合。
use_i2_feedforward = true;
use_voltage_dq_decoupling_in_tuning = true;

use_voltage_manual_kp_constraint = false;
voltage_Kp_manual = 0.05;       % [A/V]
target_phase_margin_deg = 60;

% 标称 pidtune 对象将 i2 视为独立扰动。采用精确 i2 前馈后，有限带宽
% 电流环会在完整 L1-C-L2 动态中把 L2 模态反馈至 i1_ref，因此还需
% 使用十阶完整 LCL 闭环模型校核。下列参数为通过该校核的稳健建议值。
use_full_lcl_robust_recommendation = true;
% 当前电压环参数为完整LCL闭环极点校核后的保守参数；
% 目标是兼顾vMid恢复速度与LCL动态稳定性。
full_lcl_voltage_Kp = 0.013;       % [A/V]
full_lcl_voltage_Ki = 0.01;      % [A/(V*s)]

show_rga_plots        = false;
show_validation_plots = false;

assert(L1 > 0 && Cf > 0, 'L1 and Cf must be positive.');
assert(R_L1 >= 0 && R_C >= 0 && L2 > 0 && R_L2 >= 0, ...
    'Filter resistance and inductance values are invalid.');
assert(target_current_bandwidth_hz > 0 && voltage_to_current_bw_ratio > 0, ...
    'Bandwidth settings must be positive.');

fprintf('GFM midpoint-voltage outer-loop tuning\n');
fprintf('  Target current bandwidth = %.12g Hz\n', ...
    target_current_bandwidth_hz);
fprintf('  Target voltage bandwidth = %.12g Hz\n', ...
    target_voltage_bandwidth_hz);
fprintf('  Bandwidth ratio fc_i/fc_v = %.12g\n', ...
    voltage_to_current_bw_ratio);
fprintf('  i2 feedforward = %d\n', use_i2_feedforward);
fprintf('  Voltage dq decoupling in tuning = %d\n', ...
    use_voltage_dq_decoupling_in_tuning);

%% 2. 闭合逆变器侧 i1 电流内环
switch lower(current_voltage_feedforward_mode)
    case 'capacitor_voltage'
        R_i1 = R_L1 + R_C;
    case 'midpoint_voltage'
        R_i1 = R_L1;
    otherwise
        error('Unknown current_voltage_feedforward_mode: %s', ...
            current_voltage_feedforward_mode);
end

A_i1_raw = [-R_i1/L1,  w0;
                -w0, -R_i1/L1];
B_i1 = [1/L1, 0;
           0, 1/L1];

if use_current_dq_decoupling_in_tuning
    A_i1_tune = [-R_i1/L1, 0;
                        0, -R_i1/L1];
else
    A_i1_tune = A_i1_raw;
end

G_i1 = ss(A_i1_tune, B_i1, eye(2), zeros(2));
G_i1.InputName  = {'v_ctrl_d', 'v_ctrl_q'};
G_i1.OutputName = {'i1_d', 'i1_q'};

switch lower(current_pi_source)
    case 'recalculate'
        wci = 2*pi*target_current_bandwidth_hz;
        [Cpi_i_pidtune, info_i_pidtune] = pidtune(G_i1(1,1), 'PI', wci);
        [mag_i_wc, ~] = bode(G_i1(1,1), wci);
        mag_i_wc = squeeze(mag_i_wc);
        if ~isfinite(mag_i_wc) || mag_i_wc <= 0
            error('The current plant magnitude at wci is invalid.');
        end
        required_i_controller_mag = 1/mag_i_wc;

        if use_current_manual_kp_constraint
            if current_Kp_constraint <= 0 || ...
                    current_Kp_constraint >= required_i_controller_mag
                error(['current_Kp_constraint must satisfy 0 < Kp < ' ...
                    '%.12g V/A.'], required_i_controller_mag);
            end
            current_Ki_used = wci * sqrt( ...
                required_i_controller_mag^2-current_Kp_constraint^2);
            current_Kp_used = current_Kp_constraint;
            Cpi_i = pid(current_Kp_used, current_Ki_used);
        else
            current_Kp_used = Cpi_i_pidtune.Kp;
            current_Ki_used = Cpi_i_pidtune.Ki;
            Cpi_i = Cpi_i_pidtune;
        end

    case 'manual'
        if current_Kp_manual <= 0 || current_Ki_manual <= 0
            error('Manual current-loop Kp and Ki must be positive.');
        end
        current_Kp_used = current_Kp_manual;
        current_Ki_used = current_Ki_manual;
        Cpi_i = pid(current_Kp_used, current_Ki_used);
        info_i_pidtune = struct('CrossoverFrequency', NaN, ...
            'PhaseMargin', NaN);

    otherwise
        error('Unknown current_pi_source: %s', current_pi_source);
end

K_i = append(Cpi_i, Cpi_i);
K_i.InputName  = {'e_i1_d', 'e_i1_q'};
K_i.OutputName = {'v_ctrl_d', 'v_ctrl_q'};
T_i1 = feedback(G_i1*K_i, eye(2));
T_i1.InputName  = {'i1_d_ref', 'i1_q_ref'};
T_i1.OutputName = {'i1_d', 'i1_q'};
is_current_loop_stable = isstable(T_i1);

fprintf('\nCurrent-loop result used by the voltage-loop tuning:\n');
fprintf('  Kp_i = %.12g V/A\n', current_Kp_used);
fprintf('  Ki_i = %.12g V/(A*s)\n', current_Ki_used);
fprintf('  Stable = %d\n', is_current_loop_stable);

%% 3. 建立电流内环闭环后的电容电压对象
% d(vC_d)/dt = (i1_d-i2_d)/Cf + w0*vC_q
% d(vC_q)/dt = (i1_q-i2_q)/Cf - w0*vC_d
% 其中 i2 作为外部扰动处理。i1_ref_corr 到 vC 的参考通道不包含
% 网侧阻抗，L2 与 R_L2 仅在后续完整 LCL 闭环模型中参与校核。
A_cap_raw = [0,  w0;
            -w0,  0];
B_cap = [1/Cf, 0;
            0, 1/Cf];
C_cap = eye(2);
D_cap = zeros(2);

G_cap_raw = ss(A_cap_raw, B_cap, C_cap, D_cap);
G_cap_raw.InputName  = {'delta_i1_d', 'delta_i1_q'};
G_cap_raw.OutputName = {'vC_d', 'vC_q'};
G_RC = ss([], [], [], R_C*eye(2));

if use_voltage_dq_decoupling_in_tuning
    A_cap_tune = zeros(2);
    voltage_plant_description = ...
        'dq-decoupled midpoint-voltage plant, 1/(Cf*s)+R_C.';
else
    A_cap_tune = A_cap_raw;
    voltage_plant_description = ...
        'Midpoint-voltage plant with dq cross-coupling retained.';
end

G_cap_tune = ss(A_cap_tune, B_cap, C_cap, D_cap);
G_cap_tune.InputName  = {'delta_i1_d', 'delta_i1_q'};
G_cap_tune.OutputName = {'vC_d', 'vC_q'};

% vMid = vC + R_C*(i1-i2)。标称参考通道将 i2 作为扰动，
% 因此从 i1_ref_corr 到 vMid 的通道包含 R_C*i1 的直接项。
G_mid = minreal((G_cap_tune+G_RC)*T_i1);
G_mid.InputName  = {'i1_d_ref_corr', 'i1_q_ref_corr'};
G_mid.OutputName = {'vMid_d', 'vMid_q'};
G_mid_raw = minreal((G_cap_raw+G_RC)*T_i1);

fprintf('\nMidpoint-voltage plant: %s\n', voltage_plant_description);
fprintf('Nominal voltage-loop tuning excludes L2 and R_L2.\n');

%% 4. 计算 RGA 并判断 d/q 轴配对
freq_hz    = logspace(-1, 3, 2000);
w          = 2*pi*freq_hz;
rga_values = NaN(2, 2, numel(w));

for k = 1:numel(w)
    Gjw = squeeze(freqresp(G_mid, w(k)));
    if all(size(Gjw) == [2, 2]) && rcond(Gjw) >= 1e-12
        rga_values(:, :, k) = Gjw .* transpose(Gjw \ eye(2));
    end
end

G_wv = squeeze(freqresp(G_mid, wv));
if ~all(size(G_wv) == [2, 2]) || rcond(G_wv) < 1e-12
    error('The voltage plant is singular at the target bandwidth.');
end
rga_wv = G_wv .* transpose(G_wv \ eye(2));

G_raw_wv = squeeze(freqresp(G_mid_raw, wv));
if all(size(G_raw_wv) == [2, 2]) && rcond(G_raw_wv) >= 1e-12
    rga_raw_wv = G_raw_wv .* transpose(G_raw_wv \ eye(2));
else
    rga_raw_wv = NaN(2);
end

diag_pairing_score = abs(rga_wv(1,1)-1) + abs(rga_wv(2,2)-1) ...
                   + abs(rga_wv(1,2)) + abs(rga_wv(2,1));
cross_pairing_score = abs(rga_wv(1,2)-1) + abs(rga_wv(2,1)-1) ...
                    + abs(rga_wv(1,1)) + abs(rga_wv(2,2));

if diag_pairing_score <= cross_pairing_score
    selected_pairing = ...
        'Diagonal: i1_d_ref_corr -> vMid_d, i1_q_ref_corr -> vMid_q';
else
    selected_pairing = ...
        'Cross: i1_d_ref_corr -> vMid_q, i1_q_ref_corr -> vMid_d';
end

fprintf('\nRGA at the target voltage bandwidth:\n');
disp(rga_wv);
fprintf('  Diagonal pairing score = %.12g\n', diag_pairing_score);
fprintf('  Cross pairing score    = %.12g\n', cross_pairing_score);
fprintf('  Recommended pairing    = %s\n', selected_pairing);
fprintf('\nRaw, non-decoupled RGA at the target bandwidth:\n');
disp(rga_raw_wv);

if show_rga_plots
    figure;
    semilogx(freq_hz, squeeze(abs(rga_values(1,1,:))), 'LineWidth', 1.2); hold on;
    semilogx(freq_hz, squeeze(abs(rga_values(1,2,:))), 'LineWidth', 1.2);
    semilogx(freq_hz, squeeze(abs(rga_values(2,1,:))), 'LineWidth', 1.2);
    semilogx(freq_hz, squeeze(abs(rga_values(2,2,:))), 'LineWidth', 1.2);
    xline(target_voltage_bandwidth_hz, '--', 'Target bandwidth');
    grid on;
    xlabel('Frequency [Hz]');
    ylabel('RGA magnitude');
    legend('|lambda_{dd}|', '|lambda_{dq}|', '|lambda_{qd}|', ...
        '|lambda_{qq}|', 'Location', 'best');
    title('GFM midpoint-voltage-loop RGA');
end

%% 5. 整定电压外环 PI 控制器
tune_options = pidtuneOptions('PhaseMargin', target_phase_margin_deg);
[Cpi_v_pidtune, info_v_pidtune] = ...
    pidtune(G_mid(1,1), 'PI', wv, tune_options);

Kp_v_pidtune = Cpi_v_pidtune.Kp;
Ki_v_pidtune = Cpi_v_pidtune.Ki;
[plant_mag_wv, plant_phase_wv] = bode(G_mid(1,1), wv);
plant_mag_wv   = squeeze(plant_mag_wv);
plant_phase_wv = squeeze(plant_phase_wv);
if ~isfinite(plant_mag_wv) || plant_mag_wv <= 0
    error('The voltage plant magnitude at wv is invalid.');
end

required_v_controller_mag = 1/plant_mag_wv;
if use_voltage_manual_kp_constraint
    if voltage_Kp_manual <= 0 || ...
            voltage_Kp_manual >= required_v_controller_mag
        error(['voltage_Kp_manual must satisfy 0 < Kp < ' ...
            '%.12g A/V.'], required_v_controller_mag);
    end
    voltage_Ki_manual = wv * sqrt( ...
        required_v_controller_mag^2-voltage_Kp_manual^2);
    Cpi_v = pid(voltage_Kp_manual, voltage_Ki_manual);
    Kp_v_used = voltage_Kp_manual;
    Ki_v_used = voltage_Ki_manual;
else
    voltage_Ki_manual = NaN;
    Cpi_v = Cpi_v_pidtune;
    Kp_v_used = Kp_v_pidtune;
    Ki_v_used = Ki_v_pidtune;
end

nominal_full_lcl_A = buildFullLclClosedLoop( ...
    L1, R_L1, Cf, R_C, L2, R_L2, w0, ...
    current_Kp_used, current_Ki_used, ...
    Kp_v_used, Ki_v_used, use_i2_feedforward, ...
    use_voltage_dq_decoupling_in_tuning, ...
    use_current_dq_decoupling_in_tuning, ...
    strcmp(current_voltage_feedforward_mode, 'midpoint_voltage'));
nominal_full_lcl_poles = eig(nominal_full_lcl_A);
nominal_full_lcl_max_pole_real = max(real(nominal_full_lcl_poles));
is_nominal_full_lcl_stable = nominal_full_lcl_max_pole_real < 0;

if use_full_lcl_robust_recommendation
    assert(full_lcl_voltage_Kp > 0 && full_lcl_voltage_Ki > 0, ...
        'The full-LCL robust voltage gains must be positive.');
    Cpi_v = pid(full_lcl_voltage_Kp, full_lcl_voltage_Ki);
    Kp_v_used = full_lcl_voltage_Kp;
    Ki_v_used = full_lcl_voltage_Ki;
end

full_lcl_A = buildFullLclClosedLoop( ...
    L1, R_L1, Cf, R_C, L2, R_L2, w0, ...
    current_Kp_used, current_Ki_used, ...
    Kp_v_used, Ki_v_used, use_i2_feedforward, ...
    use_voltage_dq_decoupling_in_tuning, ...
    use_current_dq_decoupling_in_tuning, ...
    strcmp(current_voltage_feedforward_mode, 'midpoint_voltage'));
full_lcl_poles = eig(full_lcl_A);
full_lcl_max_pole_real = max(real(full_lcl_poles));
is_full_lcl_stable = full_lcl_max_pole_real < 0;
assert(is_full_lcl_stable, ...
    'The final voltage PI does not stabilize the complete LCL model.');

K_v = append(Cpi_v, Cpi_v);
K_v.InputName  = {'e_vMid_d', 'e_vMid_q'};
K_v.OutputName = {'i1_d_ref_corr', 'i1_q_ref_corr'};
L_open_v = G_mid*K_v;
T_closed_mid = feedback(L_open_v, eye(2));
T_closed_mid.InputName  = {'vMid_d_ref', 'vMid_q_ref'};
T_closed_mid.OutputName = {'vMid_d', 'vMid_q'};

% 电压 PI 由标称 SISO 通道 G_mid(1,1) 整定，但闭环校核采用完整 2×2
% 模型。当 T_i1 保留 dq 耦合时，直接对 G_mid(1,1) 调用 margin 可能
% 报告具有误导性的临界极点。因此默认参数采用 pidtune 给出的 SISO
% 交越频率与相位裕度，并使用 MIMO 闭环极点判断稳定性。
if use_voltage_manual_kp_constraint || ...
        use_full_lcl_robust_recommendation
    warning_state = warning;
    warning('off', 'all');
    [Gm_v, Pm_v, Wcg_v, Wcp_v] = margin(Cpi_v*G_mid(1,1));
    warning(warning_state);
else
    Gm_v = NaN;
    Pm_v = info_v_pidtune.PhaseMargin;
    Wcg_v = NaN;
    Wcp_v = info_v_pidtune.CrossoverFrequency;
end

%% 6. 输出整定结果并校核闭环
fprintf('\nSISO voltage pidtune result:\n');
fprintf('  Kp_v = %.12g A/V\n', Kp_v_pidtune);
fprintf('  Ki_v = %.12g A/(V*s)\n', Ki_v_pidtune);
fprintf('  Crossover frequency = %.12g rad/s\n', ...
    info_v_pidtune.CrossoverFrequency);
fprintf('  Phase margin        = %.12g deg\n', info_v_pidtune.PhaseMargin);
fprintf('  |G_mid(jwv)|        = %.12g V/A\n', plant_mag_wv);
fprintf('  Plant phase at wv   = %.12g deg\n', plant_phase_wv);
fprintf('  Complete-LCL maximum pole real part = %.12g\n', ...
    nominal_full_lcl_max_pole_real);
fprintf('  Complete-LCL stable = %d\n', is_nominal_full_lcl_stable);

if use_voltage_manual_kp_constraint
    fprintf('\nVoltage PI with the manual Kp constraint:\n');
    fprintf('  Kp_manual = %.12g A/V\n', voltage_Kp_manual);
    fprintf('  Ki_manual = %.12g A/(V*s)\n', voltage_Ki_manual);
    fprintf('  PI zero   = %.12g Hz\n', ...
        voltage_Ki_manual/voltage_Kp_manual/(2*pi));
end

if use_full_lcl_robust_recommendation
    fprintf('\nApplied complete-LCL robust correction:\n');
    fprintf('  Exact i2 feedforward retained = %d\n', ...
        use_i2_feedforward);
    fprintf('  Voltage dq decoupling retained = %d\n', ...
        use_voltage_dq_decoupling_in_tuning);
end

fprintf('\nFinal recommended controller parameters:\n');
fprintf('  GFM_CL.Kp = %.12g;\n', current_Kp_used);
fprintf('  GFM_CL.Ki = %.12g;\n', current_Ki_used);
fprintf('  GFM_VL.Kp = %.12g;\n', Kp_v_used);
fprintf('  GFM_VL.Ki = %.12g;\n', Ki_v_used);
fprintf('  Crossover frequency = %.12g rad/s\n', Wcp_v);
fprintf('  Crossover frequency = %.12g Hz\n', Wcp_v/(2*pi));
fprintf('  Phase margin        = %.12g deg\n', Pm_v);
if isfinite(Gm_v) && Gm_v > 0
    fprintf('  Gain margin         = %.12g dB\n', 20*log10(Gm_v));
else
    fprintf('  Gain margin         = not reported for the MIMO validation loop\n');
end
if isfinite(Wcg_v)
    fprintf('  Gain margin frequency = %.12g rad/s\n', Wcg_v);
end

T_wv = squeeze(freqresp(T_closed_mid, wv));
closed_loop_coupling_ratio = max(abs([T_wv(1,2), T_wv(2,1)])) ...
                           / max(abs([T_wv(1,1), T_wv(2,2)]));
closed_loop_poles = pole(T_closed_mid);
is_voltage_loop_stable = isstable(T_closed_mid);

fprintf('\nClosed-loop validation at the target bandwidth:\n');
fprintf('  Off-diagonal/diagonal ratio = %.12g\n', ...
    closed_loop_coupling_ratio);
fprintf('  Stable = %d\n', is_voltage_loop_stable);
fprintf('  Maximum pole real part = %.12g\n', max(real(closed_loop_poles)));
fprintf('\nComplete-LCL validation of the final controller:\n');
fprintf('  Stable = %d\n', is_full_lcl_stable);
fprintf('  Maximum pole real part = %.12g\n', full_lcl_max_pole_real);

if Pm_v < 35
    warning(['The recommended voltage PI phase margin is below 35 deg. ' ...
        'Consider reducing the voltage-loop bandwidth.']);
end

if show_validation_plots
    figure;
    bode(Cpi_v*G_mid(1,1));
    grid on;
    title('GFM midpoint-voltage-loop nominal SISO open-loop response');

    figure;
    bodemag(T_closed_mid(1,1), T_closed_mid(1,2), ...
        T_closed_mid(2,1), T_closed_mid(2,2), w);
    grid on;
    legend('vMid_d/vMid_d_ref', 'vMid_d/vMid_q_ref', ...
        'vMid_q/vMid_d_ref', 'vMid_q/vMid_q_ref', 'Location', 'best');
    title('GFM midpoint-voltage-loop closed-loop response');

    figure;
    bodemag(G_mid(1,1), G_mid_raw(1,1), w);
    grid on;
    legend('Tuned voltage plant', 'Raw voltage plant', 'Location', 'best');
    title('Voltage-loop tuning-plant comparison');
end

%% 7. 将整定结果写入基础工作区
GFM_CL_used = struct();
GFM_CL_used.Kp = current_Kp_used;
GFM_CL_used.Ki = current_Ki_used;
GFM_CL_used.TargetBandwidthHz = target_current_bandwidth_hz;
GFM_CL_used.VoltageFeedforwardMode = current_voltage_feedforward_mode;
GFM_CL_used.UseDQDecouplingInTuning = ...
    use_current_dq_decoupling_in_tuning;
GFM_CL_used.IsStable = is_current_loop_stable;

GFM_VL = struct();
GFM_VL.Kp = Kp_v_used;
GFM_VL.Ki = Ki_v_used;
GFM_VL.TargetBandwidthHz = target_voltage_bandwidth_hz;
GFM_VL.CurrentToVoltageBandwidthRatio = voltage_to_current_bw_ratio;
GFM_VL.FeedbackVoltage = 'midpoint_voltage';
GFM_VL.InternalVoltageDefinition = 'midpoint_voltage';
GFM_VL.UseI2Feedforward = use_i2_feedforward;
GFM_VL.UseDQDecouplingInTuning = ...
    use_voltage_dq_decoupling_in_tuning;
GFM_VL.RGAatTarget = rga_wv;
GFM_VL.RawRGAatTarget = rga_raw_wv;
GFM_VL.ClosedLoopCouplingRatio = closed_loop_coupling_ratio;
GFM_VL.PhaseMarginDeg = Pm_v;
GFM_VL.AchievedNominalCrossoverHz = Wcp_v/(2*pi);
GFM_VL.NominalPidtuneKp = Kp_v_pidtune;
GFM_VL.NominalPidtuneKi = Ki_v_pidtune;
GFM_VL.NominalFullLCLMaxPoleReal = ...
    nominal_full_lcl_max_pole_real;
GFM_VL.FullLCLMaxPoleReal = full_lcl_max_pole_real;
GFM_VL.IsNominalFullLCLStable = is_nominal_full_lcl_stable;
GFM_VL.IsFullLCLStable = is_full_lcl_stable;
GFM_VL.IsStable = is_voltage_loop_stable && is_full_lcl_stable;

assignin('base', 'GFM_CL_used', GFM_CL_used);
assignin('base', 'GFM_VL', GFM_VL);

function A = buildFullLclClosedLoop( ...
        L1, R_L1, Cf, R_C, L2, R_L2, w0, ...
        currentKp, currentKi, voltageKp, voltageKi, ...
        useI2Feedforward, useVoltageDecoupling, ...
        useCurrentDecoupling, useMidpointVoltageFeedforward)
% 完整 LCL 闭环模型的状态顺序：
% [i1_d i1_q vC_d vC_q i2_d i2_q xi_id xi_iq xi_vd xi_vq].

selector = eye(10);
i1d = selector(1,:);
i1q = selector(2,:);
vCd = selector(3,:);
vCq = selector(4,:);
i2d = selector(5,:);
i2q = selector(6,:);
xiId = selector(7,:);
xiIq = selector(8,:);
xiVd = selector(9,:);
xiVq = selector(10,:);

vMidd = vCd + R_C*(i1d-i2d);
vMidq = vCq + R_C*(i1q-i2q);

i1dRef = -voltageKp*vMidd + voltageKi*xiVd ...
    + double(useI2Feedforward)*i2d ...
    - double(useVoltageDecoupling)*Cf*w0*vCq;
i1qRef = -voltageKp*vMidq + voltageKi*xiVq ...
    + double(useI2Feedforward)*i2q ...
    + double(useVoltageDecoupling)*Cf*w0*vCd;

errorId = i1dRef-i1d;
errorIq = i1qRef-i1q;
controlVd = currentKp*errorId + currentKi*xiId;
controlVq = currentKp*errorIq + currentKi*xiIq;

A = zeros(10);
if useMidpointVoltageFeedforward
    A(1,:) = (controlVd-R_L1*i1d)/L1 ...
        + (1-double(useCurrentDecoupling))*w0*i1q;
    A(2,:) = (controlVq-R_L1*i1q)/L1 ...
        - (1-double(useCurrentDecoupling))*w0*i1d;
else
    A(1,:) = (controlVd-R_C*(i1d-i2d)-R_L1*i1d)/L1 ...
        + (1-double(useCurrentDecoupling))*w0*i1q;
    A(2,:) = (controlVq-R_C*(i1q-i2q)-R_L1*i1q)/L1 ...
        - (1-double(useCurrentDecoupling))*w0*i1d;
end
A(3,:) = (i1d-i2d)/Cf + w0*vCq;
A(4,:) = (i1q-i2q)/Cf - w0*vCd;
A(5,:) = (vCd+R_C*(i1d-i2d)-R_L2*i2d)/L2 + w0*i2q;
A(6,:) = (vCq+R_C*(i1q-i2q)-R_L2*i2q)/L2 - w0*i2d;
A(7,:) = errorId;
A(8,:) = errorIq;
A(9,:) = -vMidd;
A(10,:) = -vMidq;
end
