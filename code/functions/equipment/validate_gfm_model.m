function report = validate_gfm_model()
%VALIDATE_GFM_MODEL Compile and run acceptance checks for the GFM model.

Project_Root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
Model_Name = 'Grid_Forming_Inverters';
Model_File = fullfile(Project_Root, 'simulink', 'models', ...
    [Model_Name '.slx']);
Parameter_File = fullfile(Project_Root, 'code', 'scripts', 'equipment', ...
    'GFM', 'GFM_Parameters.m');

assert(isfile(Model_File), 'GFM model not found: %s', Model_File);
assert(isfile(Parameter_File), 'GFM parameter script not found: %s', ...
    Parameter_File);

evalin('base', sprintf('run(''%s'');', escapeQuotes(Parameter_File)));
Required_Variables = {'V_base', 'S_base', 'V_in', 'L1', 'Cf', 'L2', ...
    'GFM_CL', 'GFM_VL', 'GFM_Droop', 'GFM_Sim'};
for k = 1:numel(Required_Variables)
    assert(evalin('base', sprintf('exist(''%s'',''var'') == 1', ...
        Required_Variables{k})), ...
        'GFM_Parameters.m did not define %s.', Required_Variables{k});
end

closeIfLoaded(Model_Name);
load_system(Model_File);
cleanup = onCleanup(@() closeIfLoaded(Model_Name));

set_param(Model_Name, 'SimulationCommand', 'update');

plant = [Model_Name '/GFM_1'];
control = [plant '/GFM_Control'];
Required_Blocks = { ...
    [control '/PQ_Measurement'], ...
    [control '/Droop_Control'], ...
    [control '/Voltage_Loop_vC'], ...
    [control '/Future_Extensions_Hook'], ...
    [control '/Current_Loop_i1'], ...
    [control '/Reference_Frame'], ...
    [control '/PWM_Control'], ...
    [control '/Signal_Logging'], ...
    [control '/Reference_Frame/Ideal_vC_abc'], ...
    [control '/Droop_Control/theta_integrator'], ...
    [control '/Voltage_Loop_vC/Build_i1_d_ref'], ...
    [control '/Voltage_Loop_vC/Build_i1_q_ref'], ...
    [control '/Current_Loop_i1/Add_vC_d_feedforward'], ...
    [control '/Current_Loop_i1/Add_vC_q_feedforward'], ...
    [control '/PWM_Control/PWM_Delay']};
for k = 1:numel(Required_Blocks)
    assert(getSimulinkBlockHandle(Required_Blocks{k}) ~= -1, ...
        'Required GFM block is missing: %s', Required_Blocks{k});
end

Disconnected_Lines = findDisconnectedLines(Model_Name);
assert(isempty(Disconnected_Lines), ...
    'The GFM model contains %d disconnected line(s).', ...
    numel(Disconnected_Lines));

Goto_Blocks = find_system(plant, 'LookUnderMasks', 'none', ...
    'FollowLinks', 'off', 'BlockType', 'Goto');
Goto_Tags = getStringParameters(Goto_Blocks, 'GotoTag');
if isempty(Goto_Tags)
    Duplicate_Goto_Tags = {};
else
    [Unique_Tags, ~, Tag_Groups] = unique(Goto_Tags);
    Tag_Counts = accumarray(Tag_Groups, 1);
    Duplicate_Goto_Tags = Unique_Tags(Tag_Counts > 1);
end
assert(isempty(Duplicate_Goto_Tags), ...
    'Duplicate Goto tags were found: %s', ...
    strjoin(Duplicate_Goto_Tags, ', '));

PLL_Blocks = findPllBlocks(plant);
assert(isempty(PLL_Blocks), ...
    'PLL blocks remain in the GFM normal control path.');

Algebraic_Loops = Simulink.BlockDiagram.getAlgebraicLoops(Model_Name);
assert(isempty(Algebraic_Loops), ...
    'The GFM model contains %d algebraic loop(s).', ...
    numel(Algebraic_Loops));

assert(strcmp(get_param([control '/Voltage_Loop_vC/Build_i1_d_ref'], ...
    'Inputs'), '++-'), 'The d-axis vC decoupling sign is incorrect.');
