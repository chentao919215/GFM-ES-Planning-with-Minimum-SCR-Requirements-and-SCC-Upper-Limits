%% GFL i2 current-loop PI tuning with LCL internal losses
clear; clc; close all;

%% Scope of this tuning model
% This script extends Cunrrent_Loop_PI_Caluculation_2 by adding the
% measurable internal losses of the LCL filter:
%   - L1 series resistance
%   - L2 series resistance
%   - series damping resistance in the capacitor branch
%
% Grid impedance is intentionally excluded because it belongs to the
% external system, not to the LCL filter itself. PWM delay is also excluded
% because its exact value depends on sampling, carrier implementation, and
% digital control details.
%
% The plant below assumes that vPCC_d and vPCC_q are feed-forwarded before
% the dq0-to-abc transformation. The PI controller output is therefore the
% incremental inverter voltage command over the PCC voltage.

%% Parameters
L1 = 1e-3;
R_L1 = 10;
L2 = 600e-6;
R_L2 = 0.05;
Cf = 20e-6;
R_C = 3;

% Additional LCL internal loss parameters.
% R_L1 should match the physical L1 branch resistance and the resistance
% compensation term used in the Simulink model.
fg = 50;
w0 = 2*pi*fg;

target_bandwidth_hz = 200;
wc = 2*pi*target_bandwidth_hz;

% Manual engineering constraint. Set this flag to false if you want to use
% the unconstrained pidtune result directly. str2double keeps MATLAB Code
% Analyzer from treating either branch below as unreachable.
use_manual_kp_constraint = logical(str2double('1'));
Kp_manual = 5;

%% Continuous-time plant
% State: x = [i1d i1q vcd vcq i2d i2q]^T
% Input: u = [v_ctrl_d; v_ctrl_q]
% Output: y = [i2d; i2q]
%
% The capacitor branch is modeled as a series R-C shunt branch. With
% iC = i1 - i2, the LCL midpoint voltage is
%
%   v_mid = vC + R_C * (i1 - i2)
%
% and the capacitor state equation remains
%
%   d(vC)/dt = iC / Cf plus the dq cross-coupling terms.

A = [-(R_L1 + R_C)/L1,        w0,       -1/L1,       0,          R_C/L1,        0;
             -w0, -(R_L1 + R_C)/L1,       0,    -1/L1,             0,     R_C/L1;
            1/Cf,                 0,       0,       w0,         -1/Cf,        0;
              0,               1/Cf,     -w0,        0,             0,    -1/Cf;
          R_C/L2,                 0,     1/L2,        0, -(R_L2 + R_C)/L2,   w0;
              0,             R_C/L2,       0,     1/L2,           -w0, -(R_L2 + R_C)/L2];

B = [1/L1    0;
        0 1/L1;
        0    0;
        0    0;
        0    0;
        0    0];

Cout = [0 0 0 0 1 0;
        0 0 0 0 0 1];
D = zeros(2, 2);

G = ss(A, B, Cout, D);
G.InputName = {'v_ctrl_d', 'v_ctrl_q'};
G.OutputName = {'i2_d', 'i2_q'};
G.StateName = {'i1_d', 'i1_q', 'vc_d', 'vc_q', 'i2_d', 'i2_q'};

%% Reference plant from Cunrrent_Loop_PI_Caluculation_2 for comparison
A_ref = [-R_L1/L1      w0 -1/L1     0       0     0;
            -w0 -R_L1/L1     0 -1/L1       0     0;
           1/Cf      0     0     w0  -1/Cf     0;
             0    1/Cf   -w0      0      0 -1/Cf;
             0       0  1/L2      0      0    w0;
             0       0     0   1/L2    -w0     0];

G_ref = ss(A_ref, B, Cout, D);

%% Tune PI parameters for the d-axis current loop
[Cpi, info] = pidtune(G(1,1), 'PI', wc);
Kp = Cpi.Kp;
Ki = Cpi.Ki;

[Cpi_ref, info_ref] = pidtune(G_ref(1,1), 'PI', wc);

%% Manual Kp-constrained PI tuning
% pidtune can return Kp = 0 because the continuous averaged plant is close
% to a positive gain around the target bandwidth. For implementation in a
% switched Simulink model, a small proportional term can be useful as an
% engineering constraint. Here Kp is specified manually, and Ki is recomputed
% so that the loop still crosses over at wc:
%
%   |(Kp + Ki/s) * G(j*wc)| = 1
%
% This keeps the intended current-loop bandwidth while enforcing Kp ~= 0.
[plant_mag_wc, plant_phase_wc] = bode(G(1,1), wc);
plant_mag_wc = squeeze(plant_mag_wc);
plant_phase_wc = squeeze(plant_phase_wc);
required_controller_mag = 1 / plant_mag_wc;

