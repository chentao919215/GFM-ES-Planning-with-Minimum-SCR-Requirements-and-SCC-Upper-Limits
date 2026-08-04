%% 构网型变流器 i1 电流内环 PI 参数整定
% 本脚本用于整定 GFM 模型中的 i1_d/i1_q 电流内环。
%
% 建模口径：
% 1. 控制对象为流过逆变器侧电感 L1 的电流 i1。
% 2. 本方案采用 LCL 中点电压 vMid 前馈，因此电流环对象中的串联电阻
%    主要为逆变器侧电阻 R_L1，R_C 压降由 vMid 前馈直接包含。
% 3. 根据模型中的 dq 解耦配置决定整定对象是否保留交叉耦合项。
% 4. 最终结果写入 GFM_CL 结构体，供 GFM_Parameters.m 复核使用。

clear; clc; close all;

%% 1. 控制对象与整定参数
L1   = 1e-3;       % 逆变器侧电感 [H]
R_L1 = 10;         % 逆变器侧串联电阻 [ohm]
Cf   = 40e-6;      % 滤波电容 [F]
R_C  = 3;          % 电容支路串联阻尼电阻 [ohm]
L2   = 600e-6;     % 网侧电感，仅用于与完整 LCL 参数保持一致 [H]
R_L2 = 0.05;       % 网侧电阻，仅用于与完整 LCL 参数保持一致 [ohm]

fg = 50;           % 额定电网频率 [Hz]
w0 = 2*pi*fg;      % 同步 dq 坐标系角频率 [rad/s]

target_bandwidth_hz = 200;
wc = 2*pi*target_bandwidth_hz;

% 电压前馈方式：
% 'capacitor_voltage' 表示前馈理想电容电压，此时电流环对象包含 R_C；
% 'midpoint_voltage' 表示前馈 LCL 物理中点电压，此时对象只包含 R_L1。
voltage_feedforward_mode = 'midpoint_voltage';

% 仅当 Simulink 电流控制器显式补偿 +/-w0*L1*i1 交叉耦合项时设为 true。
use_dq_decoupling_in_tuning = false;

% 连续平均模型的 pidtune 结果可能不适合直接实现，因此允许约束 Kp
% 为正值，并在目标交越频率 wc 处重新计算 Ki。
use_manual_kp_constraint = true;
Kp_manual = 5;     % [V/A]

show_rga_plots        = false;
show_validation_plots = false;

assert(L1 > 0 && Cf > 0, 'L1 and Cf must be positive.');
assert(R_L1 >= 0 && R_C >= 0 && L2 > 0 && R_L2 >= 0, ...
    'Filter resistance and inductance values are invalid.');
assert(target_bandwidth_hz > 0, 'The target bandwidth must be positive.');

%% 2. 建立 2×2 dq 电流环对象
switch lower(voltage_feedforward_mode)
    case 'capacitor_voltage'
        R_i1 = R_L1 + R_C;
        feedforward_description = ...
            'Capacitor-voltage feedforward: R_C included.';
    case 'midpoint_voltage'
        R_i1 = R_L1;
        feedforward_description = ...
            'LCL-midpoint-voltage feedforward: only R_L1 included.';
    otherwise
        error('Unknown voltage_feedforward_mode: %s', ...
            voltage_feedforward_mode);
end

A_raw = [-R_i1/L1,  w0;
              -w0, -R_i1/L1];
B_i1 = [1/L1, 0;
           0, 1/L1];
C_i1 = eye(2);
D_i1 = zeros(2, 2);

if use_dq_decoupling_in_tuning
    A_tune = [-R_i1/L1, 0;
                    0, -R_i1/L1];
    coupling_description = 'dq cross-coupling compensated in the tuning plant.';
else
    A_tune = A_raw;
    coupling_description = 'dq cross-coupling retained in the tuning plant.';
end

G_i1 = ss(A_tune, B_i1, C_i1, D_i1);
G_i1.InputName  = {'v_ctrl_d', 'v_ctrl_q'};
G_i1.OutputName = {'i1_d', 'i1_q'};
G_i1.StateName  = {'i1_d', 'i1_q'};

fprintf('GFM inverter-side current-loop tuning\n');
fprintf('  %s\n', feedforward_description);
fprintf('  %s\n', coupling_description);
fprintf('  Equivalent resistance = %.12g ohm\n', R_i1);
fprintf('  Target bandwidth      = %.12g Hz\n', target_bandwidth_hz);

