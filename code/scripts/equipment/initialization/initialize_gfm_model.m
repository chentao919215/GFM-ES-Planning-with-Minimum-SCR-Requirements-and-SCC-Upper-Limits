%% GFM-ES模型参数初始化。
% 参数输入、派生量、检查及工作区映射集中在本脚本。
% 可直接运行，也可由验证函数调用；不清理调用方工作区。
Project_Root = find_project_root(mfilename('fullpath'));

% 构网型变流器模型参数
% 本脚本负责把参数源映射为 Grid_Forming_Inverters.slx 所需的工作区变量。
% 原始物理参数与设计输入在get_gfm_parameter_inputs.m中维护；
% 系统级 GFM 电气参数应优先修改 generate_multiple_snapshot_default_params.m；
% 再运行该脚本生成 multiple_snapshot_default_params.json。
% 本脚本先派生实际L2，再调用整定函数计算Ki、校核并发布模型参数。

%% 0. 外部继承参数（唯一入口）
% get_gfm_parameter_inputs.m 返回分组结构体，不直接写入基础工作区。
% Base/Filter/Grid/Simulation为原始输入，CurrentLoopDesign/VoltageLoopDesign
% 和Droop为设计输入；Electrical来自系统级JSON。此时尚未计算PI。
GFM_Inherited = get_gfm_parameter_inputs(Project_Root);
GFM_Parameter_Source = GFM_Inherited.Source;

%% 1. 基准值与直流侧参数（由外部参数源映射）
% V_base 为三相线电压有效值基准，S_base 为三相视在功率基准。
% V_base_phase 是相电压峰值基准，适配模型中采用峰值量的相量表示。
V_base = GFM_Inherited.Base.V_base;
S_base = GFM_Inherited.Base.S_base;
V_base_phase = sqrt(2/3)*V_base;
% I_base_rms 为线电流有效值基准；I_base_peak 为 dq 峰值电流基准。
I_base_rms = S_base/(sqrt(3)*V_base);
% Z_base 以线电压有效值和三相容量定义，用于标幺阻抗与 SI 阻抗之间的换算。
% V_in 为变流器直流侧电压，供调制器及直流侧模型使用。
Z_base = V_base^2/S_base;
I_base_peak = sqrt(2)*I_base_rms;
V_in = GFM_Inherited.Base.V_in;

%% 2. LCL 滤波器参数（由外部参数源映射或正式电气参数派生）
% L1、R_L1 为逆变器侧电感及其串联电阻；Cf、R_C 为滤波电容及
% 电容支路串联阻尼电阻；L2、R_L2 为网侧电感及其串联电阻。
% 这些参数同时用于模型 LCL 网络和控制器 PI 参数整定的对象描述。
L1 = GFM_Inherited.Filter.L1;
R_L1 = GFM_Inherited.Filter.R_L1;
Cf = GFM_Inherited.Filter.Cf;
R_C = GFM_Inherited.Filter.R_C;
% 当前端口验证口径令 Q-E 下垂斜率 nq=0，并由物理 L2 单独表示正式
% 设备基准残余电抗 X_res_device_pu。L2 因此由唯一的系统级电气参数派生，
% 避免在参数脚本中另行硬编码 0.10 p.u.。
L2 = GFM_Inherited.Electrical.X_res_device_pu*Z_base ...
    /(2*pi*GFM_Inherited.Droop.f0);
R_L2 = GFM_Inherited.Filter.R_L2;
GFM_Inherited.Filter.L2 = L2; % 整定和参数快照使用同一派生值，不保留0.6 mH副本。

