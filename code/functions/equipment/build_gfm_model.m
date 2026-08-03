function build_gfm_model()
%BUILD_GFM_MODEL Build Grid_Forming_Inverters from the validated GFL plant.
% The target keeps the GFL power circuit, LCL filter, average PWM interface,
% measurements, and simulation configuration. The GFL controller is replaced
% by a droop-based grid-forming controller.

Project_Root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
Model_Directory = fullfile(Project_Root, 'simulink', 'models');
Parameter_File = fullfile(Project_Root, 'code', 'scripts', 'equipment', ...
    'GFM_Parameters.m');
Reference_File = fullfile(Model_Directory, 'Grid_Following_Inverters.slx');
Target_File = fullfile(Model_Directory, 'Grid_Forming_Inverters.slx');

assert(isfile(Reference_File), 'Reference model not found: %s', Reference_File);
assert(isfile(Parameter_File), 'Parameter script not found: %s', Parameter_File);

evalin('base', sprintf('run(''%s'');', escapeQuotes(Parameter_File)));
Feedforward_Mode = evalin('base', 'GFM_CL.VoltageFeedforwardMode');
assert(strcmp(Feedforward_Mode, 'capacitor_voltage'), ...
    'The builder currently requires capacitor-voltage feedforward.');

Reference_Model = 'Grid_Following_Inverters';
Target_Model = 'Grid_Forming_Inverters';
closeIfLoaded(Target_Model);
closeIfLoaded(Reference_Model);

copyfile(Reference_File, Target_File, 'f');
load_system(Reference_File);
load_system(Target_File);

Old_Plant = [Target_Model '/GFL_1'];
assert(getSimulinkBlockHandle(Old_Plant) ~= -1, ...
    'The reference plant subsystem GFL_1 was not found.');
set_param(Old_Plant, 'Name', 'GFM_1');
plant = [Target_Model '/GFM_1'];

deleteIfPresent([plant '/PLL与坐标轴变换']);
deleteIfPresent([plant '/功率外环']);
deleteIfPresent([plant '/电流内环']);
deleteIfPresent([plant '/测量部分']);

Keep_Tags = { ...
    'i_1_a', 'i_1_b', 'i_1_c', 'i_1_abc', ...
    'v_c_a', 'v_c_b', 'v_c_c', 'v_c_abc', ...
    'i_2_abc', 'v_pcc_abc', 'v_inv_abc_ref'};
deleteUnusedTagBlocks(plant, Keep_Tags);

Source_Blocks = struct();
Source_Blocks.i1 = renameTagBlock(plant, 'From', 'i_1_abc', 'From_i1_abc');
Source_Blocks.i2 = renameTagBlock(plant, 'From', 'i_2_abc', 'From_i2_abc');
Source_Blocks.vC = renameTagBlock(plant, 'From', 'v_c_abc', 'From_vMid_abc');
Source_Blocks.vPCC = renameTagBlock(plant, 'From', 'v_pcc_abc', ...
    'From_vPCC_abc');
Command_Goto = renameTagBlock(plant, 'Goto', 'v_inv_abc_ref', ...
    'Goto_v_inv_abc_ref');
renameTagBlock(plant, 'From', 'v_inv_abc_ref', 'From_v_inv_abc_ref');
disconnectInput(Command_Goto);

control = [plant '/GFM_Control'];
add_block('simulink/Ports & Subsystems/Subsystem', control, ...
    'Position', [880 285 1340 650], ...
    'BackgroundColor', 'lightBlue');
Simulink.SubSystem.deleteContents(control);
set_param(control, 'AttributesFormatString', ...
    ['P-f / Q-E droop\n' ...
     'vC voltage loop -> i1 current loop\n' ...
     'PLL-free normal operation']);

Template_Base = [Reference_Model '/GFL_1'];
buildGfmControl(control, Template_Base);

add_line(plant, [blockName(Source_Blocks.i1) '/1'], 'GFM_Control/1', ...
    'autorouting', 'on');
add_line(plant, [blockName(Source_Blocks.i2) '/1'], 'GFM_Control/2', ...
    'autorouting', 'on');
add_line(plant, [blockName(Source_Blocks.vC) '/1'], 'GFM_Control/3', ...
    'autorouting', 'on');
add_line(plant, [blockName(Source_Blocks.vPCC) '/1'], 'GFM_Control/4', ...
    'autorouting', 'on');
add_line(plant, 'GFM_Control/1', [blockName(Command_Goto) '/1'], ...
    'autorouting', 'on');

