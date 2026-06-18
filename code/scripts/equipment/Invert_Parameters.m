%% 跟网型变流器 i2 电流内环 PI 参数整定脚本
% 本脚本用于为当前GFL模型中的i2_d/i2_q电流内环整定PI参数。
%
% 建模范围：
% 1. 考虑LCL滤波器内部可量化的损耗，包括L1电阻、L2电阻、C串联电阻。
% 2. 不考虑网侧阻抗。
% 3. 不考虑 PWM 延时。
% 4. PI输出对应相对于PCC电压的增量逆变器电压指令，需配合前馈。
%
% 脚本流程：
% LCL小信号建模 -> 绘制RGA -> 判断D/Q配对 -> 选取Kp/Ki -> 验证闭环解耦

clear; clc; close all;

%% 1. LCL滤波器与整定目标参数
% 下列参数应与当前Simulink模型和Invert_Parameters.m保持一致。
L1   = 1e-3;   % 逆变器侧电感
R_L1 = 10;     % 逆变器侧电感串联电阻，同时用于模型中的电阻补偿项
L2   = 600e-6; % 网侧电感
R_L2 = 0.05;   % 网侧电感串联电阻
Cf   = 40e-6;  % 滤波电容
R_C  = 3;      % 电容支路串联阻尼电阻

fg = 50;       % 电网频率
w0 = 2*pi*fg;  % dq 坐标系同步角速度

target_bandwidth_hz = 95;      % 目标电流环交越频率
wc = 2*pi*target_bandwidth_hz; % 目标电流环交越角频率

% 手动Kp约束。
% 连续平均模型下pidtune可能给出Kp=0。为了更贴近开关模型中的实现，
% 此处默认强制Kp为一个正数，再重新计算Ki以保持目标交越频率。
use_manual_kp_constraint = logical(str2double('1'));
Kp_manual = 5;

%% 2. 建立考虑内部损耗的连续时间LCL模型
% 状态变量：
%   x = [i1_d, i1_q, vc_d, vc_q, i2_d, i2_q]^T
%
% 输入变量：
%   u = [v_ctrl_d, v_ctrl_q]^T
%
% 输出变量：
%   y = [i2_d, i2_q]^T
%
% 电容支路按串联 R-C 支路处理。设 iC = i1 - i2，则 LCL 中点电压为：
%   v_mid = vC + R_C * (i1 - i2)
%
% dq 坐标系下额外包含同步旋转坐标引入的交叉耦合项。

A = [-(R_L1 + R_C)/L1,               w0, -1/L1,     0,           R_C/L1,                0;
                  -w0, -(R_L1 + R_C)/L1,     0, -1/L1,                0,           R_C/L1;
                 1/Cf,                0,     0,    w0,            -1/Cf,                0;
                    0,              1/Cf,  -w0,     0,                0,            -1/Cf;
               R_C/L2,                0,  1/L2,     0, -(R_L2 + R_C)/L2,               w0;
                    0,            R_C/L2,    0,  1/L2,              -w0, -(R_L2 + R_C)/L2];

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
G.InputName  = {'v_ctrl_d', 'v_ctrl_q'};
G.OutputName = {'i2_d', 'i2_q'};
G.StateName  = {'i1_d', 'i1_q', 'vc_d', 'vc_q', 'i2_d', 'i2_q'};

%% 3. 绘制RGA并判断D/Q轴配对
% RGA(Relative Gain Array，相对增益矩阵)用于判断多输入多输出系统中
% 输入与输出的配对关系。频域 RGA 定义为：
%   Lambda(jw) = G(jw).*transpose(inv(G(jw)))
%
% 若Lambda的对角元素接近1，非对角元素接近0，则说明采用
% v_ctrl_d -> i2_d、v_ctrl_q -> i2_q 的对角配对较合理；
% 此时可以使用D/Q两个相同的PI控制器形成对角控制器，实现近似解耦。

freq_hz    = logspace(0, 4, 2000);
w          = 2*pi*freq_hz;
rga_values = zeros(2, 2, numel(w));

for k = 1:numel(w)
    Gjw = squeeze(freqresp(G, w(k)));
    rga_values(:, :, k) = Gjw .* transpose(inv(Gjw));
end

G_wc   = squeeze(freqresp(G, wc));
rga_wc = G_wc.*transpose(inv(G_wc));

% 此处的score表示的是在指定带宽下的RGA矩阵相距单位矩阵的差距，因此越大越不解耦。
diag_pairing_score = abs(rga_wc(1,1)-1) + abs(rga_wc(2,2)-1) ...
                   + abs(rga_wc(1,2))   + abs(rga_wc(2,1));