%% 3. 电网、开关与仿真参数
% Vg 为电网线电压有效值，默认与模型电压基准一致。
% f 为额定频率，fs 为开关频率，i2_lpf_fc 为输出电流测量低通滤波器
% 截止频率；这些频率量均以 Hz 表示。
Vg = V_base;
f = GFM_Inherited.Grid.f;
fs = GFM_Inherited.Grid.fs;
i2_lpf_fc = GFM_Inherited.Grid.i2_lpf_fc;
X_L2_device_pu = 2*pi*f*L2/Z_base;
SCR = GFM_Inherited.Grid.SCR;
MISCR = GFM_Inherited.Grid.MISCR;
Grid_X_R = GFM_Inherited.Grid.Grid_X_R;
% SCR 为短路比，MISCR 为修正短路比；Grid_X_R 为电网等值阻抗的 X/R 比。
% Zg 按 SCR 换算电网等值阻抗，Rg 和 Lg 分别为电网等值电阻和电感。
Zg = Vg^2/(S_base*SCR);
Rg = Zg/sqrt(1 + Grid_X_R^2);
Lg = Grid_X_R*Rg/(2*pi*f);
Lij = (SCR/MISCR-1)*Lg;
t_close = GFM_Inherited.Grid.t_close;

% Lij 为并网联络支路电感，t_close 为并网开关的闭合时刻。
% t_stop 为完整仿真时长，validation_stop_time 为参数验证用仿真时长。
GFM_Sim = GFM_Inherited.Simulation;

%% 4. 可编程三相电源与 Case A/B/C 电压工况
% Case A/B/C 是同一次仿真中的三个连续时段，而不是三个互斥算例。
% SourceVoltage_pu 是有限电网阻抗之后的外部电源幅值指令。
% PCC电压由网络和变流器共同决定，验收必须使用实测PCC电压。
% TransitionTime_s 定义相邻时段之间的线性电压过渡时间。
GFM_GridSource = struct();
GFM_GridSource.TransitionTime_s = 0.005;

% Case A：起始较浅电压工况。
GFM_GridSource.CaseA.SourceVoltage_pu = 1.00;
GFM_GridSource.CaseA.StartTime_s = 0.0;
GFM_GridSource.CaseA.Duration_s = 4.0;
GFM_GridSource.CaseA.EndTime_s = GFM_GridSource.CaseA.StartTime_s ...
    + GFM_GridSource.CaseA.Duration_s;

% Case B：深跌落工况，在当前有限电网阻抗下触发虚拟阻抗限流。
GFM_GridSource.CaseB.SourceVoltage_pu = 0.30;
GFM_GridSource.CaseB.StartTime_s = GFM_GridSource.CaseA.EndTime_s;
GFM_GridSource.CaseB.Duration_s = 4.0;
GFM_GridSource.CaseB.EndTime_s = GFM_GridSource.CaseB.StartTime_s ...
    + GFM_GridSource.CaseB.Duration_s;

% Case C：最后进入电压恢复工况。
GFM_GridSource.CaseC.SourceVoltage_pu = GFM_GridSource.CaseA.SourceVoltage_pu;
GFM_GridSource.CaseC.StartTime_s = GFM_GridSource.CaseB.EndTime_s;
GFM_GridSource.CaseC.Duration_s = 4.0;
GFM_GridSource.CaseC.EndTime_s = GFM_GridSource.CaseC.StartTime_s ...
    + GFM_GridSource.CaseC.Duration_s;

% 三段持续时间共同决定一次完整时序算例的仿真终止时刻。
GFM_GridSource.TotalDuration_s = GFM_GridSource.CaseC.EndTime_s;
GFM_Sim.t_stop = GFM_GridSource.TotalDuration_s;
GFM_GridSource.Amplitudes_pu = [ ...
    GFM_GridSource.CaseA.SourceVoltage_pu, ...
    GFM_GridSource.CaseA.SourceVoltage_pu, ...
    GFM_GridSource.CaseB.SourceVoltage_pu, ...
    GFM_GridSource.CaseB.SourceVoltage_pu, ...
    GFM_GridSource.CaseC.SourceVoltage_pu, ...
    GFM_GridSource.CaseC.SourceVoltage_pu];
GFM_GridSource.TimeValues_s = [ ...
    GFM_GridSource.CaseA.StartTime_s, ...
    GFM_GridSource.CaseB.StartTime_s, ...
    GFM_GridSource.CaseB.StartTime_s ...
    + GFM_GridSource.TransitionTime_s, ...
    GFM_GridSource.CaseC.StartTime_s, ...
    GFM_GridSource.CaseC.StartTime_s ...
    + GFM_GridSource.TransitionTime_s, ...
    GFM_GridSource.CaseC.EndTime_s];

