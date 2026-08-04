%% Report04_Section5_3_Case_Study
% 《报告04》第5.3节：三节点混合电源系统短路电流理论计算与仿真对比
%
% 本脚本统一采用系统三相基准：
%   S_B = 100 MVA，V_B = 38.5 kV（线电压 RMS），
%   I_B = S_B/(sqrt(3)*V_B)，Z_B = V_B^2/S_B。
% 电压相量按相电压 RMS 表示；电流相量按系统电流基准表示。
%
% 运行方式：在 MATLAB 当前目录或任意目录执行本脚本即可。
% 脚本会加载参数、更新并运行 Simulink 模型，最后输出表5-5数据。

clearvars -except ans;
clc;

scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(fileparts(fileparts(fileparts(scriptDir)))));
paramDir = fullfile(projectRoot, 'code', 'scripts', 'equipment', 'Others');
functionDir = fullfile(projectRoot, 'code', 'functions', 'equipment');
modelFile = fullfile(projectRoot, 'simulink', 'models', ...
    'Grid_Following_Inverter_Generator.slx');
modelName = 'Grid_Following_Inverter_Generator';

addpath(functionDir);
addpath(paramDir);
run(fullfile(paramDir, 'Invert_Generator_Parameters.m'));

fprintf('\n===== 报告04 第5.3节：理论计算与仿真对比 =====\n');
fprintf('统一标幺基准：S_B = %.6g VA，V_B = %.6g V（线电压 RMS），', S_B, V_B_LL);
fprintf('I_B = %.9g A，Z_B = %.9g ohm。\n', I_B, Z_B);
fprintf('仿真提取时间窗：%.6g s 至 %.6g s。\n', t_extract_start, t_extract_end);

%% 1. 三节点支路导纳与式(5.5)节点导纳矩阵
y12 = 1 / z12_pu;
y13 = 1 / z13_pu;
y23 = 1 / z23_pu;
yth = 1 / Zth_pu;

Y_line = [ y12+y13, -y12,      -y13;
          -y12,     y12+y23,  -y23;
          -y13,     -y23,     y13+y23+yth ];

Y_post_fault = Y_line;
Y_post_fault(3,3) = Y_post_fault(3,3) + 1/R_fault_pu;

% Y_report is the fault-free three-node network matrix used for report
% equations.  It deliberately excludes the numerical fault admittance 1/Rf.
Y_report = Y_line;

fprintf('\n[式(5.5)] 三节点网络导纳矩阵 Y_report（pu，不含1/Rf）:\n');
disp(Y_report);
fprintf('Y11 = %.9g %+.9gj, Y12 = %.9g %+.9gj, Y13 = %.9g %+.9gj\n', ...
    real(Y_line(1,1)), imag(Y_line(1,1)), real(Y_line(1,2)), imag(Y_line(1,2)), ...
    real(Y_line(1,3)), imag(Y_line(1,3)));
fprintf('Y21 = %.9g %+.9gj, Y22 = %.9g %+.9gj, Y23 = %.9g %+.9gj\n', ...
    real(Y_line(2,1)), imag(Y_line(2,1)), real(Y_line(2,2)), imag(Y_line(2,2)), ...
    real(Y_line(2,3)), imag(Y_line(2,3)));
fprintf('Y31 = %.9g %+.9gj, Y32 = %.9g %+.9gj, Y33 = %.9g %+.9gj\n', ...
    real(Y_line(3,1)), imag(Y_line(3,1)), real(Y_line(3,2)), imag(Y_line(3,2)), ...
    real(Y_line(3,3)), imag(Y_line(3,3)));
fprintf('故障支路：Yf = %.9g pu，故障后 Y(3,3) = %.9g %+.9gj pu。\n', ...
    1/R_fault_pu, real(Y_post_fault(3,3)), imag(Y_post_fault(3,3)));

%% 2. 同步发电机次暂态诺顿等值
Zg_pu = Z_dpp_pu;
Yg_pu = 1/Zg_pu;
Epp_operating_pu = E_double_pu_complex;
% The model's Internal Voltage E pu input is scalar and aligned with the
% simplified machine quadrature axis.  Use the same -90 deg cosine-phasor
% reference for the report Norton source; retain Epp_operating_pu for audit.
Epp_pu = E_internal_pu * exp(1j*deg2rad(machine_voltage_axis_phase_deg));
Jg_pu = Epp_pu/Zg_pu;

