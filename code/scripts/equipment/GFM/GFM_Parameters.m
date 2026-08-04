%% 构网型变流器模型参数
% 本脚本用于独立初始化 Grid_Forming_Inverters.slx 所需的工作区变量。
% 脚本不动态调用 GFL_Parameters.m，避免 clear 语句和隐式工作区依赖。

%% 1. 基准值与直流侧参数
V_base = 38.5e3;                         % 线电压有效值基准 [V]
S_base = 60e6;                           % 三相视在功率基准 [VA]
V_base_phase = sqrt(2/3)*V_base;         % 相电压峰值基准 [V]
I_base_rms   = S_base/(sqrt(3)*V_base);  % 线电流有效值基准 [A]
I_base_peak  = sqrt(2)*I_base_rms;       % dq峰值电流基准 [A]
I_base = I_base_rms;                     % 兼容现有脚本的线电流有效值基准 [A]
V_in   = 120e3;                          % 直流侧电压 [V]

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
Grid_X_R = 10;
Rg = Zg/sqrt(1 + Grid_X_R^2);
Lg = Grid_X_R*Rg/(2*pi*f);
Lij = (SCR/MISCR-1)*Lg;
t_close = 0.5;

GFM_Sim = struct();
GFM_Sim.t_stop = 6;
GFM_Sim.validation_stop_time = 3;

%% 4. 逆变器侧 i1 电流内环参数
% 参数取自 GFM_Current_Loop_PI_Calculation.m 的最终建议结果。
GFM_CL = struct();
GFM_CL.Kp = 5;
GFM_CL.Ki = 1.101049928403827e+04;
GFM_CL.TargetBandwidthHz = 200;
GFM_CL.VoltageFeedforwardMode = 'midpoint_voltage';
GFM_CL.UseDQDecouplingInTuning = false;
GFM_CL.R_equivalent = R_L1;
GFM_CL.PWMDelay = 0.5/fs;

%% 5. LCL中点电压 vMid 外环参数
% 参数取自 GFM_Voltage_Loop_PI_Calculation.m 的最终建议结果。
% 当前版本将 vMid = vC + R_C*(i1-i2) 作为GFM内部受控电势。
GFM_VL = struct();
% 该组参数针对 t=0.5 s 并网后的快速恢复目标整定；Kp 较大时并网
% 瞬间电流和调制应力会增加，后续应结合限流环节进一步优化。
GFM_VL.Kp = 0.013;
GFM_VL.Ki = 0.01;
GFM_VL.TargetBandwidthHz = 50;
GFM_VL.AchievedNominalCrossoverHz = 48.5975701821;
GFM_VL.CurrentToVoltageBandwidthRatio = 4;
GFM_VL.FeedbackVoltage = 'midpoint_voltage';
GFM_VL.InternalVoltageDefinition = 'midpoint_voltage';
GFM_VL.UseI2Feedforward = true;
GFM_VL.UseDQDecouplingInTuning = true;
GFM_VL.NominalPidtuneKp = 0.0128385673255;
GFM_VL.NominalPidtuneKi = 1.2267855989;
GFM_VL.NominalFullLCLMaxPoleReal = 8.69268950509;
GFM_VL.FullLCLMaxPoleReal = -0.100715885869;

%% 6. P-f 与 Q-E 下垂控制参数
GFM_Droop = struct();
GFM_Droop.f0 = 50;
GFM_Droop.w0 = 2*pi*GFM_Droop.f0;
GFM_Droop.theta0 = -pi/2;

% 初始电势值
GFM_Droop.E0_pu = 1.0;

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

% 并网初始阶段采用较窄的下垂输出限幅，抑制断路器闭合激发的 LCL 暂态。
% 超过该时刻后恢复正常下垂限幅，不改变正常运行范围。
GFM_Droop.StartupLimitDuration = 0.25;
GFM_Droop.StartupLimitEndTime = t_close + GFM_Droop.StartupLimitDuration;
GFM_Droop.Startup_f_min = 49.98;
GFM_Droop.Startup_f_max = 50.02;
GFM_Droop.Startup_w_min = 2*pi*GFM_Droop.Startup_f_min;
GFM_Droop.Startup_w_max = 2*pi*GFM_Droop.Startup_f_max;
GFM_Droop.Startup_E_min_pu = 0.998;
GFM_Droop.Startup_E_max_pu = 1.002;