cross_pairing_score = abs(rga_wc(1,2)-1) + abs(rga_wc(2,1)-1) ...
                    + abs(rga_wc(1,1))   + abs(rga_wc(2,2));

if diag_pairing_score <= cross_pairing_score
    selected_pairing = '对角配对：v_{ctrl,d}->i_{2,d}, v_{ctrl,q}->i_{2,q}';
else
    selected_pairing = '交叉配对：v_{ctrl,d}->i_{2,q}, v_{ctrl,q}->i_{2,d}';
end

fprintf('目标电流环带宽 = %.6g Hz\n', target_bandwidth_hz);
fprintf('\n目标带宽处的 RGA 矩阵 Lambda(jwc)：\n');
disp(rga_wc);
fprintf('  对角配对评分 = %.12g\n', diag_pairing_score);
fprintf('  交叉配对评分 = %.12g\n', cross_pairing_score);
fprintf('  建议配对方式 = %s\n', selected_pairing);

%% 4. 基于RGA配对选择D/Q轴PI参数
% 当前目标是通过D/Q两个相同的PI控制器形成对角控制器：
%   K(s) = diag(Kp + Ki/s, Kp + Ki/s)
%
% RGA若显示对角配对占优，则该控制器可以使d轴主要响应id_ref，
% q轴主要响应iq_ref，从而实现工程意义上的D/Q轴近似解耦。

[Cpi, info] = pidtune(G(1,1), 'PI', wc);
Kp_pidtune = Cpi.Kp;
Ki_pidtune = Cpi.Ki;

[plant_mag_wc, plant_phase_wc] = bode(G(1,1), wc);
plant_mag_wc = squeeze(plant_mag_wc);
plant_phase_wc = squeeze(plant_phase_wc);
required_controller_mag = 1 / plant_mag_wc;

if use_manual_kp_constraint
    if Kp_manual <= 0
        error('启用手动 Kp 约束时，Kp_manual 必须为正数。');
    end

    if Kp_manual >= required_controller_mag
        error(['Kp_manual = %.12g 对 %.6g Hz 目标带宽而言过大，', ...
               '应小于 %.12g。'], ...
               Kp_manual, target_bandwidth_hz, required_controller_mag);
    end

    Ki_manual = wc * sqrt(required_controller_mag^2 - Kp_manual^2);
    Cpi_suggested = pid(Kp_manual, Ki_manual);
    Kp_suggested = Kp_manual;
    Ki_suggested = Ki_manual;
else
    Ki_manual = NaN;
    Cpi_suggested = Cpi;
    Kp_suggested = Kp_pidtune;
    Ki_suggested = Ki_pidtune;
end

K_decouple = append(Cpi_suggested, Cpi_suggested);
K_decouple.InputName = {'e_d', 'e_q'};
K_decouple.OutputName = {'v_ctrl_d', 'v_ctrl_q'};

L_open = G * K_decouple;
T_closed = feedback(L_open, eye(2));
T_closed.InputName = {'i2_d_ref', 'i2_q_ref'};
T_closed.OutputName = {'i2_d', 'i2_q'};

[Gm_suggested, Pm_suggested, Wcg_suggested, Wcp_suggested] = margin(Cpi_suggested * G(1,1));


%% 清理无用变量 
clearvars -except Kp_suggested Ki_suggested

%% 参数设置
% 基准值
V_base = 38.5e3;
S_base = 60e6;

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
Vg  = V_base;
f   = 50; 
SCR = 3;
MISCR = 3;
Zg  = Vg^2/(S_base*SCR);
% Rg  = Zg/sqrt(101);
% Lg  = 10*Rg/(2*pi*f);
Lg  = Zg/(2*pi*f);
Lij = (SCR/MISCR-1)*Lg;
% Rij = (SCR/MISCR-1)*Rg;
t_close = 0.05;

% PLL参数
PLL = [];
PLL.Kp = 90;
PLL.Ki = 1200;
PLL.Kd = 0;

% 电流环内环PI参数
CL = [];
CL.Kp = Kp_suggested;
CL.Ki = Ki_suggested;

% PWM波频率
fs = 10e3;

% 功率外环参数
PQ = [];
PQ.Pref = S_base;
PQ.Qref = 0;
PQ.step_time_P = 0.15;
PQ.step_time_Q = 0.2;
PQ.v_lpf_fc = 200;
PQ.vdq_eps  = (0.05*sqrt(2/3)*Vg)^2;

clearvars Ki_suggested Kp_suggested