% 外部电网等值电压源接在节点3；参数脚本中的 grid_phase_deg 为电压源
% 正弦波相位。正弦波转换为余弦相量时需减去90度。
Egrid_theory_pu = abs(E_grid_pu_complex) * ...
    exp(1j*deg2rad(grid_phase_deg - 90));
Jgrid_pu = yth * Egrid_theory_pu;

Y_aug = Y_report;
Y_aug(1,1) = Y_aug(1,1) + Yg_pu;

fprintf('\n[同步发电机次暂态等值]\n');
fprintf('运行点计算 E'''' = %.9g %+.9gj pu；报告模型坐标 E'''' = %.9g %+.9gj pu。\n', ...
    real(Epp_operating_pu), imag(Epp_operating_pu), real(Epp_pu), imag(Epp_pu));
fprintf('|E''''| = %.9g pu，报告相角 = %.9g deg。\n', ...
    abs(Epp_pu), rad2deg(angle(Epp_pu)));
fprintf('Z'''' = %.9g %+.9gj pu，Yg = %.9g %+.9gj pu，Jg = %.9g %+.9gj pu。\n', ...
    real(Zg_pu), imag(Zg_pu), real(Yg_pu), imag(Yg_pu), ...
    real(Jg_pu), imag(Jg_pu));
fprintf('外部电网等值源：Egrid = %.9g %+.9gj pu，angle = %.9g deg。\n', ...
    real(Egrid_theory_pu), imag(Egrid_theory_pu), rad2deg(angle(Egrid_theory_pu)));

%% 3. GFL-LVRT 线性段受控电流源等值
% 采用第5.3节假设：
%   Id = Id_ref；
%   Iq = Iq_ref + Kq*(V_LVRT_max - |U2|)；
% 并限制在 LVRT 线性段内，不在理论方程中主动触发电流限幅。
% 这里的电流先按变流器额定电流基准计算，再换算到系统基准。
I2_ref_device_pu = Id_ref_manual + 1j*Iq_ref_manual;
I2_ref_system_pu = I2_ref_device_pu * gfl_to_system_current_pu;

% Apply the metallic three-phase fault as the boundary condition U3 = 0.
% Therefore only the first two nodal equations are solved for U1 and U2;
% the fault current is recovered from the node-3 current balance.
Y_fault_boundary = Y_aug(1:2,1:2);
U12_pu = Y_fault_boundary \ [Jg_pu; I2_ref_system_pu];
for k = 1:1000
    I2_device_pu = Id_ref_manual + 1j * ...
        (Iq_ref_manual + K_q_LVRT * (V_LVRT_max - abs(U12_pu(2))));
    I2_system_pu = I2_device_pu * gfl_to_system_current_pu;
    U12_next_pu = Y_fault_boundary \ [Jg_pu; I2_system_pu];
    if norm(U12_next_pu-U12_pu, inf) < 1e-12
        U12_pu = U12_next_pu;
        break;
    end
    U12_pu = U12_next_pu;
end
U_pu = [U12_pu; 0];
I2_device_pu = Id_ref_manual + 1j * ...
    (Iq_ref_manual + K_q_LVRT * (V_LVRT_max - abs(U_pu(2))));
I2_system_pu = I2_device_pu * gfl_to_system_current_pu;

I1_theory_pu = (Epp_pu - U_pu(1)) / Zg_pu;
I2_theory_pu = I2_system_pu;

% Node-3 current balance, all currents directed into the metallic fault:
% generator-side line contribution, GFL-side line contribution, and the
% external-grid contribution through Zth.  This is the reported I3^F.
I13_theory_pu = U_pu(1) / z13_pu;
I23_theory_pu = U_pu(2) / z23_pu;
Ith_theory_pu = Egrid_theory_pu / Zth_pu;
I3_balance_theory_pu = I13_theory_pu + I23_theory_pu + Ith_theory_pu;
I3_theory_pu = I3_balance_theory_pu;

fprintf('\n[GFL受控电流源等值]\n');
fprintf('I2,d = %.9g pu(system)，I2,q = %.9g pu(system)，', ...
    real(I2_theory_pu), imag(I2_theory_pu));