assert(strcmp(get_param([control '/Voltage_Loop_vC/Build_i1_q_ref'], ...
    'Inputs'), '+++'), 'The q-axis vC decoupling sign is incorrect.');
assert(strcmp(get_param([control '/Current_Loop_i1/Error_id'], ...
    'Inputs'), '+-'), 'The d-axis i1 error sign is incorrect.');
assert(strcmp(get_param([control '/Current_Loop_i1/Error_iq'], ...
    'Inputs'), '+-'), 'The q-axis i1 error sign is incorrect.');
assert(endsWith(inputSource([control '/Current_Loop_i1/Error_id'], 2), ...
    '/i1_d'), 'The d-axis current loop is not fed back by i1_d.');
assert(endsWith(inputSource([control '/Current_Loop_i1/Error_iq'], 2), ...
    '/i1_q'), 'The q-axis current loop is not fed back by i1_q.');
assert(strcmp(get_param([control '/Droop_Control/P_f_droop'], 'Gain'), ...
    '-GFM_Droop.mp'), 'The P-f droop sign is not negative.');
assert(strcmp(get_param([control '/Droop_Control/Q_E_droop'], 'Gain'), ...
    '-GFM_Droop.nq'), 'The Q-E droop sign is not negative.');

L2_Compensation_Blocks = find_system(control, 'LookUnderMasks', 'all', ...
    'FollowLinks', 'on', 'Regexp', 'on', 'Name', '(?i)L2.*comp');
assert(isempty(L2_Compensation_Blocks), ...
    'An L2 voltage-drop compensation block was found unexpectedly.');

Stop_Time = evalin('base', 'GFM_Sim.validation_stop_time');
Simulation_Output = sim(Model_Name, ...
    'Stop_Time', num2str(Stop_Time, 17), ...
    'ReturnWorkspaceOutputs', 'on');

Signal_Names = {'P_pu', 'Q_pu', 'omega_ref', 'f_ref', 'theta_ref', ...
    'E_ref_pu', 'vC_d_ref', 'vC_q_ref', 'vC_d', 'vC_q', ...
    'i1_d_ref', 'i1_q_ref', 'i1_d', 'i1_q', 'i2_d', 'i2_q', ...
    'vPCC_mag', 'modulation_abc', 'duty_abc'};
for k = 1:numel(Signal_Names)
    value = Simulation_Output.get(Signal_Names{k});
    assert(isa(value, 'timeseries'), ...
        'Logged signal %s is missing or is not a timeseries.', ...
        Signal_Names{k});
    assert(all(isfinite(value.Data(:))), ...
        'Logged signal %s contains NaN or Inf.', Signal_Names{k});
end

Tail_Start = max(0, Stop_Time-0.05);
Tail_Time = linspace(Tail_Start, Stop_Time, 1001).';
Ppu = sampleTimeseries(Simulation_Output.get('P_pu'), Tail_Time);
Qpu = sampleTimeseries(Simulation_Output.get('Q_pu'), Tail_Time);
Omega_Reference = sampleTimeseries(Simulation_Output.get('omega_ref'), Tail_Time);
F_Reference = sampleTimeseries(Simulation_Output.get('f_ref'), Tail_Time);
Eref = sampleTimeseries(Simulation_Output.get('E_ref_pu'), Tail_Time);
V_Cd_Reference = sampleTimeseries(Simulation_Output.get('vC_d_ref'), Tail_Time);
V_Cq_Reference = sampleTimeseries(Simulation_Output.get('vC_q_ref'), Tail_Time);
V_Cd = sampleTimeseries(Simulation_Output.get('vC_d'), Tail_Time);
V_Cq = sampleTimeseries(Simulation_Output.get('vC_q'), Tail_Time);
I1d_Reference = sampleTimeseries(Simulation_Output.get('i1_d_ref'), Tail_Time);
I1q_Reference = sampleTimeseries(Simulation_Output.get('i1_q_ref'), Tail_Time);
i1d = sampleTimeseries(Simulation_Output.get('i1_d'), Tail_Time);
i1q = sampleTimeseries(Simulation_Output.get('i1_q'), Tail_Time);
V_PCC_Magnitude = sampleTimeseries( ...
    Simulation_Output.get('vPCC_mag'), Tail_Time);

