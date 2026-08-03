%% Invert_Generator_Parameters
% 混合电源三节点算例统一参数脚本
% 用于：Grid_Following_Inverter_Generator.slx 和 Report04_Section5_3_Case_Study.m
%
% 约定：
%   1) 网络理论计算统一采用系统三相基准 S_B/V_B_LL；
%   2) 同步发电机次暂态参数采用 S_N/V_N 基准，本算例中与系统基准相同；
%   3) GFL 控制器内部仍采用自身设备基准 S_inv/V_inv_LL，所有进入网络
%      方程的 GFL 电流均通过 I_inv_base/I_B 换算到系统 pu；
%   4) 电压的 pu 均为线电压有效值基准，网络正序相量均为 RMS 相量；
%   5) 本脚本不执行 clear/clc/close all，便于模型 InitFcn 和报告脚本调用。

%% 1. 系统三相基准（网络方程和报告表格统一基准）
S_B = 100e6;                         % 系统三相容量基准，VA
V_B_LL = 38.5e3;                     % 系统线电压有效值基准，V
f0 = 50;                             % 工频，Hz
omega0 = 2*pi*f0;                    % 工频角频率，rad/s
I_B = S_B/(sqrt(3)*V_B_LL);          % 系统线电流有效值基准，A
Z_B = V_B_LL^2/S_B;                  % 系统三相等值阻抗基准，ohm
V_B_phase_rms = V_B_LL/sqrt(3);      % 相电压有效值基准，V
V_B_phase_peak = sqrt(2/3)*V_B_LL;   % 相电压峰值基准，V

% 与旧模型/旧后处理脚本兼容的系统基准别名。I_base 保留给 GFL
% 子系统使用，不再把系统 I_B 覆盖为 GFL 设备电流基准。
S_base_3ph = S_B;
V_base_ll_rms = V_B_LL;
I_base_system = I_B;
Z_base_system = Z_B;
I_N_system = I_B;
Z_base = Z_B;

%% 2. 三节点支路和外部电网等值阻抗（系统 S_B/V_B_LL 基准）
% z_ij_pu、Zth_pu 为正序串联阻抗；R/L 为 SPS 三相 RL 支路的每相有名值。
z12_pu = 0.01  + 1j*0.15;              % 节点1—节点2，pu(system)
z13_pu = 0.01  + 1j*0.20;              % 节点1—节点3，pu(system)
z23_pu = 0.01  + 1j*1.20;              % 节点2—节点3，pu(system)
Zth_pu = 0.005 + 1j*0.25;             % 节点3—外部电网等值阻抗，pu(system)

R12_ohm = real(z12_pu)*Z_B;           % 节点1—节点2每相电阻，ohm
L12_H = imag(z12_pu)*Z_B/omega0;      % 节点1—节点2每相电感，H
R13_ohm = real(z13_pu)*Z_B;           % 节点1—节点3每相电阻，ohm
L13_H = imag(z13_pu)*Z_B/omega0;      % 节点1—节点3每相电感，H
R23_ohm = real(z23_pu)*Z_B;           % 节点2—节点3每相电阻，ohm
L23_H = imag(z23_pu)*Z_B/omega0;      % 节点2—节点3每相电感，H
Rth_ohm = real(Zth_pu)*Z_B;           % 外部电网等值每相电阻，ohm
Lth_H = imag(Zth_pu)*Z_B/omega0;      % 外部电网等值每相电感，H

%% 3. 同步发电机次暂态端口等值（S_N/V_N 基准）
% 模型采用 E'' behind (Ra+jXd'') 的简化同步机端口模型。
S_N = S_B;                            % 发电机额定三相容量，VA；与系统基准一致
V_N = V_B_LL;                         % 发电机额定线电压有效值，V
f_N = f0;                             % 发电机额定频率，Hz
pole_pairs = 1;                       % 极对数，无量纲
H_machine = 3.7;                      % 惯性时间常数，s
D_machine = 0;                        % 阻尼系数，pu_T/pu_w
speed_pu = 1;                         % 初始机械转速，pu
R_a = 0.003;                          % 定子电阻，pu(S_N/V_N)
X_dpp = 0.23;                         % d 轴次暂态电抗 Xd''，pu(S_N/V_N)
Z_dpp_pu = R_a + 1j*X_dpp;            % 次暂态内电势后的端口阻抗，pu(system)

