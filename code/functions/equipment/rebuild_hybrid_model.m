function rebuild_hybrid_model()
%REBUILD_HYBRID_MODEL Rebuild the SPS three-node hybrid source model.
%
% The original hybrid file contained several zero-length graphical
% connection segments.  Those segments cannot be deleted reliably by the
% Simulink API, so this helper copies the existing blocks into a clean model,
% reconnects the physical network, validates the diagram, and only then
% saves the requested target file.

Project_Root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
Source_File = fullfile(Project_Root,'simulink','models', ...
    'Grid_Following_Inverter_Generator.slx');
Target_File = Source_File;
Source_Model = 'Grid_Following_Inverter_Generator';
tmp = 'Grid_Following_Inverter_Generator__rebuild__';

if bdIsLoaded(tmp)
    close_system(tmp,0);
end
load_system(Source_File);
Parameter_File = fullfile(Project_Root,'code','scripts','equipment', ...
    'Invert_Generator_Parameters.m');
% SPS mask expressions are evaluated in the base workspace, therefore the
% merged parameter script must also be evaluated there.
evalin('base',sprintf('run(''%s'');',strrep(Parameter_File,'''','''''')));

new_system(tmp);
Block_Names = { ...
    'Electrical Ground', ...
    'GFL_1', ...
    'Grid Controlled Voltage Source A', ...
    'Grid Controlled Voltage Source B', ...
    'Grid Controlled Voltage Source C', ...
    'Grid Voltage Command A', ...
    'Grid Voltage Command B', ...
    'Grid Voltage Command C', ...
    'Internal Voltage E pu', ...
    'Machine Terminal V-I Measurement', ...
    'Machine Terminal V-I Measurement1', ...
    'Mechanical Speed w', ...
    'Synchronous Machine', ...
    'Three-Phase Fault', ...
    'Z_th', ...
    'z_12', ...
    'z_13', ...
    'z_23', ...
    'powergui'};

for k = 1:numel(Block_Names)
    name = Block_Names{k};
    Source_Path = [Source_Model '/' name];
    Destination_Path = [tmp '/' name];
    add_block(srcPath,Destination_Path);
    set_param(Destination_Path,'Position',get_param(Source_Path,'Position'));
end

% Insert a non-invasive three-phase V-I measurement in the fault lead so
% the fault-point current is available as a recorded Simulink signal.
Fault_Measurement_Path = [tmp '/Fault V-I Measurement'];
add_block([tmp '/Machine Terminal V-I Measurement'],Fault_Measurement_Path, ...
    'Position',[700 340 790 430]);
set_param(Fault_Measurement_Path,'VoltageMeasurement','phase-to-ground', ...
    'CurrentMeasurement','yes','Pbase','S_B','Vbase','V_B_LL', ...
    'OutputType','Complex','PhasorSimulation','off');

% Add three-phase V-I measurements in the three branches incident on node 3.
% Their electrical ports are inserted in series without changing branch
% impedance values.  These signals are used only for the node-3 KCL audit.
Line13_Measurement_Path = [tmp '/Line13 V-I Measurement'];
Line23_Measurement_Path = [tmp '/Line23 V-I Measurement'];
Grid_Th_Measurement_Path = [tmp '/GridTh V-I Measurement'];
for Measurement_Path = {Line13_Measurement_Path,Line23_Measurement_Path,Grid_Th_Measurement_Path}
    add_block([tmp '/Machine Terminal V-I Measurement'],Measurement_Path{1}, ...
        'Position',[900 340 990 430]);
    set_param(Measurement_Path{1},'VoltageMeasurement','phase-to-ground', ...
        'CurrentMeasurement','yes','Pbase','S_B','Vbase','V_B_LL', ...
        'OutputType','Complex','PhasorSimulation','off');
end

% The three line blocks are deliberately parameterized from the unified
% hybrid script.  The same values are also used by the report calculation.
set_param([tmp '/z_12'],'BranchType','RL', ...
    'Resistance','R12_ohm','Inductance','L12_H');
set_param([tmp '/z_13'],'BranchType','RL', ...
    'Resistance','R13_ohm','Inductance','L13_H');
set_param([tmp '/z_23'],'BranchType','RL', ...
    'Resistance','R23_ohm','Inductance','L23_H');
set_param([tmp '/Z_th'],'BranchType','RL', ...
    'Resistance','Rth_ohm','Inductance','Lth_H');

% Preserve the intended subtransient terminal snapshot of the simplified
% synchronous machine rather than enabling a full electromagnetic model.
set_param([tmp '/Synchronous Machine'], ...
    'NominalParameters','[S_N V_N f_N]', ...
    'Mechanical','[H_machine D_machine pole_pairs]', ...
    'InternalRL','[R_a X_dpp]', ...
    'InitialConditions','machine_initial_conditions', ...
    'TsPowergui','powergui_sample_time', ...
    'Pref','P_0','Qref','Q_0');

set_param([tmp '/Three-Phase Fault'], ...
    'SwitchTimes','[t_fault t_clear]', ...
    'FaultResistance','R_fault','GroundResistance','R_fault', ...
    'Measurements','None');
for tag = {'A','B','C'}
    s = ['Grid Controlled Voltage Source ' tag{1}];
    set_param([tmp '/' s],'Amplitude','E_grid_peak', ...
        'Phase','grid_phase_deg', 'Frequency','f0');
end
set_param([tmp '/Grid Controlled Voltage Source B'], ...
    'Phase','grid_phase_deg-120');
set_param([tmp '/Grid Controlled Voltage Source C'], ...
    'Phase','grid_phase_deg+120');
% Simulink Sine Wave Frequency is angular frequency (rad/s), unlike the
% SPS controlled source Frequency parameter below, which uses Hz.
set_param([tmp '/Grid Voltage Command A'],'Amplitude','E_grid_peak', ...
    'Phase','deg2rad(grid_phase_deg)','Frequency','omega0');
set_param([tmp '/Grid Voltage Command B'],'Amplitude','E_grid_peak', ...
    'Phase','deg2rad(grid_phase_deg-120)','Frequency','omega0');
set_param([tmp '/Grid Voltage Command C'],'Amplitude','E_grid_peak', ...
    'Phase','deg2rad(grid_phase_deg+120)','Frequency','omega0');
set_param([tmp '/Internal Voltage E pu'],'Value','E_internal_pu');
set_param([tmp '/Mechanical Speed w'],'Value','speed_pu');

% Numerical SPS regularization: the GFL filter-side voltage source and the
% synchronous current source can otherwise be detected as a pure series
% source/inductor path during topology compilation.  A 1 Mohm three-phase
% resistor in parallel with the existing L2 branch is electrically
% negligible at the 38.5 kV, 100 MVA base, but supplies the high-value
% snubber requested by the SPS compiler without changing z12/z13/z23/Zth.
L2_Path = [tmp '/GFL_1/Three-Phase L2'];
L2_Snubber_Path = [tmp '/GFL_1/L2_Parallel_R'];
L2_Snubber_Exists = ~isempty(find_system([tmp '/GFL_1'],'SearchDepth',1,'Type','Block', ...
        'Name','L2_Parallel_R'));
if ~L2_Snubber_Exists
    add_block('sps_lib/Passives/Three-Phase Parallel RLC Branch',L2_Snubber_Path, ...
        'Position',[700 610 790 670]);
end
set_param(L2_Snubber_Path,'BranchType','R', ...
    'Resistance','SPS_high_value_parallel_R','Measurements','None');
L2_Ports = get_param(L2_Path,'PortHandles');
Snubber_Ports = get_param(L2_Snubber_Path,'PortHandles');
if ~L2_Snubber_Exists
    for ph = 1:3
        add_line([tmp '/GFL_1'],Snubber_Ports.LConn(ph),L2_Ports.LConn(ph), ...
            'autorouting','on');
        add_line([tmp '/GFL_1'],Snubber_Ports.RConn(ph),L2_Ports.RConn(ph), ...
            'autorouting','on');
    end
end

% Keep the reference model's discrete sample time and TBE powergui solver.
% The hybrid model is discrete because its SPS current-source/inverter
% topology cannot be updated in the reference model's continuous mode.
pg = [tmp '/powergui'];
set_param(pg,'SimulationMode','Discrete', ...
    'SampleTime','powergui_sample_time', ...
    'SolverType','Tustin/Backward Euler (TBE)', ...
    'frequency','f0','fundamental','f0','Pbase','S_B');
set_param(tmp,'Solver','ode3','FixedStep','powergui_sample_time', ...
    'Stop_Time','t_stop','SimulationMode','normal');

% Model-startup path setup.  The helper is intentionally called from the
% model's InitFcn so the model remains independently runnable.
Init_Fcn = sprintf([ ...
    'Model_File = get_param(bdroot,''FileName'');' ...
    'Project_Root = fileparts(fileparts(fileparts(Model_File)));' ...
    'addpath(fullfile(Project_Root,''code'',''functions'',''equipment''));' ...
    'addpath(fullfile(Project_Root,''code'',''scripts'',''equipment''));' ...
    'run(fullfile(Project_Root,''code'',''scripts'',''equipment'',' ...
    '''Invert_Generator_Parameters.m''));' ...
    'configure_hybrid_report_signals(bdroot);' ...
    'configure_simulink_file_generation_from_model(bdroot);']);