fprintf('|I2| = %.9g pu(system)，|I2| = %.9g pu(device)。\n', ...
    abs(I2_theory_pu), abs(I2_device_pu));
fprintf('理论迭代次数 = %d，|U2| = %.9g pu。\n', k, abs(U_pu(2)));

%% 4. 理论值（系统基准）
theory = struct();
theory.U1 = U_pu(1);
theory.U2 = U_pu(2);
theory.U3 = U_pu(3);
theory.I1 = I1_theory_pu;
theory.I2 = I2_theory_pu;
theory.I3 = I3_theory_pu;
theory.I13 = I13_theory_pu;
theory.I23 = I23_theory_pu;
theory.Ith = Ith_theory_pu;
theory.I3_balance = I3_balance_theory_pu;
theory.I2d = real(I2_theory_pu);
theory.I2q = imag(I2_theory_pu);

fprintf('\n[理论计算结果，pu(system)]\n');
fprintf('|U1^F| = %.9g，|U2^F| = %.9g，|U3^F| = %.9g\n', ...
    abs(theory.U1), abs(theory.U2), abs(theory.U3));
fprintf('|I1^F| = %.9g，|I2^F| = %.9g，|I3^F| = %.9g\n', ...
    abs(theory.I1), abs(theory.I2), abs(theory.I3));
fprintf('I2,d^F = %+.9g，I2,q^F = %+.9g\n', theory.I2d, theory.I2q);

%% 5. 运行 Simulink 并提取故障后基波正序量
simulationAvailable = false;
simOut = [];
simError = '';
if isfile(modelFile)
    try
        load_system(modelFile);
        configure_hybrid_report_signals(modelName);
        set_param(modelName, 'StopTime', num2str(t_stop, '%.15g'));
        set_param(modelName, 'SimulationCommand', 'update');
        simOut = sim(modelName, 'ReturnWorkspaceOutputs', 'on');
        simulationAvailable = true;
    catch ME
        simError = ME.message;
        warning('Report04:SimulationFailed', 'Simulink仿真未完成：%s', ME.message);
    end
else
    simError = sprintf('找不到模型文件：%s', modelFile);
    warning('%s', simError);
end

simulation = struct('U1',NaN,'U2',NaN,'I1',NaN,'I2',NaN,'I3',NaN, ...
    'I2d',NaN,'I2q',NaN,'I2d_device',NaN,'I2q_device',NaN, ...
    'I13',NaN,'I23',NaN,'Ith',NaN,'I3_balance',NaN,'Egrid_command',NaN, ...
    'branchDiagnosticsAvailable',false);
if simulationAvailable
    try
        simulation.U1 = positive_sequence_rms(get_signal(simOut, 'Report_Node1_Vabc'), ...
            t_extract_start, t_extract_end, f0) / V_B_phase_rms;
        simulation.I1 = positive_sequence_rms(get_signal(simOut, 'Report_Node1_Iabc'), ...
            t_extract_start, t_extract_end, f0) / I_B;
        simulation.U2 = positive_sequence_rms(get_signal(simOut, 'Report_Node2_Vabc'), ...
            t_extract_start, t_extract_end, f0) / V_B_phase_rms;
        simulation.I3 = positive_sequence_rms(get_signal(simOut, 'Report_Fault_Iabc'), ...
            t_extract_start, t_extract_end, f0) / I_B;
        % GridTh测量方向与注入节点3的电流方向相反。
        simulation.I13 = positive_sequence_rms(get_signal(simOut, 'Report_I13_abc'), ...
            t_extract_start, t_extract_end, f0) / I_B;
        simulation.I23 = positive_sequence_rms(get_signal(simOut, 'Report_I23_abc'), ...
            t_extract_start, t_extract_end, f0) / I_B;
        simulation.Ith = -positive_sequence_rms(get_signal(simOut, 'Report_Ith_abc'), ...
            t_extract_start, t_extract_end, f0) / I_B;
        simulation.I3_balance = simulation.I13 + simulation.I23 + simulation.Ith;
        simulation.Egrid_command = positive_sequence_rms_from_scalars( ...
            get_signal(simOut, 'Report_Grid_Command_A'), ...
            get_signal(simOut, 'Report_Grid_Command_B'), ...
            get_signal(simOut, 'Report_Grid_Command_C'), ...
            t_extract_start, t_extract_end, f0) / V_B_phase_rms;
        simulation.branchDiagnosticsAvailable = true;
        % 报告信号来自 GFL 控制器的电流量，模型内部单位为 A；
        % 先除以变流器额定电流基准，再换算到系统基准。
        simulation.I2d_device = mean_scalar_in_window( ...
            get_signal(simOut, 'Report_GFL_i2_d_pu'), t_extract_start, t_extract_end) / I_inv_base;
        simulation.I2q_device = mean_scalar_in_window( ...
            get_signal(simOut, 'Report_GFL_i2_q_pu'), t_extract_start, t_extract_end) / I_inv_base;
        simulation.I2d = simulation.I2d_device * gfl_to_system_current_pu;
        simulation.I2q = simulation.I2q_device * gfl_to_system_current_pu;
        simulation.I2 = hypot(simulation.I2d, simulation.I2q);
    catch ME
        simulationAvailable = false;
        simError = ME.message;
        warning('Report04:ExtractionFailed', '仿真结果提取未完成：%s', ME.message);
    end
