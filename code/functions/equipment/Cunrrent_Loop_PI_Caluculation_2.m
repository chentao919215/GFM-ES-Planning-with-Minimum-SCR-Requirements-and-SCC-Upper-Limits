%% GFL i2 current-loop PI tuning with corrected continuous-time model
clear; clc; close all;

%% Parameters
% Keep the numerical parameters and target bandwidth aligned with the first
% tuning section in Cunrrent_Loop_PI_Caluculation_1 for a direct comparison.
% R1 = 5.1041667;
% L1 = 5.1041667e-4;
% L2 = 1.53125e-4;
% Cf = 3.9183673e-5;

R1 = 10;
L1 = 1e-3;
L2 = 300e-6;
Cf = 20e-6;

fg = 50;
w0 = 2*pi*fg;

% State: x = [i1d i1q vcd vcq i2d i2q]^T
A = [-R1/L1      w0 -1/L1     0       0     0;
         -w0 -R1/L1     0 -1/L1       0     0;
        1/Cf      0     0     w0  -1/Cf     0;
          0    1/Cf   -w0      0      0 -1/Cf;
          0       0  1/L2      0      0    w0;
          0       0     0   1/L2    -w0     0];

% Input: u = [v_inv_d; v_inv_q]. Both axes act on i1 through L1.
B = [1/L1    0;
        0 1/L1;
        0    0;
        0    0;
        0    0;
        0    0];

% Output: y = [i2d; i2q]
Cout = [0 0 0 0 1 0;
        0 0 0 0 0 1];
D = zeros(2, 2);

%% Build standard continuous-time state-space plant
G = ss(A, B, Cout, D);

%% Tune PI parameters for the d-axis current loop
wc = 2*pi*200;
[Cpi, info] = pidtune(G(1,1), 'PI', wc);
Kp = Cpi.Kp;
Ki = Cpi.Ki;

fprintf('Kp = %.12g\n', Kp);
fprintf('Ki = %.12g\n', Ki);

%% Optional validation plots
freq_rad_s = logspace(0, 5, 2000);

figure;
bode(G(1,1), freq_rad_s);
grid on;
title('|G_{11}(j\omega)|');

figure;
bode(Cpi, freq_rad_s);
grid on;
title('|PI(j\omega)|');