% The temporary in-memory model has no FileName yet, so defer installing the
% InitFcn until after the first save establishes the target path.

% Signal/control connections that existed in the source model.
Source_H = get_param([tmp '/Mechanical Speed w'],'PortHandles');
Destination_H = get_param([tmp '/Synchronous Machine'],'PortHandles');
add_line(tmp,Source_H.Outport(1),Destination_H.Inport(1),'autorouting','off');
Source_H = get_param([tmp '/Internal Voltage E pu'],'PortHandles');
add_line(tmp,Source_H.Outport(1),Destination_H.Inport(2),'autorouting','off');
for tag = {'A','B','C'}
    cmd = get_param([tmp '/Grid Voltage Command ' tag{1}],'PortHandles');
    vsrc = get_param([tmp '/Grid Controlled Voltage Source ' tag{1}],'PortHandles');
    add_line(tmp,cmd.Outport(1),vsrc.Inport(1),'autorouting','off');
end

% Direct physical connections.  These are created before branches so the
% branch endpoints can be snapped to the exact line geometry.
machine = get_param([tmp '/Synchronous Machine'],'PortHandles');
gfl = get_param([tmp '/GFL_1'],'PortHandles');
meas1 = get_param([tmp '/Machine Terminal V-I Measurement'],'PortHandles');
meas2 = get_param([tmp '/Machine Terminal V-I Measurement1'],'PortHandles');
z12 = get_param([tmp '/z_12'],'PortHandles');
z13 = get_param([tmp '/z_13'],'PortHandles');
z23 = get_param([tmp '/z_23'],'PortHandles');
zth = get_param([tmp '/Z_th'],'PortHandles');
fault = get_param([tmp '/Three-Phase Fault'],'PortHandles');
Fault_Measurement = get_param(Fault_Measurement_Path,'PortHandles');
Line13_Measurement = get_param(Line13_Measurement_Path,'PortHandles');
Line23_Measurement = get_param(Line23_Measurement_Path,'PortHandles');
Grid_Th_Measurement = get_param(Grid_Th_Measurement_Path,'PortHandles');
ground = get_param([tmp '/Electrical Ground'],'PortHandles');