% 故障前运行点：正号表示同步发电机向网络注入有功。
P_0 = 80e6;                           % 故障前有功功率，W
Q_0 = 0;                              % 故障前无功功率，var
V_0 = V_N;                            % 故障前机端线电压有效值，V
theta_0 = 0;                          % 故障前机端电压相角，deg
P_0_pu = P_0/S_B;                     % 故障前有功，pu(system)
Q_0_pu = Q_0/S_B;                     % 故障前无功，pu(system)
V_0_pu = V_0/V_B_LL;                  % 故障前机端电压，pu(system)
V_0_pu_complex = V_0_pu*exp(1j*deg2rad(theta_0));
S_0_pu_complex = (P_0 + 1j*Q_0)/S_B;
I_0_pu_complex = conj(S_0_pu_complex/V_0_pu_complex); % 发电机注入网络，pu(system)
I_0_pu = abs(I_0_pu_complex);
I_0 = I_0_pu_complex*I_B;              % 故障前正序电流，A RMS
I_0_mag = abs(I_0);

% E'' = U0 + (Ra+jXd'')I0；复数形式供报告脚本使用，幅值/相角供模型使用。
E_double_pu_complex = V_0_pu_complex + Z_dpp_pu*I_0_pu_complex;
E_internal_pu = abs(E_double_pu_complex);
E_internal_angle_deg = rad2deg(angle(E_double_pu_complex));
I_0_angle_deg = rad2deg(angle(I_0_pu_complex));
machine_initial_conditions = [0, E_internal_angle_deg, ...
    I_0_pu, I_0_pu, I_0_pu, ...
    I_0_angle_deg, I_0_angle_deg-120, I_0_angle_deg+120];

% The simplified SPS synchronous-machine block receives E as a magnitude
% input and uses its quadrature-axis sinusoidal reference.  Report phasors
% use a cosine RMS convention, so map the model internal-voltage axis to
% -90 deg when forming the mixed-source fault-current phasor equation.
machine_voltage_axis_phase_deg = -90;

%% 4. 跟网型变流器设备参数和 LVRT 参数（GFL 自身设备基准）
% 这些量来自 GFL_Parameters.m 的最终参数设置段；控制器内部 pu
% 电流的基准为 I_inv_base，而非系统 I_B。
S_inv = 60e6;                         % GFL 额定三相容量，VA
V_inv_LL = V_B_LL;                    % GFL 额定线电压有效值，V
I_inv_base = S_inv/(sqrt(3)*V_inv_LL); % GFL 额定电流基准，A RMS
Z_inv_base = V_inv_LL^2/S_inv;        % GFL 自身阻抗基准，ohm
gfl_to_system_current_pu = I_inv_base/I_B; % GFL pu -> system pu 换算系数

% 保留当前 GFL 模型使用的基准变量：V_base/S_base/I_base 仅表示 GFL 设备。
V_base = V_inv_LL;                    % GFL 控制器线电压基准，V RMS
S_base = S_inv;                       % GFL 控制器容量基准，VA
I_base = I_inv_base;                  % GFL 控制器电流基准，A RMS
Vg = V_base;                          % GFL 等值电网线电压基准，V RMS
f = f0;                               % GFL 工频，Hz
V_base_phase = V_B_phase_peak;        % GFL 模型相电压峰值基准，V

% GFL LCL 参数（GFL_Parameters.m 的最终模型参数）
V_in = 120e3;                         % 直流侧输入电压，V
L1 = 1e-3;                            % 变流器侧滤波电感，H
R_L1 = 10;                            % 变流器侧滤波电感串联电阻，ohm
Cf = 40e-6;                           % 滤波电容，F
R_C = 3;                              % 电容支路串联阻尼电阻，ohm
L2 = 600e-6;                          % 电网侧滤波电感，H
R_L2 = 0.05;                          % 电网侧滤波电感串联电阻，ohm
i2_lpf_fc = 300;                      % 并网电流低通截止频率，Hz
SPS_high_value_parallel_R = 1e6;      % L2/z12 并联数值高阻阻尼，ohm；仅用于 SPS 拓扑正则化

% GFL 等值弱电网参数：只供 GFL 内部控制器使用，不能直接替代三节点
% 网络中的 z_ij_pu/Zth_pu。
SCR = 3;
MISCR = 3;
Zg = Vg^2/(S_base*SCR);               % GFL 自身基准下的等值阻抗，ohm
Lg = Zg/(2*pi*f);                     % GFL 自身基准下的等值电感，H
Lij = (SCR/MISCR-1)*Lg;               % GFL 内部互联系统电感，H
t_close = 0;                          % 并网开关投入时刻，s