end

if simulationAvailable
    fprintf('\n[电磁暂态仿真提取结果，pu(system)]\n');
    fprintf('|U1^F| = %.9g，|U2^F| = %.9g，|I1^F| = %.9g，|I2^F| = %.9g，|I3^F| = %.9g\n', ...
        abs(simulation.U1), abs(simulation.U2), abs(simulation.I1), ...
        abs(simulation.I2), abs(simulation.I3));
    fprintf('I2,d^F = %+.9g，I2,q^F = %+.9g（控制器输出原值：d=%+.9g，q=%+.9g A）。\n', ...
        simulation.I2d, simulation.I2q, simulation.I2d_device*I_inv_base, ...
        simulation.I2q_device*I_inv_base);
    if simulation.branchDiagnosticsAvailable
        fprintf('节点3支路电流（pu）：I13=%g，I23=%g，Ith=%g，KCL合计=%g，故障支路测量=%g。\n', ...
            abs(simulation.I13), abs(simulation.I23), abs(simulation.Ith), ...
            abs(simulation.I3_balance), abs(simulation.I3));
    else
        fprintf('节点3支路诊断信号不可用；当前仅使用故障支路总电流测量。\n');
    end
else
    fprintf('\n[电磁暂态仿真提取结果]\n未得到完整仿真值：%s\n', simError);
end

%% 6. 表5-5：理论值、仿真值、相对误差
rowNames = {'故障点短路电流 |I3^F|'; ...
    '同步发电机节点残余电压 |U1^F|'; ...
    '同步发电机故障电流 |I1^F|'; ...
    'GFL并网点残余电压 |U2^F|'; ...
    'GFL合成故障电流 |I2^F|'; ...
    'GFL d轴电流 I2d^F'; ...
    'GFL q轴电流 I2q^F'};
theoryValues = [abs(theory.I3); abs(theory.U1); abs(theory.I1); abs(theory.U2); ...
    abs(theory.I2); theory.I2d; theory.I2q];
simulationValues = [abs(simulation.I3); abs(simulation.U1); abs(simulation.I1); ...
    abs(simulation.U2); abs(simulation.I2); simulation.I2d; simulation.I2q];
relativeErrorPct = 100 * abs(simulationValues-theoryValues) ./ ...
    max(abs(theoryValues), eps);

table55 = table(theoryValues, simulationValues, relativeErrorPct, ...
    'VariableNames', {'Theory_pu_system','Simulation_pu_system','RelativeError_pct'}, ...
    'RowNames', rowNames);

fprintf('\n===== 表5-5 理论计算与仿真对比（pu，系统基准） =====\n');
disp(table55);

theoryNamedValues = [abs(theory.I3)*I_B; abs(theory.U1)*V_B_phase_rms; ...
    abs(theory.I1)*I_B; abs(theory.U2)*V_B_phase_rms; abs(theory.I2)*I_B; ...
    theory.I2d*I_B; theory.I2q*I_B];
simulationNamedValues = [abs(simulation.I3)*I_B; abs(simulation.U1)*V_B_phase_rms; ...
    abs(simulation.I1)*I_B; abs(simulation.U2)*V_B_phase_rms; abs(simulation.I2)*I_B; ...
    simulation.I2d*I_B; simulation.I2q*I_B];