droop = evalin('base', 'GFM_Droop');
Voltage_Base_Peak = evalin('base', 'V_base_phase');
Current_Base_Peak = sqrt(2)*evalin('base', 'I_base');

Expected_Omega = min(max(droop.w0 ...
    - droop.mp*(Ppu-droop.Pref_pu), droop.w_min), droop.w_max);
Expected_E = min(max(1-droop.nq*(Qpu-droop.Qref_pu), ...
    droop.E_min_pu), droop.E_max_pu);

Omega_Droop_Residual = max(abs(Omega_Reference-Expected_Omega));
Frequency_Residual = max(abs(F_Reference-Omega_Reference/(2*pi)));
Voltage_Droop_Residual = max(abs(Eref-Expected_E));
V_C_Tracking_Error_PU = rms(hypot(V_Cd_Reference-V_Cd, V_Cq_Reference-V_Cq)) ...
    / Voltage_Base_Peak;
I1_Tracking_Error_PU = rms(hypot(I1d_Reference-i1d, I1q_Reference-i1q)) ...
    / Current_Base_Peak;
L2_Voltage_Difference_PU = rms(hypot(V_Cd, V_Cq)-V_PCC_Magnitude) ...
    / Voltage_Base_Peak;

modulation = Simulation_Output.get('modulation_abc').Data;
duty = Simulation_Output.get('duty_abc').Data;
assert(Omega_Droop_Residual < 1e-8, ...
    'The logged P-f droop equation residual is too large.');
assert(Frequency_Residual < 1e-10, ...
    'f_ref is inconsistent with omega_ref.');
assert(Voltage_Droop_Residual < 1e-10, ...
    'The logged Q-E droop equation residual is too large.');
assert(V_C_Tracking_Error_PU < 0.01, ...
    'The tail vC tracking error exceeds 0.01 p.u.');
assert(I1_Tracking_Error_PU < 0.01, ...
    'The tail i1 tracking error exceeds 0.01 p.u.');
assert(L2_Voltage_Difference_PU > 1e-5, ...
    'vC and PCC voltage are unexpectedly identical; inspect L2 handling.');
assert(max(abs(modulation(:))) <= 1+1e-9, ...
    'The modulation command exceeds its configured limits.');
assert(min(duty(:)) >= -1e-9 && max(duty(:)) <= 1+1e-9, ...
    'The duty command is outside [0, 1].');

theta = Simulation_Output.get('theta_ref');
assert(abs(theta.Data(1)-droop.theta0) < 1e-12, ...
    'theta_ref does not start from GFM_Droop.theta0.');
assert(abs(Omega_Reference(1)-droop.w0) < 2*pi*0.1, ...
    'omega_ref initialization is inconsistent with w0.');
assert(abs(Eref(1)-1) < 0.01, ...
    'E_ref_pu initialization is inconsistent with 1 p.u.');

report = struct();
report.ParameterScriptPassed = true;
report.CompilePassed = true;
report.SimulationPassed = true;
report.StopTime = Stop_Time;
report.DisconnectedLineCount = numel(Disconnected_Lines);
report.DuplicateGotoTags = Duplicate_Goto_Tags;
report.AlgebraicLoopCount = numel(Algebraic_Loops);
report.PLLBlockCount = numel(PLL_Blocks);
report.PDroopSlopeRadPerSecPerPu = -droop.mp;
report.QDroopSlopePuPerPu = -droop.nq;
report.OmegaDroopResidual = Omega_Droop_Residual;
report.VoltageDroopResidual = Voltage_Droop_Residual;
report.VCTrackingErrorPu = V_C_Tracking_Error_PU;
report.I1TrackingErrorPu = I1_Tracking_Error_PU;
report.L2VoltageDifferencePu = L2_Voltage_Difference_PU;
report.ModulationMaximum = max(abs(modulation(:)));
report.DutyMinimum = min(duty(:));
report.DutyMaximum = max(duty(:));
report.PTailMeanPu = mean(Ppu);
report.QTailMeanPu = mean(Qpu);
report.FrequencyTailMeanHz = mean(F_Reference);
report.ErefTailMeanPu = mean(Eref);