PLL = struct('Kp',90,'Ki',1200,'Kd',0);
fs = 10e3;                            % PWM 频率，Hz
CL = struct('Kp',5,'Ki',2*pi*95);     % 电流内环 PI 参数
PQ = struct('Pref',S_base/2,'Qref',0,'step_time_P',0.15, ...
    'step_time_Q',0.20,'v_lpf_fc',200, ...
    'vdq_eps',(.05*sqrt(2/3)*Vg)^2);

% 故障前 d/q 电流参考值，均为 GFL 设备 pu。
Manual_Current_Ref = 1;               % 1=使用手动 d/q 参考值
Id_ref_manual = 0.8;                  % 故障前 d 轴电流参考值，pu(GFL)
Iq_ref_manual = 0;                    % 故障前 q 轴电流参考值，pu(GFL)

% LVRT 线性段和限流参数，均为 GFL 设备 pu。
I_N = 1.0;                            % GFL 额定电流，pu(GFL)
I_limit = 1.2;                        % GFL 最大允许电流，pu(GFL)
V_LVRT_max = 0.90;                    % LVRT 启动/线性段上限电压，pu(GFL)
V_LVRT_min = 0.20;                    % LVRT 无功饱和阈值电压，pu(GFL)
K_q_LVRT = 1.5;                       % 无功电流注入系数，pu(I)/pu(V)
Delta_Iq_LVRT_max = K_q_LVRT*(V_LVRT_max-V_LVRT_min)*I_N;

% GFL 参考电流和限流值换算到系统网络方程的 pu 基准。
I2_ref_system_pu = (Id_ref_manual + 1j*Iq_ref_manual)*gfl_to_system_current_pu;
I2_limit_system_pu = I_limit*gfl_to_system_current_pu;

%% 5. 外部电网等值电压源和三相金属性故障
% 外部电网等值源位于节点3，E_grid 为系统 pu 正序相量；Simulink
% 受控电压源采用相电压峰值 E_grid_peak 及 A/B/C 相序相角。
E_grid_pu_complex = 1 + 0j;           % 外部电网等值正序电压，pu(system)
E_grid_peak = abs(E_grid_pu_complex)*V_B_phase_peak;
% Grid Voltage Command采用正弦源，网络相量采用余弦约定，因此相角减90度。
grid_phase_deg = rad2deg(angle(E_grid_pu_complex)) - 90;

t_fault = 1.0;                        % 节点3三相短路投入时刻，s
t_clear = 1.40;                       % 故障切除时刻，s（提取窗在此之前）
R_fault = 1e-4;                        % 三相故障电阻，ohm/phase
R_fault_pu = R_fault/Z_B;              % 三相故障电阻，pu(system)

%% 6. 仿真求解器、记录和报告提取窗口
powergui_sample_time = 50e-6;         % SPS 离散采样时间，s
powergui_simulation_mode = 'Discrete';
powergui_solver_type = 'Tustin/Backward Euler (TBE)';
solver_name = 'ode3';
solver_fixed_step = powergui_sample_time;
t_stop = 1.45;                        % 仿真停止时间，s
t_extract_start = 1.20;               % 故障后稳定提取窗起点，s
t_extract_end = 1.35;                 % 故障后稳定提取窗终点，s

%% 7. 兼容诊断量
I_kpp_pu = abs(E_double_pu_complex)/abs(Z_dpp_pu + R_fault_pu);
I_kpp = I_kpp_pu*I_B;                 % 发电机单机次暂态短路电流，A RMS
I_kpp_kA = I_kpp/1e3;

fprintf(['Hybrid parameters loaded: Sbase=%.6g VA, Vbase_LL=%.6g V, ', ...
    'Ibase=%.6f A, Zbase=%.8f ohm; E''''=%.8f pu, Xd''''=%.8f pu, Ra=%.8f pu.\n'], ...
    S_B,V_B_LL,I_B,Z_B,E_internal_pu,X_dpp,R_a);
fprintf(['GFL device base: Sinv=%.6g VA, Iinv_base=%.6f A; ', ...
    'Iref=%.6f pu(system), Ilimit=%.6f pu(system).\n'], ...
    S_inv,I_inv_base,abs(I2_ref_system_pu),I2_limit_system_pu);