table55_named = table(theoryNamedValues, simulationNamedValues, relativeErrorPct, ...
    'VariableNames', {'Theory_named','Simulation_named','RelativeError_pct'}, ...
    'RowNames', rowNames);
fprintf('\n===== 表5-5有名值换算（V/A） =====\n');
disp(table55_named);

if simulationAvailable && relativeErrorPct(1) > 10 && simulation.branchDiagnosticsAvailable
    fprintf('\n===== |I3^F| 大误差详细诊断 =====\n');
    fprintf('理论定义：U3^F=0，I3^F=I13^F+I23^F+Ith^F，均为流入故障点的电流。\n');
    fprintf('理论支路分量（pu / kA）：\n');
    fprintf('  I13 = %+.9g%+.9gj / %.6g kA\n', real(theory.I13), imag(theory.I13), abs(theory.I13)*I_B/1000);
    fprintf('  I23 = %+.9g%+.9gj / %.6g kA\n', real(theory.I23), imag(theory.I23), abs(theory.I23)*I_B/1000);
    fprintf('  Ith = %+.9g%+.9gj / %.6g kA\n', real(theory.Ith), imag(theory.Ith), abs(theory.Ith)*I_B/1000);
    fprintf('  I3(KCL) = %+.9g%+.9gj / %.6g kA\n', real(theory.I3), imag(theory.I3), abs(theory.I3)*I_B/1000);
    fprintf('仿真支路分量（pu / kA）：\n');
    fprintf('  I13 = %+.9g%+.9gj / %.6g kA\n', real(simulation.I13), imag(simulation.I13), abs(simulation.I13)*I_B/1000);
    fprintf('  I23 = %+.9g%+.9gj / %.6g kA\n', real(simulation.I23), imag(simulation.I23), abs(simulation.I23)*I_B/1000);
    fprintf('  Ith = %+.9g%+.9gj / %.6g kA\n', real(simulation.Ith), imag(simulation.Ith), abs(simulation.Ith)*I_B/1000);
    fprintf('  I3(KCL) = %+.9g%+.9gj / %.6g kA\n', real(simulation.I3_balance), imag(simulation.I3_balance), abs(simulation.I3_balance)*I_B/1000);
    fprintf('  故障支路测量 = %+.9g%+.9gj / %.6g kA\n', real(simulation.I3), imag(simulation.I3), abs(simulation.I3)*I_B/1000);
    fprintf('仿真实际外部电网命令正序电压：|Egrid_cmd|=%.9g pu，angle=%.9g deg。\n', ...
        abs(simulation.Egrid_command), rad2deg(angle(simulation.Egrid_command)));
elseif simulationAvailable && relativeErrorPct(1) > 10
    fprintf('\n|I3^F| 相对误差超过10%%，但当前模型未提供节点3支路诊断信号。\n');
    fprintf('请重新保存包含 Line13/Line23/GridTh V-I Measurement 的模型后再进行支路分量诊断。\n');
end

%% 7. GFL 第5.3节工况假设校验
u2_for_check = abs(theory.U2);
i2_for_check = abs(theory.I2);
voltageCondition = (V_LVRT_min <= u2_for_check) && (u2_for_check <= V_LVRT_max);
currentCondition = i2_for_check < I_limit * gfl_to_system_current_pu;
fprintf('\n===== GFL工况假设校验（理论值） =====\n');
fprintf('|U2^F| = %.9g pu，要求 %.9g <= |U2^F| <= %.9g：%s\n', ...
    u2_for_check, V_LVRT_min, V_LVRT_max, yes_no(voltageCondition));
fprintf('|I2^F| = %.9g pu(system)，要求 |I2^F| < %.9g pu(system)：%s\n', ...
    i2_for_check, I_limit*gfl_to_system_current_pu, yes_no(currentCondition));

if simulationAvailable
    simulationVoltageCondition = (V_LVRT_min <= abs(simulation.U2)) && ...
        (abs(simulation.U2) <= V_LVRT_max);
    simulationCurrentCondition = abs(simulation.I2) < I_limit*gfl_to_system_current_pu;
    fprintf('仿真复核：|U2^F| = %.9g pu，电压段条件：%s；|I2^F| = %.9g pu，限流条件：%s。\n', ...
        abs(simulation.U2), yes_no(simulationVoltageCondition), abs(simulation.I2), ...
        yes_no(simulationCurrentCondition));