% 顶层Three-Phase Grid Impedance位于PCC测量点与外部电源之间。
% 该电网支路不属于设备内部L2，端口理论仍以实测PCC电压为输入。
GFM_GridImpedance = struct();
GFM_GridImpedance.R_ohm = Rg;
GFM_GridImpedance.L_H = Lg;
GFM_GridImpedance.R_pu = GFM_GridImpedance.R_ohm/Z_base;
GFM_GridImpedance.X_pu = 2*pi*f*GFM_GridImpedance.L_H/Z_base;

%% 5. 逆变器侧 i1 电流内环参数（给定Kp和目标，计算Ki并校核）
% GFM_CL 为逆变器侧 i1_d/i1_q 电流内环 PI 控制器的最终整定结果。
% 具体整定口径和来源脚本记录在 GFM_Parameter_Source 中。
GFM_LCL = struct('L1', L1, 'R_L1', R_L1, 'Cf', Cf, 'R_C', R_C, ...
    'L2', L2, 'R_L2', R_L2, 'f', f);
GFM_CL = tune_gfm_current_loop(GFM_LCL, GFM_Inherited.CurrentLoopDesign);
% R_equivalent 为电流环整定时采用的等效串联电阻；当前采用中点电压前馈，
% 因此取逆变器侧电阻 R_L1。PWMDelay 采用半个开关周期的平均模型延时。
GFM_CL.R_equivalent = R_L1;
GFM_CL.PWMDelay = 0.5/fs;
GFM_Inherited.CurrentLoop = GFM_CL;

%% 6. LCL中点电压 vMid 外环参数（计算Ki并校核实际LCL闭环）
% 控制器将 vMid = vC + R_C*(i1-i2) 作为 GFM 内部受控电势。
% GFM_VL 为 vMid_d/vMid_q 电压外环的最终整定结果；电压环输出为 i1 参考值。
% UseI2Feedforward 表示是否补偿电容电流平衡，UseDQDecouplingInTuning
% 表示整定模型是否补偿同步 dq 坐标系中的电压交叉耦合。
GFM_VL = tune_gfm_voltage_loop(GFM_LCL, GFM_CL, GFM_Inherited.VoltageLoopDesign);
GFM_Inherited.VoltageLoop = GFM_VL;

%% 7. P-f 与 Q-E 下垂控制参数
% GFM_Droop 保存有功-频率（P-f）和无功-电压（Q-E）下垂控制的输入及限幅。
% f0、theta0、E0_pu 为额定频率、初始相角和初始内部电势；Pref_pu、Qref_pu
% 为有功和无功标幺参考值。
GFM_Droop = GFM_Inherited.Droop;
% Q_pu 采用“GFM 向电网注入无功为正”的符号约定；Q-E 下垂为
% E_ref = E0 - nq*(Q_pu - Qref_pu)，确保无功注入增加时 E_ref 下降。
GFM_Droop.QSignConvention = 'converter_injection_positive';
GFM_Droop.w0 = 2*pi*GFM_Droop.f0;
GFM_Droop.mp_hz = GFM_Droop.f0*GFM_Droop.Rf;
% mp_hz 为 P-f 下垂频率斜率，mp 为对应的角频率斜率。
% Rf=0.02 表示 2%% P-f 下垂；因此额定工况下 mp=2*pi rad/s/p.u.
GFM_Droop.mp = 2*pi*GFM_Droop.mp_hz;
% 当前端口验证采用固定内电势口径：Q-E 下垂斜率置零，残余电抗完全由
% 物理 L2 提供。这样不会再把 L2 电抗与 Q-E 下垂重复折算为 X_res。
GFM_Droop.nq = 0;
% PQ_lpf_fc/PQ_lpf_wc 为 PCC 侧有功、无功测量的一阶低通滤波器参数。
% f_min/f_max 和 E_min_pu/E_max_pu 为正常运行时的频率、电势限幅。
% StartupLimitDuration 及其对应限幅用于并网初始暂态抑制，超过
% StartupLimitEndTime 后恢复正常下垂限幅。
GFM_Droop.PQ_lpf_wc = 2*pi*GFM_Droop.PQ_lpf_fc;
GFM_Droop.w_min = 2*pi*GFM_Droop.f_min;
GFM_Droop.w_max = 2*pi*GFM_Droop.f_max;
GFM_Droop.StartupLimitEndTime = ...
    t_close + GFM_Droop.StartupLimitDuration;