Init_Fcn = sprintf([ ...
    'Model_File=get_param(bdroot,''FileName'');' ...
    'Project_Root=fileparts(fileparts(fileparts(Model_File)));' ...
    'addpath(fullfile(Project_Root,''code'',''functions'',''equipment''));' ...
    'run(fullfile(Project_Root,''code'',''scripts'',''equipment'',' ...
    '''GFM_Parameters.m''));' ...
    'configure_simulink_file_generation_from_model(bdroot);']);
set_param(targetModel, 'Init_Fcn', Init_Fcn, ...
    'Stop_Time', 'GFM_Sim.t_stop');

set_param(Target_Model, 'SimulationCommand', 'update');
save_system(Target_Model, Target_File);
close_system(Reference_Model, 0);

fprintf('Built and compiled %s\n', Target_File);
end

function buildGfmControl(control, Template_Base)
addPort(control, 'Inport', 'i1_abc', 1, [25 45 55 65]);
addPort(control, 'Inport', 'i2_abc', 2, [25 95 55 115]);
addPort(control, 'Inport', 'vMid_abc', 3, [25 145 55 165]);
addPort(control, 'Inport', 'vPCC_abc', 4, [25 195 55 215]);
addPort(control, 'Outport', 'v_inv_abc_ref', 1, [1190 180 1220 200]);

Reference_Frame = [control '/Reference_Frame'];
Pq_Measurement = [control '/PQ_Measurement'];
Droop_Control = [control '/Droop_Control'];
Voltage_Loop = [control '/Voltage_Loop_vC'];
Future_Hook = [control '/Future_Extensions_Hook'];
Current_Loop = [control '/Current_Loop_i1'];
PWM_Control = [control '/PWM_Control'];
Signal_Logging = [control '/Signal_Logging'];

addEmptySubsystem(Reference_Frame, [110 25 310 235], 'green');
addEmptySubsystem(Pq_Measurement, [365 245 550 355], 'yellow');
addEmptySubsystem(Droop_Control, [610 240 800 370], 'orange');
addEmptySubsystem(Voltage_Loop, [610 20 805 175], 'cyan');
addEmptySubsystem(Future_Hook, [820 20 890 175], 'white');
addEmptySubsystem(Current_Loop, [860 20 1055 175], 'blue');
addEmptySubsystem(PWM_Control, [1090 100 1165 255], 'magenta');
addEmptySubsystem(Signal_Logging, [860 260 1085 590], 'gray');

ABC_Template = [Template_Base '/PLL与坐标轴变换/abc to dq0'];
DQ_Template = [Template_Base '/电流内环/dq0 to abc'];
buildReferenceFrame(Reference_Frame, ABC_Template);
buildPqMeasurement(Pq_Measurement);
buildDroopControl(Droop_Control);
buildVoltageLoop(Voltage_Loop);
buildFutureExtensionsHook(Future_Hook);
buildCurrentLoop(Current_Loop);
buildPwmControl(PWM_Control, DQ_Template);
Log_Names = buildSignalLogging(Signal_Logging);

add_line(control, 'i1_abc/1', 'Reference_Frame/1', 'autorouting', 'on');
add_line(control, 'i2_abc/1', 'Reference_Frame/2', 'autorouting', 'on');
add_line(control, 'vMid_abc/1', 'Reference_Frame/3', 'autorouting', 'on');
add_line(control, 'vPCC_abc/1', 'Reference_Frame/4', 'autorouting', 'on');

add_line(control, 'Reference_Frame/3', 'PQ_Measurement/3', ...
    'autorouting', 'on');
add_line(control, 'Reference_Frame/4', 'PQ_Measurement/4', ...
    'autorouting', 'on');
add_line(control, 'Reference_Frame/7', 'PQ_Measurement/1', ...
    'autorouting', 'on');
add_line(control, 'Reference_Frame/8', 'PQ_Measurement/2', ...
    'autorouting', 'on');
add_line(control, 'PQ_Measurement/1', 'Droop_Control/1', ...
    'autorouting', 'on');
add_line(control, 'PQ_Measurement/2', 'Droop_Control/2', ...
    'autorouting', 'on');
add_line(control, 'Droop_Control/3', 'Reference_Frame/5', ...
    'autorouting', 'on');

add_line(control, 'Droop_Control/5', 'Voltage_Loop_vC/1', ...
    'autorouting', 'on');
add_line(control, 'Droop_Control/6', 'Voltage_Loop_vC/2', ...
    'autorouting', 'on');
add_line(control, 'Reference_Frame/5', 'Voltage_Loop_vC/3', ...
    'autorouting', 'on');
add_line(control, 'Reference_Frame/6', 'Voltage_Loop_vC/4', ...
    'autorouting', 'on');
add_line(control, 'Reference_Frame/3', 'Voltage_Loop_vC/5', ...
    'autorouting', 'on');
add_line(control, 'Reference_Frame/4', 'Voltage_Loop_vC/6', ...
    'autorouting', 'on');
add_line(control, 'Droop_Control/1', 'Voltage_Loop_vC/7', ...
    'autorouting', 'on');

add_line(control, 'Voltage_Loop_vC/1', 'Future_Extensions_Hook/1', ...
    'autorouting', 'on');
add_line(control, 'Voltage_Loop_vC/2', 'Future_Extensions_Hook/2', ...
    'autorouting', 'on');
add_line(control, 'Future_Extensions_Hook/1', 'Current_Loop_i1/1', ...
    'autorouting', 'on');
add_line(control, 'Future_Extensions_Hook/2', 'Current_Loop_i1/2', ...
    'autorouting', 'on');
add_line(control, 'Reference_Frame/1', 'Current_Loop_i1/3', ...
    'autorouting', 'on');
add_line(control, 'Reference_Frame/2', 'Current_Loop_i1/4', ...
    'autorouting', 'on');
add_line(control, 'Reference_Frame/5', 'Current_Loop_i1/5', ...
    'autorouting', 'on');
add_line(control, 'Reference_Frame/6', 'Current_Loop_i1/6', ...
    'autorouting', 'on');
add_line(control, 'Droop_Control/1', 'Current_Loop_i1/7', ...
    'autorouting', 'on');

add_line(control, 'Current_Loop_i1/1', 'PWM_Control/1', ...
    'autorouting', 'on');
add_line(control, 'Current_Loop_i1/2', 'PWM_Control/2', ...
    'autorouting', 'on');
add_line(control, 'Droop_Control/3', 'PWM_Control/3', ...
    'autorouting', 'on');
add_line(control, 'PWM_Control/1', 'v_inv_abc_ref/1', ...
    'autorouting', 'on');

Log_Sources = { ...
    'PQ_Measurement/1', 'PQ_Measurement/2', ...
    'Droop_Control/1', 'Droop_Control/2', 'Droop_Control/3', ...
    'Droop_Control/4', 'Droop_Control/5', 'Droop_Control/6', ...
    'Reference_Frame/5', 'Reference_Frame/6', ...
    'Future_Extensions_Hook/1', 'Future_Extensions_Hook/2', ...
    'Reference_Frame/1', 'Reference_Frame/2', ...
    'Reference_Frame/3', 'Reference_Frame/4', ...
    'Reference_Frame/9', 'PWM_Control/2', 'PWM_Control/3'};
for k = 1:numel(Log_Names)
    add_line(control, Log_Sources{k}, sprintf('Signal_Logging/%d', k), ...
        'autorouting', 'on');
end
end

function buildReferenceFrame(sys, ABC_Template)
In_Names = {'i1_abc', 'i2_abc', 'vMid_abc', 'vPCC_abc', 'theta_ref'};
Out_Names = {'i1_d', 'i1_q', 'i2_d', 'i2_q', 'vC_d', 'vC_q', ...
    'vPCC_d', 'vPCC_q', 'vPCC_mag'};
for k = 1:numel(In_Names)
    addPort(sys, 'Inport', In_Names{k}, k, [20 25+45*(k-1) 50 45+45*(k-1)]);
end
for k = 1:numel(Out_Names)
    addPort(sys, 'Outport', Out_Names{k}, k, ...
        [510 20+32*(k-1) 540 40+32*(k-1)]);
end

labels = {'i1', 'i2', 'vC', 'vPCC'};
for k = 1:4
    transform = [sys '/abc_to_dq_' labels{k}];
    demux = [sys '/Demux_' labels{k}];
    add_block(ABC_Template, transform, ...
        'Position', [105 15+70*(k-1) 235 60+70*(k-1)]);
    add_block('simulink/Signal Routing/Demux', demux, ...
        'Outputs', '3', ...
        'Position', [285 20+70*(k-1) 290 55+70*(k-1)]);
    if k ~= 3
        add_line(sys, [In_Names{k} '/1'], [blockName(transform) '/1'], ...
            'autorouting', 'on');
    end
    add_line(sys, 'theta_ref/1', [blockName(transform) '/2'], ...
        'autorouting', 'on');
    add_line(sys, [blockName(transform) '/1'], [blockName(demux) '/1'], ...
        'autorouting', 'on');
    add_line(sys, [blockName(demux) '/1'], [Out_Names{2*k-1} '/1'], ...
        'autorouting', 'on');
    add_line(sys, [blockName(demux) '/2'], [Out_Names{2*k} '/1'], ...
        'autorouting', 'on');
end

% The physical voltage sensors span the complete series RC branch. Recover
% the ideal capacitor voltage required by the GFM voltage-loop definition:
% vC = vMid - R_C*(i1-i2).
add_block('simulink/Math Operations/Sum', [sys '/Capacitor_Current_abc'], ...
    'Inputs', '+-', 'Position', [60 180 85 220]);
add_block('simulink/Math Operations/Gain', [sys '/RC_Voltage_Drop_abc'], ...
    'Gain', 'R_C', 'Position', [105 185 165 215]);
add_block('simulink/Math Operations/Sum', [sys '/Ideal_vC_abc'], ...
    'Inputs', '+-', 'Position', [190 180 215 220]);
add_line(sys, 'i1_abc/1', 'Capacitor_Current_abc/1', 'autorouting', 'on');
add_line(sys, 'i2_abc/1', 'Capacitor_Current_abc/2', 'autorouting', 'on');
add_line(sys, 'Capacitor_Current_abc/1', 'RC_Voltage_Drop_abc/1', ...
    'autorouting', 'on');
add_line(sys, 'vMid_abc/1', 'Ideal_vC_abc/1', 'autorouting', 'on');
add_line(sys, 'RC_Voltage_Drop_abc/1', 'Ideal_vC_abc/2', ...
    'autorouting', 'on');
add_line(sys, 'Ideal_vC_abc/1', 'abc_to_dq_vC/1', 'autorouting', 'on');

add_block('simulink/Signal Routing/Mux', [sys '/Mux_vPCC_dq'], ...
    'Inputs', '2', 'Position', [350 250 355 290]);
add_block('simulink/User-Defined Functions/Fcn', [sys '/PCC_Magnitude'], ...
    'Expr', 'sqrt(u(1)^2+u(2)^2)', ...
    'Position', [385 255 465 285]);
add_line(sys, 'Demux_vPCC/1', 'Mux_vPCC_dq/1', 'autorouting', 'on');
add_line(sys, 'Demux_vPCC/2', 'Mux_vPCC_dq/2', 'autorouting', 'on');
add_line(sys, 'Mux_vPCC_dq/1', 'PCC_Magnitude/1', 'autorouting', 'on');
add_line(sys, 'PCC_Magnitude/1', 'vPCC_mag/1', 'autorouting', 'on');
end

function buildPqMeasurement(sys)
In_Names = {'vPCC_d', 'vPCC_q', 'i2_d', 'i2_q'};
for k = 1:4
    addPort(sys, 'Inport', In_Names{k}, k, [15 25+45*(k-1) 45 45+45*(k-1)]);
end
addPort(sys, 'Outport', 'P_pu', 1, [500 60 530 80]);
addPort(sys, 'Outport', 'Q_pu', 2, [500 150 530 170]);

add_block('simulink/Signal Routing/Mux', [sys '/Mux_vdq_i2dq'], ...
    'Inputs', '4', 'Position', [85 40 90 165]);
for k = 1:4
    add_line(sys, [In_Names{k} '/1'], sprintf('Mux_vdq_i2dq/%d', k), ...
        'autorouting', 'on');
end
add_block('simulink/User-Defined Functions/Fcn', [sys '/Calculate_P'], ...
    'Expr', '1.5*(u(1)*u(3)+u(2)*u(4))', ...
    'Position', [125 45 235 75]);
add_block('simulink/User-Defined Functions/Fcn', [sys '/Calculate_Q'], ...
    'Expr', '1.5*(u(1)*u(4)-u(2)*u(3))', ...
    'Position', [125 135 235 165]);
add_line(sys, 'Mux_vdq_i2dq/1', 'Calculate_P/1', 'autorouting', 'on');
add_line(sys, 'Mux_vdq_i2dq/1', 'Calculate_Q/1', 'autorouting', 'on');

buildInitializedLpf(sys, 'P', 'Calculate_P/1', 'GFM_Droop.Pref_pu', ...
    275, 50, 'P_pu');
buildInitializedLpf(sys, 'Q', 'Calculate_Q/1', 'GFM_Droop.Qref_pu', ...
    275, 140, 'Q_pu');
end

function buildInitializedLpf(sys, label, Raw_Source, Initial_Condition, x, y, Out_Name)
Gain_PU = [sys '/Scale_' label '_to_pu'];
Sum_Path = [sys '/LPF_' label '_error'];
Gain_Wc = [sys '/LPF_' label '_wc'];
integrator = [sys '/LPF_' label];
add_block('simulink/Math Operations/Gain', Gain_PU, ...
    'Gain', '1/S_base', 'Position', [x y x+65 y+30]);
add_block('simulink/Math Operations/Sum', Sum_Path, ...
    'Inputs', '+-', 'Position', [x+90 y x+115 y+30]);
add_block('simulink/Math Operations/Gain', Gain_Wc, ...
    'Gain', 'GFM_Droop.PQ_lpf_wc', 'Position', [x+140 y x+215 y+30]);
add_block('simulink/Continuous/Integrator', integrator, ...
    'Initial_Condition', Initial_Condition, ...
    'Position', [x+240 y x+270 y+30]);
add_line(sys, Raw_Source, [blockName(Gain_PU) '/1'], 'autorouting', 'on');
add_line(sys, [blockName(Gain_PU) '/1'], [blockName(Sum_Path) '/1'], ...
    'autorouting', 'on');
add_line(sys, [blockName(integrator) '/1'], [blockName(Sum_Path) '/2'], ...
    'autorouting', 'on');
add_line(sys, [blockName(Sum_Path) '/1'], [blockName(Gain_Wc) '/1'], ...
    'autorouting', 'on');
add_line(sys, [blockName(Gain_Wc) '/1'], [blockName(integrator) '/1'], ...
    'autorouting', 'on');
add_line(sys, [blockName(integrator) '/1'], [Out_Name '/1'], ...
    'autorouting', 'on');
end

function buildDroopControl(sys)
addPort(sys, 'Inport', 'P_pu', 1, [15 50 45 70]);
addPort(sys, 'Inport', 'Q_pu', 2, [15 170 45 190]);
Out_Names = {'omega_ref', 'f_ref', 'theta_ref', 'E_ref_pu', ...
    'vC_d_ref', 'vC_q_ref'};
for k = 1:numel(Out_Names)
    addPort(sys, 'Outport', Out_Names{k}, k, ...
        [525 25+45*(k-1) 555 45+45*(k-1)]);
end

add_block('simulink/Sources/Constant', [sys '/Pref_pu'], ...
    'Value', 'GFM_Droop.Pref_pu', 'Position', [70 85 120 110]);
add_block('simulink/Math Operations/Sum', [sys '/P_minus_Pref'], ...
    'Inputs', '+-', 'Position', [145 45 170 75]);
add_block('simulink/Math Operations/Gain', [sys '/P_f_droop'], ...
    'Gain', '-GFM_Droop.mp', 'Position', [195 45 285 75]);
add_block('simulink/Sources/Constant', [sys '/omega0'], ...
    'Value', 'GFM_Droop.w0', 'Position', [195 90 285 115]);
add_block('simulink/Math Operations/Sum', [sys '/omega_command'], ...
    'Inputs', '++', 'Position', [315 45 340 75]);
add_block('simulink/Discontinuities/Saturation', [sys '/omega_limits'], ...
    'LowerLimit', 'GFM_Droop.w_min', ...
    'UpperLimit', 'GFM_Droop.w_max', ...
    'Position', [365 45 430 75]);
add_block('simulink/Math Operations/Gain', [sys '/radps_to_hz'], ...
    'Gain', '1/(2*pi)', 'Position', [450 90 510 120]);
add_block('simulink/Continuous/Integrator', [sys '/theta_integrator'], ...
    'Initial_Condition', 'GFM_Droop.theta0', ...
    'Position', [450 135 480 165]);

add_line(sys, 'P_pu/1', 'P_minus_Pref/1', 'autorouting', 'on');
add_line(sys, 'Pref_pu/1', 'P_minus_Pref/2', 'autorouting', 'on');
add_line(sys, 'P_minus_Pref/1', 'P_f_droop/1', 'autorouting', 'on');
add_line(sys, 'P_f_droop/1', 'omega_command/1', 'autorouting', 'on');
add_line(sys, 'omega0/1', 'omega_command/2', 'autorouting', 'on');
add_line(sys, 'omega_command/1', 'omega_limits/1', 'autorouting', 'on');
add_line(sys, 'omega_limits/1', 'omega_ref/1', 'autorouting', 'on');
add_line(sys, 'omega_limits/1', 'radps_to_hz/1', 'autorouting', 'on');
add_line(sys, 'radps_to_hz/1', 'f_ref/1', 'autorouting', 'on');
add_line(sys, 'omega_limits/1', 'theta_integrator/1', 'autorouting', 'on');
add_line(sys, 'theta_integrator/1', 'theta_ref/1', 'autorouting', 'on');

add_block('simulink/Sources/Constant', [sys '/Qref_pu'], ...
    'Value', 'GFM_Droop.Qref_pu', 'Position', [70 205 120 230]);
add_block('simulink/Math Operations/Sum', [sys '/Q_minus_Qref'], ...
    'Inputs', '+-', 'Position', [145 165 170 195]);
add_block('simulink/Math Operations/Gain', [sys '/Q_E_droop'], ...
    'Gain', '-GFM_Droop.nq', 'Position', [195 165 285 195]);
add_block('simulink/Sources/Constant', [sys '/E0_pu'], ...
    'Value', '1', 'Position', [195 210 285 235]);
add_block('simulink/Math Operations/Sum', [sys '/E_command'], ...
    'Inputs', '++', 'Position', [315 165 340 195]);
add_block('simulink/Discontinuities/Saturation', [sys '/E_limits'], ...
    'LowerLimit', 'GFM_Droop.E_min_pu', ...
    'UpperLimit', 'GFM_Droop.E_max_pu', ...
    'Position', [365 165 430 195]);
add_block('simulink/Math Operations/Gain', [sys '/E_to_vC_d_ref'], ...
    'Gain', 'V_base_phase', 'Position', [450 205 515 235]);
add_block('simulink/Sources/Constant', [sys '/vC_q_ref_zero'], ...
    'Value', '0', 'Position', [450 250 500 275]);

add_line(sys, 'Q_pu/1', 'Q_minus_Qref/1', 'autorouting', 'on');
add_line(sys, 'Qref_pu/1', 'Q_minus_Qref/2', 'autorouting', 'on');
add_line(sys, 'Q_minus_Qref/1', 'Q_E_droop/1', 'autorouting', 'on');
add_line(sys, 'Q_E_droop/1', 'E_command/1', 'autorouting', 'on');
add_line(sys, 'E0_pu/1', 'E_command/2', 'autorouting', 'on');
add_line(sys, 'E_command/1', 'E_limits/1', 'autorouting', 'on');
add_line(sys, 'E_limits/1', 'E_ref_pu/1', 'autorouting', 'on');
add_line(sys, 'E_limits/1', 'E_to_vC_d_ref/1', 'autorouting', 'on');
add_line(sys, 'E_to_vC_d_ref/1', 'vC_d_ref/1', 'autorouting', 'on');
add_line(sys, 'vC_q_ref_zero/1', 'vC_q_ref/1', 'autorouting', 'on');
end

function buildVoltageLoop(sys)
In_Names = {'vC_d_ref', 'vC_q_ref', 'vC_d', 'vC_q', ...
    'i2_d', 'i2_q', 'omega_ref'};
for k = 1:numel(In_Names)
    addPort(sys, 'Inport', In_Names{k}, k, [15 20+38*(k-1) 45 40+38*(k-1)]);
end
addPort(sys, 'Outport', 'i1_d_ref', 1, [580 75 610 95]);
addPort(sys, 'Outport', 'i1_q_ref', 2, [580 190 610 210]);

buildPiChannel(sys, 'vd', 'vC_d_ref/1', 'vC_d/1', ...
    'GFM_VL.Kp', 'GFM_VL.Ki', 90, 35);
buildPiChannel(sys, 'vq', 'vC_q_ref/1', 'vC_q/1', ...
    'GFM_VL.Kp', 'GFM_VL.Ki', 90, 150);

add_block('simulink/Math Operations/Gain', [sys '/i2_d_feedforward'], ...
    'Gain', 'double(GFM_VL.UseI2Feedforward)', ...
    'Position', [290 90 370 120]);
add_block('simulink/Math Operations/Gain', [sys '/i2_q_feedforward'], ...
    'Gain', 'double(GFM_VL.UseI2Feedforward)', ...
    'Position', [290 205 370 235]);
add_line(sys, 'i2_d/1', 'i2_d_feedforward/1', 'autorouting', 'on');
add_line(sys, 'i2_q/1', 'i2_q_feedforward/1', 'autorouting', 'on');

add_block('simulink/Math Operations/Product', [sys '/omega_vC_q'], ...
    'Inputs', '2', 'Position', [290 125 325 155]);
add_block('simulink/Math Operations/Gain', [sys '/Cf_dq_d'], ...
    'Gain', 'double(GFM_VL.UseDQDecouplingInTuning)*Cf', ...
    'Position', [350 125 435 155]);
add_block('simulink/Math Operations/Product', [sys '/omega_vC_d'], ...
    'Inputs', '2', 'Position', [290 240 325 270]);
add_block('simulink/Math Operations/Gain', [sys '/Cf_dq_q'], ...
    'Gain', 'double(GFM_VL.UseDQDecouplingInTuning)*Cf', ...
    'Position', [350 240 435 270]);
add_line(sys, 'omega_ref/1', 'omega_vC_q/1', 'autorouting', 'on');
add_line(sys, 'vC_q/1', 'omega_vC_q/2', 'autorouting', 'on');
add_line(sys, 'omega_vC_q/1', 'Cf_dq_d/1', 'autorouting', 'on');
add_line(sys, 'omega_ref/1', 'omega_vC_d/1', 'autorouting', 'on');
add_line(sys, 'vC_d/1', 'omega_vC_d/2', 'autorouting', 'on');
add_line(sys, 'omega_vC_d/1', 'Cf_dq_q/1', 'autorouting', 'on');

add_block('simulink/Math Operations/Sum', [sys '/Build_i1_d_ref'], ...
    'Inputs', '++-', 'Position', [485 65 510 105]);
add_block('simulink/Math Operations/Sum', [sys '/Build_i1_q_ref'], ...
    'Inputs', '+++', 'Position', [485 180 510 220]);
add_line(sys, 'PI_vd/1', 'Build_i1_d_ref/1', 'autorouting', 'on');
add_line(sys, 'i2_d_feedforward/1', 'Build_i1_d_ref/2', ...
    'autorouting', 'on');
add_line(sys, 'Cf_dq_d/1', 'Build_i1_d_ref/3', 'autorouting', 'on');
add_line(sys, 'PI_vq/1', 'Build_i1_q_ref/1', 'autorouting', 'on');
add_line(sys, 'i2_q_feedforward/1', 'Build_i1_q_ref/2', ...
    'autorouting', 'on');
add_line(sys, 'Cf_dq_q/1', 'Build_i1_q_ref/3', 'autorouting', 'on');
add_line(sys, 'Build_i1_d_ref/1', 'i1_d_ref/1', 'autorouting', 'on');
add_line(sys, 'Build_i1_q_ref/1', 'i1_q_ref/1', 'autorouting', 'on');
end

function buildFutureExtensionsHook(sys)
addPort(sys, 'Inport', 'i1_d_ref_in', 1, [15 35 45 55]);
addPort(sys, 'Inport', 'i1_q_ref_in', 2, [15 100 45 120]);
addPort(sys, 'Outport', 'i1_d_ref_out', 1, [175 35 205 55]);
addPort(sys, 'Outport', 'i1_q_ref_out', 2, [175 100 205 120]);
add_line(sys, 'i1_d_ref_in/1', 'i1_d_ref_out/1', 'autorouting', 'on');
add_line(sys, 'i1_q_ref_in/1', 'i1_q_ref_out/1', 'autorouting', 'on');
set_param(sys, 'AttributesFormatString', ...
    ['Unity pass-through in this version\n' ...
     'Reserved: virtual impedance / LVRT / current limiting']);
end

function buildCurrentLoop(sys)
In_Names = {'i1_d_ref', 'i1_q_ref', 'i1_d', 'i1_q', ...
    'vC_d', 'vC_q', 'omega_ref'};
for k = 1:numel(In_Names)
    addPort(sys, 'Inport', In_Names{k}, k, [15 20+38*(k-1) 45 40+38*(k-1)]);
end
addPort(sys, 'Outport', 'v_inv_d_ref', 1, [565 75 595 95]);
addPort(sys, 'Outport', 'v_inv_q_ref', 2, [565 190 595 210]);

buildPiChannel(sys, 'id', 'i1_d_ref/1', 'i1_d/1', ...
    'GFM_CL.Kp', 'GFM_CL.Ki', 90, 35);
buildPiChannel(sys, 'iq', 'i1_q_ref/1', 'i1_q/1', ...
    'GFM_CL.Kp', 'GFM_CL.Ki', 90, 150);

add_block('simulink/Math Operations/Product', [sys '/omega_i1_q'], ...
    'Inputs', '2', 'Position', [300 115 335 145]);
add_block('simulink/Math Operations/Gain', [sys '/L1_decouple_d'], ...
    'Gain', '-double(GFM_CL.UseDQDecouplingInTuning)*L1', ...
    'Position', [360 115 465 145]);
add_block('simulink/Math Operations/Product', [sys '/omega_i1_d'], ...
    'Inputs', '2', 'Position', [300 230 335 260]);
add_block('simulink/Math Operations/Gain', [sys '/L1_decouple_q'], ...
    'Gain', 'double(GFM_CL.UseDQDecouplingInTuning)*L1', ...
    'Position', [360 230 465 260]);
add_line(sys, 'omega_ref/1', 'omega_i1_q/1', 'autorouting', 'on');
add_line(sys, 'i1_q/1', 'omega_i1_q/2', 'autorouting', 'on');
add_line(sys, 'omega_i1_q/1', 'L1_decouple_d/1', 'autorouting', 'on');
add_line(sys, 'omega_ref/1', 'omega_i1_d/1', 'autorouting', 'on');
add_line(sys, 'i1_d/1', 'omega_i1_d/2', 'autorouting', 'on');
add_line(sys, 'omega_i1_d/1', 'L1_decouple_q/1', 'autorouting', 'on');

add_block('simulink/Math Operations/Sum', [sys '/Add_vC_d_feedforward'], ...
    'Inputs', '+++', 'Position', [495 65 520 105]);
add_block('simulink/Math Operations/Sum', [sys '/Add_vC_q_feedforward'], ...
    'Inputs', '+++', 'Position', [495 180 520 220]);
add_line(sys, 'PI_id/1', 'Add_vC_d_feedforward/1', 'autorouting', 'on');
add_line(sys, 'vC_d/1', 'Add_vC_d_feedforward/2', 'autorouting', 'on');
add_line(sys, 'L1_decouple_d/1', 'Add_vC_d_feedforward/3', ...
    'autorouting', 'on');
add_line(sys, 'PI_iq/1', 'Add_vC_q_feedforward/1', 'autorouting', 'on');
add_line(sys, 'vC_q/1', 'Add_vC_q_feedforward/2', 'autorouting', 'on');
add_line(sys, 'L1_decouple_q/1', 'Add_vC_q_feedforward/3', ...
    'autorouting', 'on');
add_line(sys, 'Add_vC_d_feedforward/1', 'v_inv_d_ref/1', ...
    'autorouting', 'on');
add_line(sys, 'Add_vC_q_feedforward/1', 'v_inv_q_ref/1', ...
    'autorouting', 'on');
end

function buildPiChannel(sys, label, Reference_Source, Feedback_Source, kp, ki, x, y)
Error_Block = [sys '/Error_' label];
Kp_Block = [sys '/Kp_' label];
Ki_Block = [sys '/Ki_' label];
integrator = [sys '/Integrator_' label];
Sum_Block = [sys '/PI_' label];
add_block('simulink/Math Operations/Sum', Error_Block, ...
    'Inputs', '+-', 'Position', [x y x+25 y+30]);
add_block('simulink/Math Operations/Gain', Kp_Block, ...
    'Gain', kp, 'Position', [x+50 y-15 x+115 y+15]);
add_block('simulink/Math Operations/Gain', Ki_Block, ...
    'Gain', ki, 'Position', [x+50 y+30 x+115 y+60]);
add_block('simulink/Continuous/Integrator', integrator, ...
    'Initial_Condition', '0', 'Position', [x+140 y+30 x+170 y+60]);
add_block('simulink/Math Operations/Sum', Sum_Block, ...
    'Inputs', '++', 'Position', [x+205 y x+230 y+40]);
add_line(sys, Reference_Source, [blockName(Error_Block) '/1'], ...
    'autorouting', 'on');
add_line(sys, Feedback_Source, [blockName(Error_Block) '/2'], ...
    'autorouting', 'on');
add_line(sys, [blockName(Error_Block) '/1'], [blockName(Kp_Block) '/1'], ...
    'autorouting', 'on');
add_line(sys, [blockName(Error_Block) '/1'], [blockName(Ki_Block) '/1'], ...
    'autorouting', 'on');
add_line(sys, [blockName(Kp_Block) '/1'], [blockName(Sum_Block) '/1'], ...
    'autorouting', 'on');
add_line(sys, [blockName(Ki_Block) '/1'], [blockName(integrator) '/1'], ...
    'autorouting', 'on');
add_line(sys, [blockName(integrator) '/1'], [blockName(Sum_Block) '/2'], ...
    'autorouting', 'on');
end

function buildPwmControl(sys, DQ_Template)
addPort(sys, 'Inport', 'v_inv_d_ref', 1, [15 35 45 55]);
addPort(sys, 'Inport', 'v_inv_q_ref', 2, [15 85 45 105]);
addPort(sys, 'Inport', 'theta_ref', 3, [15 135 45 155]);
addPort(sys, 'Outport', 'v_inv_abc_ref', 1, [500 45 530 65]);
addPort(sys, 'Outport', 'modulation_abc', 2, [500 105 530 125]);
addPort(sys, 'Outport', 'duty_abc', 3, [500 165 530 185]);

add_block('simulink/Sources/Constant', [sys '/zero_sequence'], ...
    'Value', '0', 'Position', [70 140 110 165]);
add_block('simulink/Signal Routing/Mux', [sys '/Mux_dq0'], ...
    'Inputs', '3', 'Position', [135 45 140 145]);
add_block(DQ_Template, [sys '/dq0_to_abc'], ...
    'Position', [180 50 310 115]);
add_block('simulink/Discontinuities/Saturation', [sys '/Phase_Voltage_Limits'], ...
    'UpperLimit', 'V_in/2', 'LowerLimit', '-V_in/2', ...
    'Position', [340 45 410 75]);
add_block('simulink/Continuous/Transport Delay', [sys '/PWM_Delay'], ...
    'DelayTime', 'GFM_CL.PWMDelay', ...
    'InitialOutput', '0', ...
    'Position', [435 40 475 80]);
add_block('simulink/Math Operations/Gain', [sys '/Voltage_to_Modulation'], ...
    'Gain', '2/V_in', 'Position', [340 100 410 130]);
add_block('simulink/Math Operations/Bias', [sys '/Duty_Offset'], ...
    'Bias', '1', 'Position', [340 155 400 185]);
add_block('simulink/Math Operations/Gain', [sys '/Duty_Scale'], ...
    'Gain', '0.5', 'Position', [420 155 470 185]);

add_line(sys, 'v_inv_d_ref/1', 'Mux_dq0/1', 'autorouting', 'on');
add_line(sys, 'v_inv_q_ref/1', 'Mux_dq0/2', 'autorouting', 'on');
add_line(sys, 'zero_sequence/1', 'Mux_dq0/3', 'autorouting', 'on');
add_line(sys, 'Mux_dq0/1', 'dq0_to_abc/1', 'autorouting', 'on');
add_line(sys, 'theta_ref/1', 'dq0_to_abc/2', 'autorouting', 'on');
add_line(sys, 'dq0_to_abc/1', 'Phase_Voltage_Limits/1', ...
    'autorouting', 'on');
add_line(sys, 'Phase_Voltage_Limits/1', 'PWM_Delay/1', ...
    'autorouting', 'on');
add_line(sys, 'PWM_Delay/1', 'v_inv_abc_ref/1', ...
    'autorouting', 'on');
add_line(sys, 'Phase_Voltage_Limits/1', 'Voltage_to_Modulation/1', ...
    'autorouting', 'on');
add_line(sys, 'Voltage_to_Modulation/1', 'modulation_abc/1', ...
    'autorouting', 'on');
add_line(sys, 'Voltage_to_Modulation/1', 'Duty_Offset/1', ...
    'autorouting', 'on');
add_line(sys, 'Duty_Offset/1', 'Duty_Scale/1', 'autorouting', 'on');
add_line(sys, 'Duty_Scale/1', 'duty_abc/1', 'autorouting', 'on');
end

function names = buildSignalLogging(sys)
names = {'P_pu', 'Q_pu', 'omega_ref', 'f_ref', 'theta_ref', ...
    'E_ref_pu', 'vC_d_ref', 'vC_q_ref', 'vC_d', 'vC_q', ...
    'i1_d_ref', 'i1_q_ref', 'i1_d', 'i1_q', 'i2_d', 'i2_q', ...
    'vPCC_mag', 'modulation_abc', 'duty_abc'};
for k = 1:numel(names)
    y = 15 + 32*(k-1);
    addPort(sys, 'Inport', names{k}, k, [15 y 45 y+20]);
    sink = [sys '/Log_' names{k}];
    add_block('simulink/Sinks/To Workspace', sink, ...
        'Variable_Name', names{k}, ...
        'SaveFormat', 'Timeseries', ...
        'Position', [105 y 205 y+20]);
    add_line(sys, [names{k} '/1'], [blockName(sink) '/1'], ...
        'autorouting', 'on');
end
end

function addEmptySubsystem(path, position, color)
add_block('simulink/Ports & Subsystems/Subsystem', path, ...
    'Position', position, 'BackgroundColor', color);
Simulink.SubSystem.deleteContents(path);
end

function addPort(sys, type, name, port, position)
library = ['simulink/Ports & Subsystems/' type(1:end-4) '1'];
add_block(library, [sys '/' name], ...
    'Port', num2str(port), 'Position', position);
end

function deleteUnusedTagBlocks(sys, Keep_Tags)
for Block_Type = {'From', 'Goto'}
    blocks = find_system(sys, 'SearchDepth', 1, ...
        'Block_Type', Block_Type{1});
    for k = 1:numel(blocks)
        if ~ismember(get_param(blocks{k}, 'GotoTag'), Keep_Tags)
            deleteBlockWithLines(blocks{k});
        end
    end
end
end

function path = renameTagBlock(sys, Block_Type, tag, New_Name)
blocks = find_system(sys, 'SearchDepth', 1, 'BlockType', Block_Type);
matches = blocks(strcmp(get_param(blocks, 'GotoTag'), tag));
assert(~isempty(matches), ...
    'No direct %s block was found for tag %s.', blockType, tag);
for k = 2:numel(matches)
    deleteBlockWithLines(matches{k});
end
set_param(matches{1}, 'Name', New_Name);
path = [sys '/' newName];
end

function deleteIfPresent(path)
if getSimulinkBlockHandle(path) ~= -1
    deleteBlockWithLines(path);
end
end

function deleteBlockWithLines(path)
ports = get_param(path, 'PortHandles');
Port_Types = fieldnames(ports);
for Type_Index = 1:numel(Port_Types)
    handles = ports.(Port_Types{Type_Index});
    for Port_Index = 1:numel(handles)
        try
            Line_Handle = get_param(handles(Port_Index), 'Line');
        catch
            Line_Handle = -1;
        end
        if Line_Handle ~= -1 && ishandle(Line_Handle)
            delete_line(Line_Handle);
        end
    end
end
delete_block(path);
end

function disconnectInput(path)
ports = get_param(path, 'PortHandles');
Line_Handle = get_param(ports.Inport, 'Line');
if Line_Handle ~= -1
    delete_line(Line_Handle);
end
end

function closeIfLoaded(model)
if bdIsLoaded(model)
    close_system(model, 0);
end
end

function name = blockName(path)
[~, name] = fileparts(path);
end

function value = escapeQuotes(value)
value = strrep(value, '''', '''''');
end
