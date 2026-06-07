%% 清理无用变量 
clear; clc; close all;

%% 参数设置
% 直流侧输入电压
V_in = 120e3;

% 滤波器参数
L1   = 1e-3;
R_L1 = 10;
Cf   = 40e-6;
R_C  = 3;
L2   = 600e-6;
R_L2 = 0.05;

% i2低通滤波器
i2_lpf_fc = 300;

% 网侧参数
Vg = 38.5e3;
f  = 50; 
Rg   = 0.8190; 
Lg   = 26.1e-3;
t_close = 0.05;

% PLL参数
PLL = [];
PLL.Kp = 90;
PLL.Ki = 1200;
PLL.Kd = 0;

% 电流环内环PI参数
CL = [];
CL.Kp = 1/2;
CL.Ki = 1256.7199728/2;

% PWM波频率
fs = 10e3;

% 功率外环参数
PQ = [];
PQ.Pref = 60e6;
PQ.Qref = 0;
PQ.step_time_P = 0.15;
PQ.step_time_Q = 0.2;
PQ.v_lpf_fc = 200;
PQ.vdq_eps  = (0.05*sqrt(2/3)*Vg)^2;
