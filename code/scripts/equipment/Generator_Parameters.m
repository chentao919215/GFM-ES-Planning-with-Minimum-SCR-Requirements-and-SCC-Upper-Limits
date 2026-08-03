%% Traditional_Generator 参数与次暂态端口等值计算
% 本脚本只保留 Traditional_Generator.slx 当前使用的参数。
%
% 模型含义：Simplified Synchronous Machine pu Units 被作为
%   E'' behind (Ra + jXd'')
% 的端口快照使用。它不用于复现 Ik'' -> Ik' -> Ik_inf 的衰减过程。
% 机端三相故障时，周期分量理论值按正序端口等值计算。
%
% 标幺基准：三相容量 S_N、线电压有效值 V_N；因此
%   I_N = S_N/(sqrt(3)*V_N), Z_N = V_N^2/S_N。
% 脚本不执行 clear/clc，便于由模型 InitFcn 或校核脚本调用。
%
% Traditional_Generator.slx 的实际变量映射：
%   S_N/V_N/f_N       -> 同步机 NominalParameters、三相电压源频率
%   H_machine/D_machine/pole_pairs -> Mechanical
%   R_a/X_dpp         -> InternalRL，即 E'' 后的 Ra+jXd''
%   machine_initial_conditions -> InitialConditions（含 E'' 角度和三相电流相角）
%   E_internal_pu/speed_pu -> 内部电势幅值输入、机械速度输入
%   P_0/Q_0           -> 同步机潮流初始化参数
%   R_grid_ohm/L_grid_H/E_grid_peak/grid_phase_deg -> 外部电网支路与受控电压源
%   t_fault/t_clear/R_fault -> 三相故障块
%   powergui_sample_time/t_stop -> powergui、命令信号和模型仿真时长

%% 1. 额定值与三相基准量
S_N = 100e6;                         % 三相容量基准/额定视在功率，VA
V_N = 38.5e3;                        % 线电压有效值基准，V
f_N = 50;                            % 电气频率，Hz
pole_pairs = 1;                      % 极对数，无量纲

S_base_3ph = S_N;                    % 三相容量基准，VA
V_base_ll_rms = V_N;                 % 线电压有效值基准，V
I_base = S_base_3ph/(sqrt(3)*V_base_ll_rms); % 线电流有效值基准，A
Z_base = V_base_ll_rms^2/S_base_3ph; % 三相等值阻抗基准，ohm

% 保留旧脚本中模型/后处理常用的别名。
I_N = I_base;                        % 额定线电流基准，A
Z_N = Z_base;                        % 阻抗基准，ohm
omega_e_N = 2*pi*f_N;                % 电气角频率，rad/s
omega_m_N = omega_e_N/pole_pairs;    % 机械角频率，rad/s
n_N = 60*f_N/pole_pairs;             % 机械转速，r/min

%% 2. 同步机端口等值参数
% 以下电抗均以 S_N、V_N 为基准的 pu 值；本模型只使用 Ra 与 Xd''。
R_a = 0.003;                         % 定子电阻 Ra，pu（S_N/V_N 基准）
X_dpp = 0.23;                        % 次暂态直轴电抗 Xd''，pu

% 机械参数仍由简化同步机块要求，但机械速度被固定为 1 pu；
% H/D 不参与次暂态电流理论值，也不用于产生电流衰减。
H_machine = 3.7;                     % 惯性常数 H，s
D_machine = 0;                       % 阻尼系数 D，pu_T/pu_w
speed_pu = 1;                         % 固定机械速度，pu

%% 3. 故障前运行点与 E''、初始角
P_0 = 80e6;                           % 故障前有功注入，W；正号表示发电机向电网送电
Q_0 = 0;                             % 故障前无功注入，var
V_0 = V_N;                           % 故障前机端线电压有效值，V
theta_0 = 0;                          % 故障前机端电压相角，deg

P_0_pu = P_0/S_base_3ph;             % 故障前有功，pu
Q_0_pu = Q_0/S_base_3ph;             % 故障前无功，pu
V_0_pu = V_0/V_base_ll_rms;          % 故障前线电压，pu
V_0_pu_complex = V_0_pu*exp(1j*deg2rad(theta_0));
S_0_pu_complex = (P_0 + 1j*Q_0)/S_base_3ph;

