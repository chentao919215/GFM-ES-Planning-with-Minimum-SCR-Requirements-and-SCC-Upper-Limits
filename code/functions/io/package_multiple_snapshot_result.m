function Result = package_multiple_snapshot_result( ...
    SCC_1,SCC_TimeResolved,P_Line,theta,P_G,P_GFL,P_GFM,SCR, ...
    SCR_TimeResolved,Z_SCC,Z_SCR,u_G,u_G_SCC,u_G_SCR, ...
    Cost_CON,Cost_GEN,Cost_Total,Solve_Time,CONF,Diagnostics, ...
    u_GFM_Module,P_GFM_Dis,P_GFM_Ch,E_GFM,u_GFM_Ch,P_GFL_Curt, ...
    Cost_Curt,u_G_Start,u_G_Stop,Cost_UC,SecurityValidation)
%% Organize one multiple-snapshot solve into the persisted result schema.

Cost = struct();
Cost.Total = Cost_Total;
Cost.GEN   = Cost_GEN;
Cost.CON   = Cost_CON;
Cost.Curt  = Cost_Curt;
Cost.UC    = Cost_UC;
Cost.Unit  = 'annual';
Cost.CON_Definition = ...
    'GFM-ES annual fixed cost including annualized investment and fixed O&M';

if ~isfield(Diagnostics,'ConfigurationSelection')
    error('ResultPackaging:MissingConfigurationSelection', ...
        'Diagnostics must contain the final configuration-selection vector.');
end

Result = struct();
Result.SCC_1              = SCC_1;
Result.SCC_TimeResolved   = SCC_TimeResolved;
Result.P_Line             = P_Line;
Result.theta              = theta;
Result.P_G                = P_G;
Result.P_GFL              = P_GFL;
Result.P_GFL_Curt         = P_GFL_Curt;
Result.P_GFM              = P_GFM;
Result.SCR                = SCR;
Result.SCR_TimeResolved   = SCR_TimeResolved;
% Aggregate SCC/SCR impedances retain typical day as their last dimension.
% Z_SCR columns correspond only to built GFL-WG buses.
Result.Z_SCC              = Z_SCC;
Result.Z_SCR              = Z_SCR;
Result.u_G                = u_G;
Result.u_G_Start          = u_G_Start;
Result.u_G_Stop           = u_G_Stop;
Result.u_G_SCC            = u_G_SCC;
Result.u_G_SCR            = u_G_SCR;
Result.u_GFM_Mod          = u_GFM_Module;
Result.lambda_c           = Diagnostics.ConfigurationSelection;
% Scenario-dependent storage results use
% [candidate, typical_day, wind_scenario, period].
Result.P_GFM_Dis          = P_GFM_Dis;
Result.P_GFM_Ch           = P_GFM_Ch;
Result.E_GFM              = E_GFM;
Result.u_GFM_Ch           = u_GFM_Ch;
Result.Cost               = Cost;
Result.solve_time         = Solve_Time;
Result.SecurityValidation = SecurityValidation;

% MIPStart is an input-side cache that repeats discrete arrays and is not
% needed to reproduce or analyze the final solution.
Saved_CONF = CONF;
if isfield(Saved_CONF,'MIPStart')
    Saved_CONF = rmfield(Saved_CONF,'MIPStart');
end
Result.CONF = Saved_CONF;

% Keep one authoritative copy of each item. ConfigurationSelection is a
% final planning decision (Result.lambda_c); catalog matrices live in CONF;
% ConfigurationAllowed remains a compact solver diagnostic. Offline state
% catalogs and online auxiliary-variable values are intentionally omitted.
Diagnostics = remove_fields_if_present(Diagnostics,{ ...
    'ConfigurationSelection', ...
    'ConfigurationModuleStatus', ...
    'ConfigurationCandidateStatus', ...
    'ConfigurationModuleCount', ...
    'ValidStatePairs', ...
    'ValidSCRStates', ...
    'InvalidStatePairs', ...
    'InvalidSCRStates', ...
    'StateCatalog', ...
    'LVRTIncrementCurrent', ...
    'LVRTResidualVoltage', ...
    'FaultTransferAllocation', ...
    'SCCTransferTermScaled', ...
    'Tau_GFL_Scaled'});
Result.Diagnostics = Diagnostics;

Dimensions = struct();
Dimensions.SharedUC = {'generator','typical_day','period'};
Dimensions.ScenarioGeneratorDispatch = ...
    {'generator','typical_day','wind_scenario','period'};
Dimensions.ScenarioNodeOperation = ...
    {'node','typical_day','wind_scenario','period'};
Dimensions.ScenarioGFMOperation = ...
    {'gfm_candidate','typical_day','wind_scenario','period'};
Dimensions.SafetyState = {'generator','typical_day'};
Dimensions.AggregatedSCC = {'original_node','typical_day'};
Dimensions.AggregatedSCR = {'original_node','typical_day'};
Dimensions.SCC_TimeResolved = ...
    {'period','typical_day','scc_security_node'};