if use_manual_kp_constraint
    if Kp_manual <= 0
        error('Kp_manual must be positive when use_manual_kp_constraint is true.');
    end
    if Kp_manual >= required_controller_mag
        error(['Kp_manual = %.12g is too large for the %.6g Hz target bandwidth. ', ...
               'It must be smaller than %.12g.'], ...
               Kp_manual, target_bandwidth_hz, required_controller_mag);
    end

    Ki_manual = wc * sqrt(required_controller_mag^2 - Kp_manual^2);
    Cpi_manual = pid(Kp_manual, Ki_manual);
    [Gm_manual, Pm_manual, Wcg_manual, Wcp_manual] = margin(Cpi_manual * G(1,1));

    Kp_suggested = Kp_manual;
    Ki_suggested = Ki_manual;
    Cpi_suggested = Cpi_manual;
else
    Ki_manual = NaN;
    Cpi_manual = [];
    Gm_manual = NaN;
    Pm_manual = NaN;
    Wcg_manual = NaN;
    Wcp_manual = NaN;

    Kp_suggested = Kp;
    Ki_suggested = Ki;
    Cpi_suggested = Cpi;
end

fprintf('Target bandwidth = %.6g Hz\n', target_bandwidth_hz);
fprintf('\nExtended LCL model with internal losses:\n');
fprintf('  R_L1 = %.12g ohm\n', R_L1);
fprintf('  R_L2 = %.12g ohm\n', R_L2);
fprintf('  R_C  = %.12g ohm\n', R_C);
fprintf('  Kp   = %.12g\n', Kp);
fprintf('  Ki   = %.12g\n', Ki);
fprintf('  Achieved crossover = %.12g rad/s\n', info.CrossoverFrequency);
fprintf('  Phase margin       = %.12g deg\n', info.PhaseMargin);
fprintf('  Plant |G(j*wc)|    = %.12g\n', plant_mag_wc);
fprintf('  Plant phase(j*wc)  = %.12g deg\n', plant_phase_wc);

fprintf('\nReference model from Calculation_2:\n');
fprintf('  Kp   = %.12g\n', Cpi_ref.Kp);
fprintf('  Ki   = %.12g\n', Cpi_ref.Ki);
fprintf('  Achieved crossover = %.12g rad/s\n', info_ref.CrossoverFrequency);
fprintf('  Phase margin       = %.12g deg\n', info_ref.PhaseMargin);

if use_manual_kp_constraint
    fprintf('\nManual Kp-constrained PI for the extended model:\n');
    fprintf('  Kp_manual          = %.12g\n', Kp_manual);
    fprintf('  Ki_manual          = %.12g\n', Ki_manual);
    fprintf('  PI zero frequency  = %.12g Hz\n', Ki_manual / Kp_manual / (2*pi));
    fprintf('  Achieved crossover = %.12g rad/s\n', Wcp_manual);
    fprintf('  Phase margin       = %.12g deg\n', Pm_manual);
    fprintf('  Gain margin        = %.12g dB\n', 20*log10(Gm_manual));
    fprintf('  Gain-margin freq   = %.12g rad/s\n', Wcg_manual);
else
    fprintf('\nManual Kp-constrained PI is disabled.\n');
end

fprintf('\nSimulink parameter suggestion:\n');
fprintf('  CL.Kp = %.12g;\n', Kp_suggested);
fprintf('  CL.Ki = %.12g;\n', Ki_suggested);

%% Optional validation plots
freq_hz = logspace(0, 4, 2000);
w = 2*pi*freq_hz;

figure;
bode(G_ref(1,1), G(1,1), w);
grid on;
legend('Calculation 2 plant', 'Calculation 3 plant', 'Location', 'best');
title('Plant comparison: v_{ctrl,d} to i_{2,d}');

figure;
bode(Cpi_ref, Cpi, Cpi_suggested, w);
grid on;
legend('Calculation 2 PI', 'Calculation 3 pidtune PI', 'Calculation 3 suggested PI', 'Location', 'best');
title('PI controller comparison');

figure;
margin(Cpi_suggested * G(1,1));
grid on;
title('Open-loop margin for Calculation 3 suggested PI');