end

if voltageCondition && currentCondition
    fprintf('GFL处于LVRT线性段且未触发限流，第5.3节工况假设成立。\n');
else
    if ~voltageCondition
        fprintf('不满足原因：|U2^F|不在LVRT线性段 [%.9g, %.9g] pu 内。\n', ...
            V_LVRT_min, V_LVRT_max);
    end
    if ~currentCondition
        fprintf('不满足原因：|I2^F|达到或超过限流阈值 %.9g pu(system)。\n', ...
            I_limit*gfl_to_system_current_pu);
    end
    fprintf('当前算例不能直接用于第5.3节，请先核对线路、故障阻抗和LVRT参数。\n');
end

fprintf('\n[有名值换算基准]\n');
fprintf('相电压 RMS 基准 V_B,phase = %.9g V；电流基准 I_B = %.9g A。\n', ...
    V_B_phase_rms, I_B);
fprintf('如需换算：电压有名值 = pu * %.9g V；电流有名值 = pu * %.9g A。\n', ...
    V_B_phase_rms, I_B);

report04_section5_3 = struct('Y_report_pu',Y_report,'Y_line_pu',Y_line, ...
    'Y_post_fault_pu',Y_post_fault,'Y_aug_pu',Y_aug,'theory',theory, ...
    'simulation',simulation,'table55',table55,'table55_named',table55_named, ...
    'simulationAvailable',simulationAvailable, ...
    'simulationError',simError,'base',struct('S_B',S_B,'V_B_LL',V_B_LL, ...
    'V_B_phase_rms',V_B_phase_rms,'I_B',I_B,'Z_B',Z_B));
assignin('base','report04_section5_3',report04_section5_3);

function value = get_signal(simOut, signalName)
value = simOut.get(signalName);
if isempty(value)
    error('仿真输出中不存在信号 %s。', signalName);
end
end

function x1_rms = positive_sequence_rms(signal, tStart, tEnd, fFund)
if ~isa(signal, 'timeseries')
    error('信号不是 timeseries 类型。');
end
t = signal.Time(:);
x = squeeze(signal.Data);
if size(x,2) ~= 3 && size(x,1) == 3
    x = x.';
end
if size(x,2) ~= 3
    error('三相信号应为 N×3，实际尺寸为 %s。', mat2str(size(x)));
end
idx = t >= tStart & t <= tEnd;
if nnz(idx) < 2
    error('时间窗 [%.6g, %.6g] 内没有足够采样点。', tStart, tEnd);
end
t = t(idx);
x = x(idx,:);
a = exp(1j*2*pi/3);
phasorSamples = (x(:,1) + a*x(:,2) + a^2*x(:,3)) .* ...
    exp(-1j*2*pi*fFund*t);
x1_rms = sqrt(2)/3 * mean(phasorSamples);
end

function value = mean_scalar_in_window(signal, tStart, tEnd)
if ~isa(signal, 'timeseries')
    error('信号不是 timeseries 类型。');
end
t = signal.Time(:);
x = squeeze(signal.Data);
x = x(:);
idx = t >= tStart & t <= tEnd;
if nnz(idx) < 2
    error('时间窗 [%.6g, %.6g] 内没有足够采样点。', tStart, tEnd);
end
value = mean(x(idx), 'omitnan');
end

function x1_rms = positive_sequence_rms_from_scalars(signalA, signalB, signalC, ...
        tStart, tEnd, fFund)
if ~isa(signalA,'timeseries') || ~isa(signalB,'timeseries') || ~isa(signalC,'timeseries')
    error('三相标量信号必须均为 timeseries 类型。');
end
t = signalA.Time(:);
a = exp(1j*2*pi/3);
xA = signalA.Data(:);
xB = signalB.Data(:);
xC = signalC.Data(:);
idx = t >= tStart & t <= tEnd;
if nnz(idx) < 2
    error('时间窗内没有足够的三相命令采样点。');
end
phasorSamples = (xA(idx) + a*xB(idx) + a^2*xC(idx)) .* ...
    exp(-1j*2*pi*fFund*t(idx));
x1_rms = sqrt(2)/3 * mean(phasorSamples);
end

function output = yes_no(condition)
if condition
    output = '满足';
else
    output = '不满足';
end
end