GFM_Droop.Startup_w_min = 2*pi*GFM_Droop.Startup_f_min;
GFM_Droop.Startup_w_max = 2*pi*GFM_Droop.Startup_f_max;

%% 8. 虚拟阻抗限流参数
% 系统级参数中的 X_GFM_Res/X_GFM_Vir 是系统基准值；当前 Simulink
% 电流与虚拟阻抗模块采用设备基准，因此只使用继承入口完成后的设备基准量。
% Electrical 中同时保留系统基准值，仅用于追溯和一致性检查，不直接作为
% v_vi = Z_vi*i2 中的阻抗数值。
% Enable 控制虚拟阻抗限流功能；Mode 指定电流触发、PCC 电压恢复退出的
% 两状态锁存实现。
GFM_VI = struct();
GFM_VI.Enable = true;
GFM_VI.Mode = 'latched_voltage_release_rearm';
GFM_VI.I_Post_Multiplier = GFM_Inherited.Electrical.I_Post_Multiplier;
GFM_VI.X_res_device_pu = GFM_Inherited.Electrical.X_res_device_pu;
% I_Post_Multiplier 是系统级定义的投入后设计电流倍数；X_res_device_pu
% 是设备基准残余电抗。投入后的附加虚拟电抗按总等效电抗关系派生：
% X_res_device_pu + X_vir_device_pu = 1/I_Post_Multiplier。
GFM_VI.X_vir_device_pu = ...
    1/GFM_VI.I_Post_Multiplier - GFM_VI.X_res_device_pu;
GFM_VI.X_GFM_Res_system_pu = ...
    GFM_Inherited.Electrical.X_GFM_Res_system_pu;
GFM_VI.X_GFM_Vir_system_pu = ...
    GFM_Inherited.Electrical.X_GFM_Vir_system_pu;

% 以下两个字段保留系统基准值，便于核对 generate_multiple_snapshot_default_params.m。
% 现有模型为纯虚拟电抗；不额外引入虚拟电阻。
GFM_VI.R_vir_device_pu = 0;

% 达到电流触发阈值且 PCC 电压低于恢复边界后，虚拟阻抗投入并锁存；
% 投入后不因实际电流下降至触发阈值以下而退出。只有当 PCC 电压达到
% U_boundary_pu 及以上并连续保持 ReleaseConfirmTime 后才退出；确认期间
% 若电压重新低于边界，恢复计时立即清零。当前不增加电压滞环。
% I_Post_Multiplier 表示投入后的设计电流倍数，不自动等同于触发阈值；
% 当前模型配置将两者设为同一数值，后续可单独调整该触发字段。
GFM_VI.I_switch_threshold_pu = GFM_VI.I_Post_Multiplier;

% 按简化端口模型 Ub = E0 - Xres*Ilim 派生 PCC 电压恢复边界。
% Simulink 投切逻辑直接引用该字段，不在 Block 内重复写入数值。
GFM_VI.U_boundary_pu = GFM_Droop.E0_pu ...
    - GFM_VI.X_res_device_pu*GFM_VI.I_switch_threshold_pu;

% PCC 电压恢复退出的连续成立确认时间 [s]。该时间只作用于 ON -> OFF
% 复位支路，不改变电流触发阈值、U_boundary_pu 或虚拟阻抗投入幅值。
GFM_VI.ReleaseConfirmTime = 0.005;

% 每次确认退出后，OFF -> ON 重新触发先进入未武装状态。只有在 OFF 状态下
% PCC 电压达到 U_boundary_pu 及以上且输出电流低于触发阈值，并连续保持
% RearmConfirmTime 后才重新允许下一次触发。首次故障采用初始已武装状态，
% 因而不增加首次限流投入延迟。
% 默认值取 5 ms；正式验证脚本会针对当前外部电源跌落工况重新扫描。
GFM_VI.RearmConfirmTime = GFM_VI.ReleaseConfirmTime;