assignin('base', 'GFM_Validation_Report', report);

fprintf('GFM validation passed.\n');
fprintf('  Compile/simulation: PASS / PASS (%.3g s)\n', Stop_Time);
fprintf('  Algebraic loops / PLL blocks: %d / %d\n', ...
    report.AlgebraicLoopCount, report.PLLBlockCount);
fprintf('  Tail vC / i1 tracking error: %.6g / %.6g p.u.\n', ...
    report.VCTrackingErrorPu, report.I1TrackingErrorPu);
fprintf('  Tail P / Q: %.6g / %.6g p.u.\n', ...
    report.PTailMeanPu, report.QTailMeanPu);
fprintf('  Modulation max, duty range: %.6g, [%.6g, %.6g]\n', ...
    report.ModulationMaximum, report.DutyMinimum, report.DutyMaximum);
clear cleanup
end

function values = sampleTimeseries(signal, Query_Time)
if isscalar(signal.Time)
    sample = reshape(signal.Data, 1, []);
    values = repmat(sample, numel(Query_Time), 1);
else
    values = resample(signal, Query_Time).Data;
end
end

function disconnected = findDisconnectedLines(Model_Name)
Line_Handles = find_system(Model_Name, 'FindAll', 'on', ...
    'LookUnderMasks', 'none', 'FollowLinks', 'off', 'Type', 'line');
disconnected = zeros(0, 1);
for k = 1:numel(Line_Handles)
    source = get_param(Line_Handles(k), 'SrcBlockHandle');
    destinations = get_param(Line_Handles(k), 'DstBlockHandle');
    if source == -1 || isempty(destinations) || any(destinations == -1)
        Source_Port = get_param(Line_Handles(k), 'SrcPortHandle');
        Destination_Ports = get_param(Line_Handles(k), 'DstPortHandle');
        Connected_Ports = [Source_Port; Destination_Ports(:)];
        Connected_Ports = Connected_Ports(Connected_Ports ~= -1);
        Is_Physical_Connection = ~isempty(Connected_Ports);
        for Port_Index = 1:numel(Connected_Ports)
            Is_Physical_Connection = Is_Physical_Connection && strcmp( ...
                get_param(Connected_Ports(Port_Index), 'PortType'), ...
                'connection');
        end
        if ~Is_Physical_Connection && ~isempty(Connected_Ports)
            disconnected(end+1, 1) = Line_Handles(k); %#ok<AGROW>
        end
    end
end
end

function blocks = findPllBlocks(System_Path)
All_Blocks = find_system(System_Path, 'LookUnderMasks', 'all', ...
    'FollowLinks', 'on', 'Type', 'Block');
Is_PLL = false(size(All_Blocks));
for k = 1:numel(All_Blocks)
    name = get_param(All_Blocks{k}, 'Name');
    Mask_Type = get_param(All_Blocks{k}, 'MaskType');
    Is_PLL(k) = contains(name, 'PLL', 'IgnoreCase', true) ...
        || contains(Mask_Type, 'PLL', 'IgnoreCase', true);
end
blocks = All_Blocks(Is_PLL);
end

function source = inputSource(Block_Path, Port_Number)
ports = get_param(Block_Path, 'PortHandles');
line = get_param(ports.Inport(Port_Number), 'Line');
assert(line ~= -1, 'Input %d of %s is disconnected.', ...
    Port_Number, Block_Path);
Source_Handle = get_param(line, 'SrcBlockHandle');
source = getfullname(Source_Handle);
end

function values = getStringParameters(blocks, parameter)
if isempty(blocks)
    values = {};
    return;
end
values = get_param(blocks, parameter);
if ischar(values)
    values = {values};
end
values = values(:);
end

function closeIfLoaded(Model_Name)
if bdIsLoaded(Model_Name)
    close_system(Model_Name, 0);
end
end

function text = escapeQuotes(text)
text = strrep(text, '''', '''''');
end