% 发电机向外送电的正序线电流：S_pu = V_pu * conj(I_pu)。
I_0_pu_complex = conj(S_0_pu_complex/V_0_pu_complex);
I_0_pu = abs(I_0_pu_complex);       % 故障前电流有效值，pu
I_0 = I_0_pu_complex*I_base;         % 故障前复数线电流，A
I_0_mag = abs(I_0);                  % 故障前线电流有效值，A

% 端口外特性：E'' = V0 + (Ra + jXd'') I0。
Z_dpp_pu = R_a + 1j*X_dpp;            % 发电机次暂态内部阻抗，pu
E_double_pu_complex = V_0_pu_complex + Z_dpp_pu*I_0_pu_complex;
E_internal_pu = abs(E_double_pu_complex); % 内部次暂态电势幅值 E''，pu
E_internal_angle_deg = rad2deg(angle(E_double_pu_complex));

% InitialConditions = [dw th ia ib ic pha phb phc]。
% th 使用 E'' 相对于机端电压的初始角，电流相角与潮流方向一致。
I_0_angle_deg = rad2deg(angle(I_0_pu_complex));
machine_initial_conditions = [0, E_internal_angle_deg, ...
    I_0_pu, I_0_pu, I_0_pu, ...
    I_0_angle_deg, I_0_angle_deg - 120, I_0_angle_deg + 120];

%% 4. 机端三相金属性短路与理论 Ik''
t_fault = 0.20;                       % 三相故障投入时刻，s
t_clear = 0.40;                       % 故障切除时刻，s
R_fault = 1e-4;                       % 故障电阻，ohm；相对 Z_base 足够小，作为数值正则

R_fault_pu = R_fault/Z_base;           % 故障电阻，pu
Z_fault_dpp_pu = (R_a + R_fault_pu) + 1j*X_dpp;
I_kpp_pu = E_internal_pu/abs(Z_fault_dpp_pu); % 次暂态短路电流，pu
I_kpp = I_kpp_pu*I_base;               % 次暂态短路电流周期分量有效值，A
I_kpp_kA = I_kpp/1e3;                  % 次暂态短路电流周期分量有效值，kA

%% 5. 外部电网等值（用于故障前潮流与后续混合电源扩展）
% 该支路不改变发电机端口参数；故障初期机组电流由机端三相故障钳位。
R_grid_pu = 0.005;                     % 电网等值电阻，pu（S_N/V_N 基准）
X_grid_pu = 0.05;                      % 电网等值电抗，pu（S_N/V_N 基准）
R_grid_ohm = R_grid_pu*Z_base;         % 电网等值电阻，ohm
L_grid_H = X_grid_pu*Z_base/omega_e_N; % 电网等值电感，H

% 使故障前机端电压 V0 与 P0/Q0 和电网潮流方向相容：
% E_grid = V0 - Z_grid*I0，其中 I0 定义为机组向电网注入的电流。
E_grid_pu_complex = V_0_pu_complex - ...
    (R_grid_pu + 1j*X_grid_pu)*I_0_pu_complex;
V_phase_peak_base = sqrt(2/3)*V_base_ll_rms; % 单相相电压峰值基准，V
E_grid_peak = abs(E_grid_pu_complex)*V_phase_peak_base;
grid_phase_deg = rad2deg(angle(E_grid_pu_complex));

%% 6. 统一 powergui 与求解器使用的公共量
powergui_sample_time = 50e-6;          % 与 Grid_Following_Inverters_LVRT 一致，s
t_stop = 1.0;                          % 模型停止时间，s；故障时间窗位于此范围内

%% 7. 诊断输出（模型 InitFcn 调用时也可见）
fprintf('Traditional_Generator 次暂态端口参数：E'''' = %.8f pu, angle = %.6f deg, Xd'''' = %.8f pu, Ra = %.8f pu\n', ...
    E_internal_pu, E_internal_angle_deg, X_dpp, R_a);
fprintf('三相基准：Sbase = %.6g VA, Vbase_LL,rms = %.6g V, Ibase = %.6f A, Zbase = %.8f ohm\n', ...
    S_base_3ph, V_base_ll_rms, I_base, Z_base);
fprintf('故障前电流：I0 = %.6f pu = %.6f kA rms，P0 = %.6f pu，Q0 = %.6f pu\n', ...
    I_0_pu, I_0_mag/1e3, P_0_pu, Q_0_pu);
fprintf('理论次暂态短路电流：Ik'''' = %.8f pu = %.6f kA rms（Rfault = %.6g ohm）\n', ...
    I_kpp_pu, I_kpp_kA, R_fault);