Dimensions.SCR_TimeResolved = ...
    {'period','typical_day','gfl_node'};
Result.Dimensions = Dimensions;

SCC_Definition = struct();
SCC_Definition.SCC_1 = [ ...
    'Typical-day aggregate conservative SCC upper bound from the SG-union ', ...
    'state; it is not an actual hourly SCC.'];
SCC_Definition.SCC_TimeResolved = [ ...
    'Posterior SCC recalculated from the final GFM-ES build and actual ', ...
    'hourly SG state with the Section II-C lossless network and GFL-WG LVRT.'];
SCC_Definition.SCC_1_Node_Order = 'MATPOWER original bus order';
SCC_Definition.SCC_TimeResolved_Node_Order = ...
    CONF.SCC_Constraint_Original_Nodes(:);
SCC_Definition.SCC_1_Dimension_Order = ...
    {'original_node','typical_day'};
SCC_Definition.SCC_TimeResolved_Dimension_Order = ...
    {'period','typical_day','scc_security_node'};
SCC_Definition.Unit = 'kA';
SCC_Definition.Base_Current_kA = CONF.Base_kA;
SCC_Definition.SCC_1_Non_Safety_Node_Value = 0;
Result.SCC_Definition = SCC_Definition;

SCR_Definition = struct();
SCR_Definition.SCR = [ ...
    'Typical-day aggregate classic-SCR lower bound from the SG-intersection ', ...
    'state; it is not an actual hourly SCR.'];
SCR_Definition.SCR_TimeResolved = [ ...
    'Posterior classic SCR recalculated from the final GFM-ES build and ', ...
    'actual hourly SG state.'];
SCR_Definition.SCR_Node_Order = 'MATPOWER original bus order';
SCR_Definition.SCR_TimeResolved_Node_Order = ...
    CONF.Safety_GFL_Original_Nodes(:);
SCR_Definition.SCR_Dimension_Order = ...
    {'original_node','typical_day'};
SCR_Definition.SCR_TimeResolved_Dimension_Order = ...
    {'period','typical_day','gfl_node'};
SCR_Definition.Capacity_Base = ...
    'GFL-WG rated capacity CONF.PN_GFL_pu_Node on system MVA base';
SCR_Definition.Unit = 'dimensionless';
Result.SCR_Definition = SCR_Definition;

% Explicit original/reduced-node mappings make every security array and
% aggregate impedance column independently interpretable.
Safety_Network = struct();
Safety_Network.RetainedOriginalNodes = CONF.Safety_Retained_Nodes(:);
Safety_Network.OriginalToReduced = CONF.Safety_Original_To_Reduced(:);
Safety_Network.SCCColumnOriginalNodes = CONF.Safety_Retained_Nodes(:);
Safety_Network.SCCConstraintOriginalNodes = ...
    CONF.SCC_Constraint_Original_Nodes(:);
Safety_Network.SCCTimeResolvedOriginalNodes = ...
    CONF.SCC_Constraint_Original_Nodes(:);
Safety_Network.SCRColumnOriginalNodes = ...
    CONF.Safety_GFL_Original_Nodes(:);
Safety_Network.SCRColumnReducedIndices = ...
    CONF.Safety_GFL_Reduced_Indices(:);
Safety_Network.SCRTimeResolvedOriginalNodes = ...
    CONF.Safety_GFL_Original_Nodes(:);
Safety_Network.TypicalDayCount = CONF.TypicalDayCount;
Safety_Network.PeriodCount = CONF.PeriodCount;
Safety_Network.AggregationScope = 'within_each_typical_day';
Safety_Network.SusceptanceDefinition = 'B = imag(Y)';
Safety_Network.PassiveNetworkApproximation = ...
    'lossless inductive; line series resistance and shunt susceptance neglected';
Safety_Network.SCCStateDimensions = {'generator','typical_day'};
Safety_Network.SCRStateDimensions = {'generator','typical_day'};
Safety_Network.SCCImpedanceDimensions = ...
    {'retained_node','retained_node','typical_day'};
Safety_Network.SCRImpedanceDimensions = ...
    {'retained_node','gfl_column','typical_day'};
Result.SafetyNetwork = Safety_Network;

Timing_Definition = struct();
Timing_Definition.solve_time = [ ...
    'Wall-clock seconds from entry to solve_multiple_snapshot_planning ', ...
    'through model construction, optimization, result extraction, and ', ...
    'time-resolved security post-processing; excludes packaging and save I/O.'];
Timing_Definition.Diagnostics_solvertime = ...
    'Solver-reported optimization engine time in seconds.';
Timing_Definition.Diagnostics_yalmiptime = ...
    'YALMIP-reported optimize-call overhead in seconds.';
Result.TimingDefinition = Timing_Definition;

end

function Input = remove_fields_if_present(Input, Field_Names)
%% Remove fields without requiring every legacy result path to define them.

Present = Field_Names(isfield(Input,Field_Names));
if ~isempty(Present)
    Input = rmfield(Input,Present);
end

end