for ph = 1:3
    add_line(tmp,machine.RConn(ph),meas1.LConn(ph),'autorouting','off');
    add_line(tmp,gfl.RConn(ph),meas2.LConn(ph),'autorouting','off');
    add_line(tmp,fault.LConn(ph),Fault_Measurement.LConn(ph),'autorouting','off');
    % For conserving ports, an unconnected port can be added to an already
    % occupied physical node.  Automatic routing creates the actual physical
    % branch; a hand-drawn coordinate line would only be a graphic stub.
    % The z12/z23/fault ports are deliberately connected while still free.
    add_line(tmp,z13.LConn(ph),meas1.RConn(ph),'autorouting','on');
    add_line(tmp,z23.LConn(ph),meas2.RConn(ph),'autorouting','on');
    add_line(tmp,z13.RConn(ph),Line13_Measurement.LConn(ph),'autorouting','on');
    add_line(tmp,Line13_Measurement.RConn(ph),zth.LConn(ph),'autorouting','on');
    add_line(tmp,z12.LConn(ph),meas1.RConn(ph),'autorouting','on');
    add_line(tmp,z12.RConn(ph),meas2.RConn(ph),'autorouting','on');
    add_line(tmp,z23.RConn(ph),Line23_Measurement.LConn(ph),'autorouting','on');
    add_line(tmp,Line23_Measurement.RConn(ph),zth.LConn(ph),'autorouting','on');
    add_line(tmp,Fault_Measurement.RConn(ph),zth.LConn(ph),'autorouting','on');

    Source_Ports = get_param([tmp '/Grid Controlled Voltage Source ' ...
        char('A'+ph-1)],'PortHandles');
    add_line(tmp,zth.RConn(ph),Grid_Th_Measurement.LConn(ph),'autorouting','off');
    add_line(tmp,Grid_Th_Measurement.RConn(ph),Source_Ports.LConn(1),'autorouting','off');
    % Each single-phase external voltage source uses the common electrical
    % reference on its second conserving port.  Leaving these ports open
    % silently removes the external-grid injection from the fault current.
    add_line(tmp,Source_Ports.RConn(1),ground.LConn(1),'autorouting','on');
