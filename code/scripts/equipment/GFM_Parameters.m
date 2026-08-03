%% 构网型变流器模型参数
% 本脚本用于独立初始化 Grid_Forming_Inverters.slx 所需的工作区变量。
% 脚本不动态调用 GFL_Parameters.m，避免 clear 语句和隐式工作区依赖。

%% 1. 基准值与直流侧参数
V_base = 38.5e3;                         % 线电压有效值基准 [V]
S_base = 60e6;                           % 三相视在功率基准 [VA]
V_base_phase = sqrt(2/3)*V_base;         % 相电压峰值基准 [V]
I_base = S_base/(sqrt(3)*V_base);        % 线电流有效值基准 [A]
V_in = 120e3;                            % 直流侧电压 [V]

%% 2. LCL 滤波器参数
L1   = 1e-3;                             % 逆变器侧电感 [H]
R_L1 = 10;                               % 逆变器侧电阻 [ohm]
Cf   = 40e-6;                            % 滤波电容 [F]
R_C  = 3;                                % 电容支路串联阻尼电阻 [ohm]
L2   = 600e-6;                           % 网侧电感 [H]
R_L2 = 0.05;                             % 网侧电阻 [ohm]

%% 3. 电网、开关与仿真参数
Vg = V_base;
f = 50;
fs = 10e3;
i2_lpf_fc = 300;

% 电网强度与等值电感参数。
SCR = 3;
MISCR = 3;
Zg = Vg^2/(S_base*SCR);
Lg = Zg/(2*pi*f);
Lij = (SCR/MISCR-1)*Lg;
t_close = 0;

GFM_Sim = struct();
GFM_Sim.t_stop = 0.5;
GFM_Sim.validation_stop_time = 0.5;

%% 4. 逆变器侧 i1 电流内环参数
% 参数取自 GFM_Current_Loop_PI_Calculation.m 的最终建议结果。
GFM_CL = struct();
GFM_CL.Kp = 5;
GFM_CL.Ki = 7555.28706553;
GFM_CL.TargetBandwidthHz = 100;
GFM_CL.VoltageFeedforwardMode = 'capacitor_voltage';
GFM_CL.UseDQDecouplingInTuning = false;
GFM_CL.R_equivalent = R_L1 + R_C;
GFM_CL.PWMDelay = 0.5/fs;

%% 5. 电容电压 vC 外环参数
% 参数取自 GFM_Voltage_Loop_PI_Calculation.m 的最终建议结果。
% NominalPidtuneKp/Ki 保留标称对象的 pidtune 结果；模型实际使用
% 通过完整 LCL 闭环稳定性校核的 Kp/Ki。
GFM_VL = struct();
GFM_VL.Kp = 0.01;
GFM_VL.Ki = 0.0032;
GFM_VL.TargetBandwidthHz = 25;
GFM_VL.AchievedNominalCrossoverHz = 35.664792139;
GFM_VL.CurrentToVoltageBandwidthRatio = 4;
GFM_VL.UseI2Feedforward = true;
GFM_VL.UseDQDecouplingInTuning = true;
GFM_VL.NominalPidtuneKp = 0.0064160127976;
GFM_VL.NominalPidtuneKi = 0.276736212226;
GFM_VL.FullLCLMaxPoleReal = -0.170909;

%% 6. P-f 与 Q-E 下垂控制参数
GFM_Droop = struct();
GFM_Droop.f0 = 50;
GFM_Droop.w0 = 2*pi*GFM_Droop.f0;
GFM_Droop.theta0 = -pi/2;

% 有功、无功参考值均采用标幺量。
GFM_Droop.Pref_pu = 0.5;
GFM_Droop.Qref_pu = 0;

% 2% P-f 下垂与 5% Q-E 下垂。
GFM_Droop.Rf = 0.02;
GFM_Droop.mp_hz = GFM_Droop.f0*GFM_Droop.Rf;
GFM_Droop.mp = 2*pi*GFM_Droop.mp_hz;
GFM_Droop.nq = 0.05;

% PCC 侧 P/Q 测量一阶低通滤波器。
GFM_Droop.PQ_lpf_fc = 5;
GFM_Droop.PQ_lpf_wc = 2*pi*GFM_Droop.PQ_lpf_fc;

% 频率参考与内部电势参考限幅。
GFM_Droop.f_min = 49;
GFM_Droop.f_max = 51;
GFM_Droop.w_min = 2*pi*GFM_Droop.f_min;
GFM_Droop.w_max = 2*pi*GFM_Droop.f_max;
GFM_Droop.E_min_pu = 0.90;
GFM_Droop.E_max_pu = 1.10;

%% 7. 参数一致性检查
assert(V_base > 0 && S_base > 0 && V_in > 0, ...
    'Base values and dc-link voltage must be positive.');
assert(L1 > 0 && L2 > 0 && Cf > 0, ...
    'LCL inductances and capacitance must be positive.');
assert(GFM_CL.Kp > 0 && GFM_CL.Ki > 0, ...
    'GFM current-loop PI gains must be positive.');
assert(GFM_VL.Kp > 0 && GFM_VL.Ki > 0, ...
    'GFM voltage-loop PI gains must be positive.');
assert(strcmp(GFM_CL.VoltageFeedforwardMode, 'capacitor_voltage'), ...
    'The first GFM model version requires capacitor-voltage feedforward.');
assert(abs(GFM_Droop.mp-2*pi) < 1e-12, ...
    'The configured 2%% P-f droop slope must equal 2*pi rad/s per p.u.');