% 当前模型的 Park 变换输出为峰值 dq 电流，因此采用峰值电流基准。
% I_base_used 必须与电流测量信号的峰值/有效值口径一致；当前取 I_base_peak。
GFM_VI.CurrentBaseType = 'peak_dq';
GFM_VI.I_base_used = I_base_peak;
GFM_VI.Z_base = Z_base;

% 虚拟阻抗的设备基准值乘以 Z_base 后转换为 SI 单位，用于
% v_vi = Z_vi*i2。其中 R_vir_max 当前为 0，X_vir_max 为投入后的附加电抗。
GFM_VI.R_vir_max = GFM_VI.R_vir_device_pu*GFM_VI.Z_base;
GFM_VI.X_vir_max = GFM_VI.X_vir_device_pu*GFM_VI.Z_base;
GFM_VI.LogSignals = true;

%% 9. 参数一致性检查
% 系统级JSON的维度、基准换算及总电抗关系已在参数读取入口检查；
% 此处检查模型输入范围、时序及控制/端口理论所需的约束，不重复校验赋值。
% 基准、LCL、电网及控制器参数。
Positive_Parameters = [V_base, S_base, V_in, L1, L2, Cf, f, fs, ...
    i2_lpf_fc, SCR, Grid_X_R, Lg, GFM_CL.Kp, GFM_CL.Ki, ...
    GFM_VL.Kp, GFM_VL.Ki, GFM_Droop.mp];
Nonnegative_Parameters = [R_L1, R_L2, R_C, Rg, t_close];
assert(all(isfinite(Positive_Parameters) & Positive_Parameters > 0) && ...
    all(isfinite(Nonnegative_Parameters) & Nonnegative_Parameters >= 0), ...
    'GFMInitialization:InvalidParameters', ...
    'GFM基准、滤波器、电网或控制器参数超出有效范围。');

% 电源指令有效且时间序列严格递增；连续三段和终止时刻已由前文派生。
Source_Cases = [GFM_GridSource.CaseA, ...
    GFM_GridSource.CaseB, GFM_GridSource.CaseC];
Source_Voltage_Targets = [Source_Cases.SourceVoltage_pu];
Source_Durations = [Source_Cases.Duration_s];
assert(all(isfinite(Source_Voltage_Targets) & ...
    Source_Voltage_Targets > 0 & Source_Voltage_Targets <= 1.2), ...
    'GFMInitialization:InvalidSourceVoltage', ...
    'Case A/B/C外部电源幅值指令须位于(0, 1.2] p.u.，不代表实测PCC电压。');
Source_Times = GFM_GridSource.TimeValues_s;
Transition_Time = GFM_GridSource.TransitionTime_s;
assert(isfinite(Transition_Time) && Transition_Time > 0 && ...
    all(isfinite(Source_Durations) & Source_Durations >= Transition_Time) && ...
    all(isfinite(Source_Times) & Source_Times >= 0) && all(diff(Source_Times) > 0), ...
    'GFMInitialization:InvalidSourceTiming', '电源过渡时间、时段长度或时序无效。');

% 控制方式与固定内电势端口理论一致，启动限幅位于正常限幅之内。
assert(strcmp(GFM_CL.VoltageFeedforwardMode, 'midpoint_voltage'), ...
    'The selected GFM version requires midpoint-voltage feedforward.');
assert(abs(f-GFM_Droop.f0) < 1e-12, ...
    'Grid frequency and GFM droop nominal frequency must match.');
assert(abs(GFM_Droop.nq) < 1e-12, ...
    'The fixed-internal-voltage port model requires GFM_Droop.nq = 0.');
Droop_Limits = [GFM_Droop.f_min, GFM_Droop.Startup_f_min, ...
    GFM_Droop.Startup_f_max, GFM_Droop.f_max; ...
    GFM_Droop.E_min_pu, GFM_Droop.Startup_E_min_pu, ...
    GFM_Droop.Startup_E_max_pu, GFM_Droop.E_max_pu];