end

% The same numerical regularization is applied in parallel with z12.  The
% branch has a negligible admittance on the system base and only prevents
% the SPS compiler from treating the current-source machine and z12 as a
% strict series chain when the physical node has multiple branches.
Z12_Snubber_Path = [tmp '/Z12_Parallel_R'];
add_block('sps_lib/Passives/Three-Phase Parallel RLC Branch',Z12_Snubber_Path, ...
    'Position',[460 610 550 670]);
set_param(Z12_Snubber_Path,'BranchType','R', ...
    'Resistance','SPS_high_value_parallel_R','Measurements','None');
Z12_Snubber_Ports = get_param(Z12_Snubber_Path,'PortHandles');
for ph = 1:3
    add_line(tmp,Z12_Snubber_Ports.LConn(ph),meas1.RConn(ph), ...
        'autorouting','on');
    add_line(tmp,Z12_Snubber_Ports.RConn(ph),meas2.RConn(ph), ...
        'autorouting','on');
end

% Final validation is performed before the target file is replaced.  Save
% once without InitFcn to establish a valid FileName for the model callback,
% then install the independent-startup callback and validate again.
set_param(tmp,'SimulationCommand','update');
% The source model and the rebuilt in-memory model intentionally have
% different temporary names, but MATLAB still refuses to save a model to a
% file whose same-named model is open.  Close the read-only source before
% renaming and saving the validated rebuild.
if bdIsLoaded(Source_Model)
    close_system(Source_Model,0);
end
set_param(tmp,'Name',Source_Model);
save_system(Source_Model,Target_File);
set_param(Source_Model,'InitFcn',Init_Fcn);
set_param(Source_Model,'SimulationCommand','update');
save_system(Source_Model,Target_File);
close_system(Source_Model,0);
fprintf('Hybrid model rebuilt and validated: %s\n',Target_File);
end