%% 3. 计算 RGA 并判断 d/q 轴配对
freq_hz    = logspace(0, 4, 2000);
w          = 2*pi*freq_hz;
rga_values = NaN(2, 2, numel(w));

for k = 1:numel(w)
    Gjw = squeeze(freqresp(G_i1, w(k)));
    if all(size(Gjw) == [2, 2]) && rcond(Gjw) >= 1e-12
        rga_values(:, :, k) = Gjw .* transpose(Gjw \ eye(2));
    end
end

G_wc = squeeze(freqresp(G_i1, wc));
if ~all(size(G_wc) == [2, 2]) || rcond(G_wc) < 1e-12
    error('The current plant is singular at the target bandwidth.');
end
rga_wc = G_wc .* transpose(G_wc \ eye(2));

diag_pairing_score = abs(rga_wc(1,1)-1) + abs(rga_wc(2,2)-1) ...
                   + abs(rga_wc(1,2)) + abs(rga_wc(2,1));
cross_pairing_score = abs(rga_wc(1,2)-1) + abs(rga_wc(2,1)-1) ...
                    + abs(rga_wc(1,1)) + abs(rga_wc(2,2));

if diag_pairing_score <= cross_pairing_score
    selected_pairing = 'Diagonal: v_ctrl_d -> i1_d, v_ctrl_q -> i1_q';
else
    selected_pairing = 'Cross: v_ctrl_d -> i1_q, v_ctrl_q -> i1_d';
end

fprintf('\nRGA at the target bandwidth:\n');
disp(rga_wc);
fprintf('  Diagonal pairing score = %.12g\n', diag_pairing_score);
fprintf('  Cross pairing score    = %.12g\n', cross_pairing_score);
fprintf('  Recommended pairing    = %s\n', selected_pairing);

if show_rga_plots
    figure;
    semilogx(freq_hz, squeeze(abs(rga_values(1,1,:))), 'LineWidth', 1.2); hold on;
    semilogx(freq_hz, squeeze(abs(rga_values(1,2,:))), 'LineWidth', 1.2);
    semilogx(freq_hz, squeeze(abs(rga_values(2,1,:))), 'LineWidth', 1.2);
    semilogx(freq_hz, squeeze(abs(rga_values(2,2,:))), 'LineWidth', 1.2);
    xline(target_bandwidth_hz, '--', 'Target bandwidth');
    grid on;
    xlabel('Frequency [Hz]');
    ylabel('RGA magnitude');
    legend('|lambda_{dd}|', '|lambda_{dq}|', '|lambda_{qd}|', ...
        '|lambda_{qq}|', 'Location', 'best');
    title('GFM current-loop RGA');
end

%% 4. 整定 d/q 轴对角 PI 控制器
[Cpi_pidtune, info_pidtune] = pidtune(G_i1(1,1), 'PI', wc);
Kp_pidtune = Cpi_pidtune.Kp;
Ki_pidtune = Cpi_pidtune.Ki;

[plant_mag_wc, plant_phase_wc] = bode(G_i1(1,1), wc);
plant_mag_wc   = squeeze(plant_mag_wc);
plant_phase_wc = squeeze(plant_phase_wc);
if ~isfinite(plant_mag_wc) || plant_mag_wc <= 0
    error('The current plant magnitude at wc is invalid.');
end

required_controller_mag = 1 / plant_mag_wc;
if use_manual_kp_constraint
    if Kp_manual <= 0 || Kp_manual >= required_controller_mag
        error(['Kp_manual must satisfy 0 < Kp_manual < %.12g V/A ' ...
            'at the target bandwidth.'], required_controller_mag);
    end
    Ki_manual = wc * sqrt(required_controller_mag^2 - Kp_manual^2);
    Cpi_suggested = pid(Kp_manual, Ki_manual);
    Kp_suggested = Kp_manual;
    Ki_suggested = Ki_manual;
else
    Ki_manual = NaN;
    Cpi_suggested = Cpi_pidtune;
    Kp_suggested = Kp_pidtune;
    Ki_suggested = Ki_pidtune;
end

K_i = append(Cpi_suggested, Cpi_suggested);
K_i.InputName  = {'e_i1_d', 'e_i1_q'};
K_i.OutputName = {'v_ctrl_d', 'v_ctrl_q'};

