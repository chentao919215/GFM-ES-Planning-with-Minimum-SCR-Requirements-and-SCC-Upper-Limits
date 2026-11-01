%% GFL-WG模型参数初始化。
% 参数输入、派生量、检查及工作区映射集中在本脚本。
% 可直接运行，也可由验证函数调用；不清理调用方工作区。
% 本脚本显式给出95 Hz目标与Kp；整定函数不提供默认参数。

%% 1. 参数设置
% 基准值
V_base = 38.5e3;
S_base = 60e6;

% 直流侧输入电压
V_in = 120e3;

% 滤波器参数
L1 = 1e-3;
R_L1 = 10;
Cf = 40e-6;
R_C = 3;
L2 = 600e-6;
R_L2 = 0.05;

% i2低通滤波器
i2_lpf_fc = 300;

% 网侧参数
Vg = V_base;
f = 50;
SCR = 3;
Zg = Vg^2/(S_base*SCR);
% 默认采用纯感性电网；模型通过三相电源内部阻抗表示并网支路。
% SCR扫描启用该阻抗，端口LVRT校验临时关闭该阻抗。
Rg = 0;
Lg = Zg/(2*pi*f);
t_close = 0;

% PLL参数
PLL = [];
PLL.Kp = 90;
PLL.Ki = 1200;
PLL.Kd = 0;

% 电流环内环PI参数
GFL_LCL = struct( ...
    'L1', L1, 'R_L1', R_L1, 'L2', L2, 'R_L2', R_L2, ...
    'Cf', Cf, 'R_C', R_C, 'f', f);
GFL_Current_Design = struct('TargetBandwidthHz', 95, 'Kp', 5, ...
    'MinimumPhaseMarginDeg', 35, 'ShowRGAPlots', false, ...
    'ShowValidationPlots', false, 'Verbose', false);
CL = tune_gfl_current_loop(GFL_LCL, GFL_Current_Design);

% PWM波频率
fs = 10e3;

% 功率外环参数
PQ = [];
PQ.Pref = S_base/2;
PQ.Qref = 0;
PQ.step_time_P = 0.15;
PQ.step_time_Q = 0.2;
PQ.v_lpf_fc = 200;
PQ.vdq_eps = (0.05*sqrt(2/3)*Vg)^2;

% 功率外环电流参考值选择
% 0: 使用原有功率外环输出；1: 使用手动电流参考值。
Manual_Current_Ref = 1;
Id_ref_manual = 0.8;                % 手动基准电流 / p.u.
Iq_ref_manual = 0;                  % 手动基准电流 / p.u.

%% 2. GFL LVRT 与四象限无功优先限流参数
% 变流器电流基准与额定电流均采用 p.u.；模型内部电流信号为 A。
I_N = 1.0;                         % 额定电流 / p.u.
I_limit = 1.2;                     % 电流限值 / p.u.
V_LVRT_max = 0.90;                 % LVRT 启动电压阈值 / p.u.
V_LVRT_min = 0.20;                 % 附加无功电流饱和电压阈值 / p.u.
K_q_LVRT = 1.5;                    % LVRT 无功电流斜率 / (p.u./p.u.)
Delta_Iq_LVRT_max = K_q_LVRT * ...
    (V_LVRT_max - V_LVRT_min) * I_N; % 最大附加无功电流 / p.u.

% abc/dq变换输出峰值量；手动参考及LVRT限流均使用峰值电流基准。
% 三相实测有效值电流则使用I_base_rms，二者对应相同的设备标幺值。
I_base_rms = S_base/(sqrt(3)*V_base);
I_base_peak = sqrt(2)*I_base_rms;
I_base = I_base_peak; % 保留模型现有变量接口，明确其为dq峰值基准。
V_base_phase = sqrt(2/3)*V_base;

%% 3. 发布模型参数
% 显式列出需要导出的参数；函数内运行本脚本时，也将其写入基础工作区。
% 设备族和变量清单供模型回调判断是否需要初始化，保留同族工况覆盖。
Equipment_Parameters = struct( ...
    'CL', CL, 'Cf', Cf, 'Delta_Iq_LVRT_max', Delta_Iq_LVRT_max, 'I_N', I_N, 'I_base', I_base, ...
    'I_base_rms', I_base_rms, 'I_base_peak', I_base_peak, ...
    'I_limit', I_limit, 'Id_ref_manual', Id_ref_manual, 'Iq_ref_manual', Iq_ref_manual, ...
    'K_q_LVRT', K_q_LVRT, 'L1', L1, 'L2', L2, 'Lg', Lg, 'Rg', Rg, ...
    'Manual_Current_Ref', Manual_Current_Ref, 'PLL', PLL, 'PQ', PQ, 'R_C', R_C, 'R_L1', R_L1, ...
    'R_L2', R_L2, 'SCR', SCR, 'S_base', S_base, 'V_LVRT_max', V_LVRT_max, ...
    'V_LVRT_min', V_LVRT_min, 'V_base', V_base, 'V_base_phase', V_base_phase, 'V_in', V_in, ...
    'Vg', Vg, 'Zg', Zg, 'f', f, 'fs', fs, 'i2_lpf_fc', i2_lpf_fc, 't_close', t_close);
Equipment_Parameter_Names = fieldnames(Equipment_Parameters);
for Equipment_Parameter_Index = 1:numel(Equipment_Parameter_Names)
    Equipment_Parameter_Name = Equipment_Parameter_Names{Equipment_Parameter_Index};
    assignin('base', Equipment_Parameter_Name, ...
        Equipment_Parameters.(Equipment_Parameter_Name));
end
assignin('base', 'Equipment_Parameter_Family', 'gfl');
assignin('base', 'Equipment_Parameter_Names', Equipment_Parameter_Names);