assert(isfinite(GFM_Droop.StartupLimitDuration) && ...
    GFM_Droop.StartupLimitDuration > 0 && ...
    all(isfinite(Droop_Limits) & Droop_Limits > 0, 'all') && ...
    all(Droop_Limits(:, 1) <= Droop_Limits(:, 2)) && ...
    all(Droop_Limits(:, 2) < Droop_Limits(:, 3)) && ...
    all(Droop_Limits(:, 3) <= Droop_Limits(:, 4)), ...
    'GFMInitialization:InvalidDroopLimits', '启动下垂限幅须有序且位于正常限幅之内。');

% 保留物理L2与正式残余电抗的接口核对，限流参数采用dq峰值电流基准。
assert(abs(X_L2_device_pu-GFM_VI.X_res_device_pu) < 1e-12, ...
    'Physical L2 must provide the complete device-base residual reactance.');
assert(isfinite(GFM_VI.I_switch_threshold_pu) && GFM_VI.I_switch_threshold_pu > 0 && ...
    GFM_VI.I_switch_threshold_pu <= GFM_VI.I_Post_Multiplier, ...
    'The virtual-impedance current trigger is invalid.');
assert(isfinite(GFM_VI.U_boundary_pu) && ...
    GFM_VI.U_boundary_pu > 0 && ...
    GFM_VI.U_boundary_pu <= GFM_Droop.E0_pu && ...
    GFM_VI.U_boundary_pu <= 1.2, ...
    'GFM_VI.U_boundary_pu is outside the reasonable per-unit voltage range.');
Confirm_Times = [GFM_VI.ReleaseConfirmTime, GFM_VI.RearmConfirmTime];
assert(all(isfinite(Confirm_Times) & Confirm_Times > 0 & Confirm_Times <= 0.1), ...
    'GFMInitialization:InvalidConfirmTime', '退出和重新武装确认时间须位于(0, 0.1] s。');
assert(strcmp(GFM_VI.CurrentBaseType, 'peak_dq') && ...
    isfinite(GFM_VI.I_base_used) && GFM_VI.I_base_used > 0 && ...
    abs(GFM_VI.I_base_used/I_base_rms-sqrt(2)) < 1e-12, ...
    'The virtual-impedance current base must match the peak dq current model.');

%% 10. 发布模型参数
% 显式导出模型及验证所需参数，检查用临时量不登记到回调参数清单。
% 函数内运行本脚本时同步写入基础工作区；回调据设备族和清单保留工况覆盖。
Equipment_Parameters = struct( ...
    'Cf', Cf, 'GFM_CL', GFM_CL, 'GFM_Droop', GFM_Droop, 'GFM_GridSource', GFM_GridSource, ...
    'GFM_Inherited', GFM_Inherited, 'GFM_GridImpedance', GFM_GridImpedance, ...
    'GFM_Parameter_Source', GFM_Parameter_Source, 'GFM_Sim', GFM_Sim, 'GFM_VI', GFM_VI, ...
    'GFM_VL', GFM_VL, 'Grid_X_R', Grid_X_R, 'I_base_peak', I_base_peak, ...
    'I_base_rms', I_base_rms, 'L1', L1, 'L2', L2, 'Lg', Lg, 'Lij', Lij, 'MISCR', MISCR, ...
    'R_C', R_C, 'R_L1', R_L1, 'R_L2', R_L2, 'Rg', Rg, 'SCR', SCR, 'S_base', S_base, ...
    'V_base', V_base, 'V_base_phase', V_base_phase, 'V_in', V_in, 'Vg', Vg, ...
    'X_L2_device_pu', X_L2_device_pu, 'Z_base', Z_base, 'Zg', Zg, 'f', f, 'fs', fs, ...
    'i2_lpf_fc', i2_lpf_fc, 't_close', t_close);
Equipment_Parameter_Names = fieldnames(Equipment_Parameters);
for Equipment_Parameter_Index = 1:numel(Equipment_Parameter_Names)
    Equipment_Parameter_Name = Equipment_Parameter_Names{Equipment_Parameter_Index};
    assignin('base', Equipment_Parameter_Name, ...
        Equipment_Parameters.(Equipment_Parameter_Name));
end
assignin('base', 'Equipment_Parameter_Family', 'gfm');
assignin('base', 'Equipment_Parameter_Names', Equipment_Parameter_Names);