%% 7. 虚拟阻抗限流参数
% 该节参数应与系统级代码generate_multiple_snapshot_default_params.m中GFM_Modules.Electrical的口径对齐。
GFM_VI = struct();

% 是否启用虚拟阻抗限流
GFM_VI.Enable = true;

% 与系统级规划模型对齐的设备基准参数
GFM_VI.I_Post_Multiplier = 3;
GFM_VI.X_res_device_pu   = 0.04;
GFM_VI.X_vir_device_pu   = 1/GFM_VI.I_Post_Multiplier ...
                         - GFM_VI.X_res_device_pu;
GFM_VI.R_vir_device_pu   = 0;

% 平滑投入区间：接近系统级故障后电流倍数时投入
GFM_VI.I_start_pu = 0.9*GFM_VI.I_Post_Multiplier;
GFM_VI.I_full_pu  = GFM_VI.I_Post_Multiplier;

% 当前模型的Park变换输出为峰值dq电流，因此采用峰值电流基准。
GFM_VI.CurrentBaseType = 'peak_dq';
GFM_VI.I_base_used = I_base_peak;

% 激活系数滤波
GFM_VI.alpha_lpf_fc = 200;
GFM_VI.alpha_lpf_wc = 2*pi*GFM_VI.alpha_lpf_fc;

% 基准阻抗。V_base 为线电压有效值基准，S_base 为三相容量基准。
GFM_VI.Z_base = V_base^2/S_base;

% 换算为 SI 阻抗，用于v_vi = Z_vi*i2
GFM_VI.R_vir_max = GFM_VI.R_vir_device_pu*GFM_VI.Z_base;
GFM_VI.X_vir_max = GFM_VI.X_vir_device_pu*GFM_VI.Z_base;

% 调试与日志
GFM_VI.LogSignals = true;

%% 8. 参数一致性检查
assert(V_base > 0 && S_base > 0 && V_in > 0, ...
    'Base values and dc-link voltage must be positive.');
assert(L1 > 0 && L2 > 0 && Cf > 0, ...
    'LCL inductances and capacitance must be positive.');
assert(GFM_CL.Kp > 0 && GFM_CL.Ki > 0, ...
    'GFM current-loop PI gains must be positive.');
assert(GFM_VL.Kp > 0 && GFM_VL.Ki > 0, ...
    'GFM voltage-loop PI gains must be positive.');
assert(strcmp(GFM_CL.VoltageFeedforwardMode, 'midpoint_voltage'), ...
    'The selected GFM version requires midpoint-voltage feedforward.');
assert(abs(GFM_Droop.mp-2*pi) < 1e-12, ...
    'The configured 2%% P-f droop slope must equal 2*pi rad/s per p.u.');
assert(GFM_Droop.StartupLimitEndTime > t_close, ...
    'The startup droop-limit end time must be later than t_close.');
assert(GFM_Droop.Startup_f_min < GFM_Droop.Startup_f_max && ...
    GFM_Droop.f_min <= GFM_Droop.Startup_f_min && ...
    GFM_Droop.Startup_f_max <= GFM_Droop.f_max, ...
    'The startup frequency limits must be inside the normal limits.');
assert(GFM_Droop.Startup_E_min_pu < GFM_Droop.Startup_E_max_pu && ...
    GFM_Droop.E_min_pu <= GFM_Droop.Startup_E_min_pu && ...
    GFM_Droop.Startup_E_max_pu <= GFM_Droop.E_max_pu, ...
    'The startup voltage limits must be inside the normal limits.');
assert(GFM_VI.X_vir_device_pu > 0, ...
    'Virtual reactance must be positive.');
assert(abs(GFM_VI.X_vir_device_pu - ...
    (1/GFM_VI.I_Post_Multiplier - GFM_VI.X_res_device_pu)) < 1e-12, ...
    'GFM_VI.X_vir_device_pu is inconsistent with the system-level parameter formula.');
assert(GFM_VI.I_start_pu < GFM_VI.I_full_pu, ...
    'Virtual impedance activation interval is invalid.');
assert(strcmp(GFM_VI.CurrentBaseType, 'peak_dq'), ...
    'The virtual-impedance current base must match the peak dq current model.');
assert(GFM_VI.I_base_used > 0, ...
    'The virtual-impedance current base must be positive.');