L_open_i1 = G_i1 * K_i;
T_closed_i1 = feedback(L_open_i1, eye(2));
T_closed_i1.InputName  = {'i1_d_ref', 'i1_q_ref'};
T_closed_i1.OutputName = {'i1_d', 'i1_q'};

[Gm_suggested, Pm_suggested, Wcg_suggested, Wcp_suggested] = ...
    margin(Cpi_suggested * G_i1(1,1));

%% 5. 输出整定结果并校核闭环
fprintf('\nSISO pidtune result:\n');
fprintf('  Kp = %.12g V/A\n', Kp_pidtune);
fprintf('  Ki = %.12g V/(A*s)\n', Ki_pidtune);
fprintf('  Crossover frequency = %.12g rad/s\n', info_pidtune.CrossoverFrequency);
fprintf('  Phase margin        = %.12g deg\n', info_pidtune.PhaseMargin);
fprintf('  |G_i1(jwc)|         = %.12g A/V\n', plant_mag_wc);
fprintf('  Plant phase at wc   = %.12g deg\n', plant_phase_wc);

if use_manual_kp_constraint
    fprintf('\nPI with the manual Kp constraint:\n');
    fprintf('  Kp_manual = %.12g V/A\n', Kp_manual);
    fprintf('  Ki_manual = %.12g V/(A*s)\n', Ki_manual);
    fprintf('  PI zero   = %.12g Hz\n', Ki_manual/Kp_manual/(2*pi));
end

fprintf('\nRecommended controller parameters:\n');
fprintf('  GFM_CL.Kp = %.12g;\n', Kp_suggested);
fprintf('  GFM_CL.Ki = %.12g;\n', Ki_suggested);
fprintf('  Crossover frequency = %.12g rad/s\n', Wcp_suggested);
fprintf('  Phase margin        = %.12g deg\n', Pm_suggested);
if isfinite(Gm_suggested) && Gm_suggested > 0
    fprintf('  Gain margin         = %.12g dB\n', 20*log10(Gm_suggested));
else
    fprintf('  Gain margin         = Inf or undefined\n');
end
fprintf('  Gain margin frequency = %.12g rad/s\n', Wcg_suggested);

T_wc = squeeze(freqresp(T_closed_i1, wc));
closed_loop_coupling_ratio = max(abs([T_wc(1,2), T_wc(2,1)])) ...
                           / max(abs([T_wc(1,1), T_wc(2,2)]));
closed_loop_poles = pole(T_closed_i1);
is_closed_loop_stable = isstable(T_closed_i1);

fprintf('\nClosed-loop validation at the target bandwidth:\n');
fprintf('  Off-diagonal/diagonal ratio = %.12g\n', ...
    closed_loop_coupling_ratio);
fprintf('  Stable = %d\n', is_closed_loop_stable);
fprintf('  Maximum pole real part = %.12g\n', max(real(closed_loop_poles)));

if show_validation_plots
    figure;
    margin(Cpi_suggested * G_i1(1,1));
    grid on;
    title('GFM current-loop open-loop margins');

    figure;
    bodemag(T_closed_i1(1,1), T_closed_i1(1,2), ...
        T_closed_i1(2,1), T_closed_i1(2,2), w);
    grid on;
    legend('i1_d/i1_d_ref', 'i1_d/i1_q_ref', ...
        'i1_q/i1_d_ref', 'i1_q/i1_q_ref', 'Location', 'best');
    title('GFM current-loop closed-loop response');
end

%% 6. 将整定结果写入基础工作区
GFM_CL = struct();
GFM_CL.Kp = Kp_suggested;
GFM_CL.Ki = Ki_suggested;
GFM_CL.TargetBandwidthHz = target_bandwidth_hz;
GFM_CL.VoltageFeedforwardMode = voltage_feedforward_mode;
GFM_CL.UseDQDecouplingInTuning = use_dq_decoupling_in_tuning;
GFM_CL.R_equivalent = R_i1;
GFM_CL.RGAatTarget = rga_wc;
GFM_CL.ClosedLoopCouplingRatio = closed_loop_coupling_ratio;
GFM_CL.PhaseMarginDeg = Pm_suggested;
GFM_CL.IsStable = is_closed_loop_stable;

assignin('base', 'GFM_CL', GFM_CL);
