%% 同步发电机单机三相短路仿真参数
% 说明：
% 1. 本脚本用于集中管理Synchronous Machine Round Rotor模块参数；
% 2. 标幺值均以同步机额定容量和额定电压为基准；
% 3. 当前参数对应 100 MVA、38.5 kV、50 Hz、1 对极圆转子同步发电机；
% 4. 故障前运行点为 P0 = 80 MW、Q0 = 0 Mvar、U0 = 1 pu。

%% 1. 额定参数
S_N = 100e6;                 % 额定视在功率，VA
V_N = 38.5e3;                % 额定线电压有效值，V
f_N = 50;                    % 额定电气频率，Hz
pole_pairs = 1;              % 极对数
baseEfd = 92.95;             % 励磁电压基值，V
baseIfd = 1300;              % 励磁电流基值，A

omega_e_N = 2*pi*f_N;        % 额定电气角速度，rad/s
omega_m_N = omega_e_N/pole_pairs;
n_N = 60*f_N/pole_pairs;     % 额定机械转速，r/min

%% 2. 基准值
I_N = S_N/(sqrt(3)*V_N);   % 额定线电流有效值，A
Z_N = V_N^2/S_N;           % 三相系统阻抗基值，ohm
T_N = S_N/omega_m_N;       % 转矩基值，N*m

%% 3. 同步机电抗参数
% 所有电抗均为 pu
R_a  = 0.003; % 定子电阻
X_l  = 0.15;  % 定子漏抗

X_d  = 1.81;  % Xd
X_q  = 1.76;  % Xq

X_dp = 0.30;  % Xd'
X_qp = 0.65;  % Xq'

X_dpp = 0.23; % Xd''
X_qpp = 0.25; % Xq''

%% 4. 短路时间常数
% 当前模块设置为 Short circuit time constants
T_dp  = 1.3260;              % d轴暂态短路时间常数   Td',s
T_dpp = 0.0230;              % d轴次暂态短路时间常数 Td'',s
T_qp  = 0.3693;              % q轴暂态短路时间常数   Tq',s
T_qpp = 0.0269;              % q轴次暂态短路时间常数 Tq'',s

% 开路时间常数，供同步机模块内部参数使用
T_d0p  = 8.0;                % d轴暂态开路时间常数 Td0'，s
T_d0pp = 0.03;               % d轴次暂态开路时间常数 Td0''，s
T_q0p  = 1.0;                % q轴暂态开路时间常数 Tq0'，s
T_q0pp = 0.07;               % q轴次暂态开路时间常数 Tq0''，s

%% 5. 故障前运行点
P_0 = 80e6;  % 故障前有功功率，W
Q_0 = 0;     % 故障前无功功率，var
V_0 = V_N;   % 故障前端电压线电压有效值，V
theta_0 = 0; % 故障前端电压相角，deg

P_0_pu = P_0/S_N;
Q_0_pu = Q_0/S_N;
V_0_pu = V_0/V_N;

S_0 = P_0 + 1j*Q_0;            % 故障前复功率，VA
I_0 = conj(S_0/(sqrt(3)*V_0));
I_0_mag = abs(I_0);            % 故障前线电流有效值，A
I_0_pu = I_0_mag / I_N;

%% 6. Associated Initial Conditions 计算结果
% 以下参数来自：
% Electrical > Display Associated Initial Conditions

delta_0 = 0.952107;    % 初始功角，rad
delta_0_deg = 54.5517; % 初始功角，deg

Efd_0 = 36.2472;       % 初始励磁电压，V
Ifd_0 = 2289.24;       % 初始励磁电流，A

Tm_0 = 255259;         % 初始机械转矩，N*m
Pm_0 = 8.0192e7;       % 初始机械功率，W

Tm_0_pu = 0.80192;     % 初始机械转矩，pu
Efd_0_pu = 1.76096;    % 励磁电压，励磁回路基值下 pu
Ifd_0_pu = 1.76096;    % 励磁电流，励磁回路基值下 pu

%% 7. 机械侧设置
% mech_mode = 1：固定同步转速，适合观察纯电磁暂态过程
% mech_mode = 2：恒定机械转矩，适合观察完整机电暂态过程
mech_mode = 1;

omega_m_ref = omega_m_N; % 固定机械角速度参考值，rad/s
n_m_ref = n_N;           % 固定机械转速参考值，r/min
Tm_ref = Tm_0;           % 恒定机械转矩参考值，N*m

%% 8. 励磁侧设置
% 第一版模型采用恒定励磁电压，不接 AVR
Efd_ref = Efd_0; % 励磁电压参考值，V

%% 9. 外部电网与测量基准
% 当前基准模型直接将机端连接至三相电压源，先排除线路暂态对初始化的影响
V_grid = V_N;                % 三相电源线电压有效值，V
grid_shift = 0;              % 三相电源相移，deg
U_phase_peak = sqrt(2/3)*V_N; % 三相各相电压峰值，V
sensor_Vrated = V_N;         % 三相传感器额定电压，V
field_Srated = S_N;          % 励磁接口额定容量，VA
field_f_rated = f_N;         % 励磁接口额定频率，Hz

%% 10. 故障设置
% 注意：当前基准模型尚未接入故障开关，以下参数供后续受控源/三相故障模块引用。
t_fault = 1.0;   % 三相短路投入时刻，s
t_clear = inf;   % 故障切除时刻，s；inf表示持续短路
R_fault = 1e-4;  % 故障电阻，ohm
L_fault = 0;     % 故障电感，H

%% 11. 仿真设置
t_stop = 8.0; % 仿真结束时间，s

% 为观察次暂态过程，最大步长取最小次暂态时间常数的 1/200
max_step = min(T_dpp, T_qpp)/200;

%% 12. 输出关键参数
fprintf('同步机额定电流 I_N = %.3f kA\n', I_N/1e3);
fprintf('同步机阻抗基值 Z_N = %.4f ohm\n', Z_N);
fprintf('额定机械转速 n_N = %.1f r/min\n', n_N);
fprintf('故障前定子电流 I_0 = %.3f kA = %.3f pu\n', ...
    I_0_mag/1e3, I_0_pu);
fprintf('初始励磁电压 Efd_0 = %.4f V\n', Efd_0);
fprintf('初始励磁电流 Ifd_0 = %.2f A\n', Ifd_0);
fprintf('初始机械转矩 Tm_0 = %.0f N*m\n', Tm_0);
fprintf('初始机械功率 Pm_0 = %.4f MW\n', Pm_0/1e6);
fprintf('建议求解器最大步长 max_step = %.6f s\n', max_step);
