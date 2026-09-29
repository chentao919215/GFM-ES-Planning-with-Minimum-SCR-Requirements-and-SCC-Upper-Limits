function [SCC_kA, Details] = calculate_fixed_state_scc( ...
    NET, CONF, Module_State, u_GFL, SG_State, Fault_Nodes, ...
    State_Label, Fixed_State_Network, Enable_Remote_GFM_Limiting)
%% Recalculate SCC at selected fault nodes for one fixed equipment state.
% The returned vector follows Fault_Nodes and is expressed in kA.
% The manuscript's fault-bus-only GFM-ES limiting rule is the default.
% To use remote self-consistent limiting for ex-post fixed/hourly states,
% manually set Consider_Remote_GFM_Limiting below to true. The existing
% optional ninth argument still overrides this default for explicit callers.
% Module-level Details arrays are indexed [module, fault]; residual voltage
% is indexed [original bus, fault]. Unbuilt-module currents remain NaN.

CONF = normalize_multiple_snapshot_conf(CONF);
Consider_Remote_GFM_Limiting = false; % Manual ex-post mode switch.
if nargin < 7 || isempty(State_Label)
    State_Label = 'fixed-state SCC calculation';
end
if nargin < 8 || isempty(Fixed_State_Network)
    Fixed_State_Network = build_fixed_state_safety_network( ...
        NET, CONF, Module_State, SG_State, State_Label);
end
if nargin >= 9 && ~isempty(Enable_Remote_GFM_Limiting)
    Consider_Remote_GFM_Limiting = Enable_Remote_GFM_Limiting;
end
if ~islogical(Consider_Remote_GFM_Limiting) || ...
        ~isscalar(Consider_Remote_GFM_Limiting)
    error('FixedStateSCC:InvalidRemoteLimitingSwitch', ...
        'Remote GFM-ES limiting switch must be a scalar logical value.');
end

N = NET.N;
M = CONF.GFM_Module_Count;
if numel(Module_State) ~= M || numel(u_GFL) ~= N
    error('FixedStateSCC:StateDimensionMismatch', ...
        '%s: GFM-ES or GFL-WG state dimensions do not match the network.', ...
        State_Label);
end
Module_State = validate_binary_result(Module_State(:), ...
    'GFM-ES module build state', State_Label);
u_GFL = validate_binary_result(u_GFL(:), ...
    'GFL-WG node state', State_Label);
Fault_Nodes = validate_node_list(Fault_Nodes, N, ...
    'SCC fault-node list', State_Label);

X_Fault = Fixed_State_Network.X_Fault;
B_Fault = Fixed_State_Network.B_Fault;
Source_Susceptance = Fixed_State_Network.SourceSusceptance;
if ~isequal(size(X_Fault), [N N]) || ~isequal(size(B_Fault), [N N]) || ...
        numel(Source_Susceptance) ~= N
    error('FixedStateSCC:InvalidSharedNetwork', ...
        '%s: the shared fixed-state safety network has invalid dimensions.', ...
        State_Label);
end

% Only the ex-post fault network can switch remote GFM-ES modules to their
% virtual impedance; the online SCC model retains its local-only assumption.
Module_Bus = CONF.GFM_Module_Bus(:);
X_GFM_Normal = CONF.GFM_Module_X_Res(:);
X_GFM_Virtual = CONF.GFM_Module_X_Vir(:);
Module_PN_PU = CONF.GFM_Module_PN_pu(:);
Current_Limit_ModulePU = CONF.GFM_Module_I_Post_Multiplier(:);
if any([numel(Module_Bus),numel(X_GFM_Normal), ...
        numel(X_GFM_Virtual),numel(Module_PN_PU), ...
        numel(Current_Limit_ModulePU)] ~= M) || ...
        any(~isfinite(X_GFM_Normal)) || any(X_GFM_Normal <= 0) || ...
        any(~isfinite(X_GFM_Virtual)) || any(X_GFM_Virtual < 0) || ...
        any(~isfinite(Module_PN_PU)) || any(Module_PN_PU <= 0) || ...
        any(~isfinite(Current_Limit_ModulePU)) || ...
        any(Current_Limit_ModulePU <= 0)
    error('FixedStateSCC:InvalidGFMCurrentBase', ...
        '%s: GFM-ES module reactance, rating, or current limit is invalid.', ...
        State_Label);
end
Current_Tolerance_ModulePU = 1e-8*max(1,Current_Limit_ModulePU);
GFM_Delta_Node = CONF.GFM_Module_Loc_Mat * ...
    (CONF.GFM_Module_DeltaY_abs(:).*Module_State);
GFL_Fault_Increment_Node = CONF.Delta_I_GFL_pu_Node(:).*u_GFL;
GFL_Nodes = find(u_GFL > 0.5);
SCC_kA = zeros(numel(Fault_Nodes),1);
Details = struct();
Details.FaultNodes = Fault_Nodes;
Details.LVRTIncrementCurrent = zeros(N,numel(Fault_Nodes));
Details.TransferCurrent = zeros(numel(Fault_Nodes),1);
Details.SelfReactance = zeros(numel(Fault_Nodes),1);
Details.GFMLimitingByModule = false(M,numel(Fault_Nodes));
Details.GFMUnlimitedCurrentModulePU = nan(M,numel(Fault_Nodes));
Details.GFMModuleBus = Module_Bus;
Details.GFMCurrentLimitModulePU = Current_Limit_ModulePU;
Details.GFMCurrentToleranceModulePU = Current_Tolerance_ModulePU;
Details.ResidualVoltage = nan(N,numel(Fault_Nodes));
Details.HasRemoteGFMLimiting = false(1,numel(Fault_Nodes));
Details.CandidateReports = cell(1,numel(Fault_Nodes));

for Fault_Index = 1:numel(Fault_Nodes)
    Fault_Node = Fault_Nodes(Fault_Index);
    if Consider_Remote_GFM_Limiting && any(Module_State)
        [Fault_Network, Delta_I_LVRT, Residual_Voltage, ...
            Limited_Modules, Unlimited_Current, Candidate_Reports] = ...
            select_consistent_gfm_fault_state( ...
            NET, CONF, Module_State, SG_State, Fault_Node, GFL_Nodes, ...
            State_Label, Fixed_State_Network, Module_Bus, ...
            X_GFM_Normal, X_GFM_Virtual, Module_PN_PU, ...
            Current_Limit_ModulePU, Current_Tolerance_ModulePU);
    else
        Fault_Network = Fixed_State_Network;
        Limited_Modules = logical(Module_State & Module_Bus == Fault_Node);
        Unlimited_Current = nan(M,1);
        if any(Module_State)
            Candidate_Reports = { ...
                'local-only SCC rule; remote GFM limiting not evaluated'};
        else
            Candidate_Reports = {'no GFM-ES modules installed'};
        end
        try
            [Delta_I_LVRT, Residual_Voltage] = ...
                solve_lvrt_increment_current(B_Fault, ...
                Source_Susceptance, Fault_Node, GFL_Nodes, CONF);
        catch Cause
            Context = MException('FixedStateSCC:LVRTFailure', ...
                '%s: LVRT solution failed for fault bus %d.', ...
                State_Label, Fault_Node);
            throwAsCaller(addCause(Context,Cause));
        end
    end

    X_Fault_State = Fault_Network.X_Fault;
    X_Self = X_Fault_State(Fault_Node,Fault_Node);
    if ~isfinite(X_Self) || X_Self <= 0
        error('FixedStateSCC:InvalidSelfReactance', ...
            '%s: bus %d has invalid self reactance %.15g p.u.', ...
            State_Label, Fault_Node, X_Self);
    end

    Nonfault_GFL_Nodes = GFL_Nodes(GFL_Nodes ~= Fault_Node);
    Transfer_Current = 0;
    for GFL_Node = reshape(Nonfault_GFL_Nodes,1,[])
        Transfer_Current = Transfer_Current + ...
            X_Fault_State(Fault_Node,GFL_Node)/X_Self* ...
            Delta_I_LVRT(GFL_Node);
    end

    Details.LVRTIncrementCurrent(:,Fault_Index) = Delta_I_LVRT;
    Details.TransferCurrent(Fault_Index) = Transfer_Current;
    Details.SelfReactance(Fault_Index) = X_Self;
    Details.GFMLimitingByModule(:,Fault_Index) = Limited_Modules;
    Details.GFMUnlimitedCurrentModulePU(:,Fault_Index) = ...
        Unlimited_Current;
    Details.ResidualVoltage(:,Fault_Index) = Residual_Voltage;
    Details.HasRemoteGFMLimiting(Fault_Index) = any( ...
        Limited_Modules & Module_Bus ~= Fault_Node);
    Details.CandidateReports{Fault_Index} = Candidate_Reports;

    % Under remote limiting, the final network includes every switched
    % admittance. The local-only path retains the original diagonal rule.
    Local_Correction = 0;
    if ~Consider_Remote_GFM_Limiting
        Local_Correction = GFM_Delta_Node(Fault_Node);
    end
    SCC_PU = 1/X_Self-Local_Correction + ...
        GFL_Fault_Increment_Node(Fault_Node)+Transfer_Current;
    if ~isfinite(SCC_PU) || SCC_PU < 0
        error('FixedStateSCC:InvalidSCC', ...
            '%s: fault bus %d gives invalid SCC %.15g p.u.', ...
            State_Label, Fault_Node, SCC_PU);
    end
    SCC_kA(Fault_Index) = SCC_PU*CONF.Base_kA;
end

end

function [Fault_Network, Delta_I, Voltage, Limited_Modules, ...
    Unlimited_Current, Candidate_Reports] = ...
    select_consistent_gfm_fault_state( ...
    NET, CONF, Module_State, SG_State, Fault_Node, GFL_Nodes, ...
    State_Label, Normal_Network, Module_Bus, X_Normal, X_Virtual, ...
    Module_PN_PU, Current_Limit, Current_Tolerance)
%% Enumerate remote GFM-ES limiting states and retain the unique fixed point.

M = numel(Module_State);
Built_Modules = find(Module_State);
Fault_Modules = Built_Modules(Module_Bus(Built_Modules) == Fault_Node);
Remote_Modules = Built_Modules(Module_Bus(Built_Modules) ~= Fault_Node);
Remote_Count = numel(Remote_Modules);
Candidate_Count = 2^Remote_Count;
Candidate_Reports = cell(Candidate_Count,1);
Consistent_Count = 0;

for Candidate_Index = 0:Candidate_Count-1
    Remote_Limited = logical(bitget(Candidate_Index,1:Remote_Count).');
    Trial_Limited = false(M,1);
    Trial_Limited(Fault_Modules) = true;
    Trial_Limited(Remote_Modules) = Remote_Limited;
    Candidate_Label = sprintf('remote bits %s',mat2str(Remote_Limited.'));

    try
        if any(Trial_Limited)
            Fault_CONF = CONF;
            Fault_CONF.GFM_Module_X_Res(Trial_Limited) = ...
                X_Normal(Trial_Limited)+X_Virtual(Trial_Limited);
            Trial_Network = build_fixed_state_safety_network( ...
                NET, Fault_CONF, Module_State, SG_State, ...
                sprintf('%s, fault bus %d, %s', ...
                State_Label, Fault_Node, Candidate_Label));
        else
            Trial_Network = Normal_Network;
        end
        [Trial_Delta_I, Trial_Voltage] = ...
            solve_lvrt_increment_current( ...
            Trial_Network.B_Fault, Trial_Network.SourceSusceptance, ...
            Fault_Node, GFL_Nodes, CONF);
    catch Cause
        Candidate_Reports{Candidate_Index+1} = sprintf( ...
            '%s: network/LVRT error %s: %s', ...
            Candidate_Label,Cause.identifier,Cause.message);
        continue;
    end

    Trial_Unlimited = nan(M,1);
    % Under the flat unit internal-voltage assumption:
    % I_sys=|1-V|/x_res,sys; I_module=I_sys/(PN_MW/Base_MVA).
    Trial_Unlimited(Built_Modules) = ...
        abs(1-Trial_Voltage(Module_Bus(Built_Modules)))./ ...
        X_Normal(Built_Modules)./Module_PN_PU(Built_Modules);
    Should_Limit = Trial_Unlimited(Remote_Modules) > ...
        Current_Limit(Remote_Modules)+Current_Tolerance(Remote_Modules);
    Is_Consistent = isequal(Remote_Limited(:),Should_Limit(:));
    Candidate_Reports{Candidate_Index+1} = sprintf( ...
        '%s: unlimited module p.u. %s, required bits %s, consistent %d', ...
        Candidate_Label,mat2str(Trial_Unlimited(Remote_Modules).',8), ...
        mat2str(Should_Limit.'),Is_Consistent);
    if Is_Consistent
        Consistent_Count = Consistent_Count+1;
        if Consistent_Count == 1
            Fault_Network = Trial_Network;
            Delta_I = Trial_Delta_I;
            Voltage = Trial_Voltage;
            Limited_Modules = Trial_Limited;
            Unlimited_Current = Trial_Unlimited;
        end
    end
end

if Consistent_Count ~= 1
    if Consistent_Count == 0
        Identifier = 'FixedStateSCC:NoConsistentGFMLimitingState';
    else
        Identifier = 'FixedStateSCC:MultipleConsistentGFMLimitingStates';
    end
    error(Identifier, ...
        ['%s: fault bus %d has %d self-consistent GFM-ES limiting states; ', ...
        'remote module indices %s at buses %s. All candidate combinations: %s'], ...
        State_Label,Fault_Node,Consistent_Count, ...
        mat2str(Remote_Modules.'),mat2str(Module_Bus(Remote_Modules).'), ...
        strjoin(Candidate_Reports,' | '));
end

end

function [Delta_I, Voltage] = solve_lvrt_increment_current( ...
    B_Fault, Source_Susceptance, Fault_Node, GFL_Nodes, CONF)
%% Solve the three-segment GFL-WG LVRT characteristic for one fault.

N = size(B_Fault,1);
Nonfault_Nodes = [1:Fault_Node-1, Fault_Node+1:N];
Active_GFL_Nodes = GFL_Nodes(GFL_Nodes ~= Fault_Node);
GFL_Count = numel(Active_GFL_Nodes);
Segment_Count = 3^GFL_Count;
Tolerance = 1e-8;

for Segment_Index = 0:Segment_Count-1
    Segment = mod(floor(Segment_Index./(3.^(0:GFL_Count-1))),3);
    Coefficient = B_Fault(Nonfault_Nodes,Nonfault_Nodes);
    Right_Hand_Side = Source_Susceptance(Nonfault_Nodes);

    % Manuscript Eq. (18): incremental GFL-WG current enters the right
    % hand side of the equivalent positive-definite voltage equation.
    for GFL_Index = 1:GFL_Count
        GFL_Node = Active_GFL_Nodes(GFL_Index);
        Reduced_Index = find(Nonfault_Nodes == GFL_Node,1);
        if Segment(GFL_Index) == 1
            Slope = CONF.KQ_GFL_Node(GFL_Node)* ...
                CONF.I_GFL_N_pu_Node(GFL_Node);
            Coefficient(Reduced_Index,Reduced_Index) = ...
                Coefficient(Reduced_Index,Reduced_Index)+Slope;
            Right_Hand_Side(Reduced_Index) = ...
                Right_Hand_Side(Reduced_Index) + ...
                Slope*CONF.V_LVRT_On_Node(GFL_Node);
        elseif Segment(GFL_Index) == 2
            Right_Hand_Side(Reduced_Index) = ...
                Right_Hand_Side(Reduced_Index) + ...
                CONF.Delta_I_GFL_pu_Node(GFL_Node);
        end
    end

    if rcond(full(Coefficient)) < 1e-12
        continue;
    end
    Voltage = zeros(N,1);
    Voltage(Nonfault_Nodes) = Coefficient\Right_Hand_Side;
    if any(~isfinite(Voltage)) || ...
            any(Voltage(Active_GFL_Nodes) < -Tolerance)
        continue;
    end

    Delta_I_Candidate = zeros(N,1);
    Segment_Is_Valid = true;
    for GFL_Index = 1:GFL_Count
        GFL_Node = Active_GFL_Nodes(GFL_Index);
        V_p = Voltage(GFL_Node);
        V_On = CONF.V_LVRT_On_Node(GFL_Node);
        V_Sat = CONF.V_LVRT_Sat_Node(GFL_Node);
        if Segment(GFL_Index) == 0
            Segment_Is_Valid = Segment_Is_Valid && V_p >= V_On-Tolerance;
        elseif Segment(GFL_Index) == 1
            Segment_Is_Valid = Segment_Is_Valid && ...
                V_p >= V_Sat-Tolerance && V_p <= V_On+Tolerance;
            Delta_I_Candidate(GFL_Node) = CONF.KQ_GFL_Node(GFL_Node) * ...
                CONF.I_GFL_N_pu_Node(GFL_Node)*(V_On-V_p);
        else
            Segment_Is_Valid = Segment_Is_Valid && V_p <= V_Sat+Tolerance;
            Delta_I_Candidate(GFL_Node) = ...
                CONF.Delta_I_GFL_pu_Node(GFL_Node);
        end
    end

    if Segment_Is_Valid
        Delta_I = Delta_I_Candidate;
        return;
    end
end

error('FixedStateSCC:NoLVRTSolution', ...
    'No residual-voltage solution satisfies the three-segment LVRT definition.');

end

function Nodes = validate_node_list(Nodes, Node_Count, Value_Label, State_Label)
%% Validate an ordered list of original MATPOWER bus indices.

Nodes = Nodes(:);
if any(~isfinite(Nodes)) || any(Nodes ~= round(Nodes)) || ...
        any(Nodes < 1) || any(Nodes > Node_Count) || ...
        numel(unique(Nodes,'stable')) ~= numel(Nodes)
    error('FixedStateSCC:InvalidNodeList', ...
        '%s: %s is invalid.', State_Label, Value_Label);
end

end

function Binary_Value = validate_binary_result(Binary_Value, Value_Label, State_Label)
%% Validate a solved discrete state and fix it to exact zero-one values.

if any(~isfinite(Binary_Value)) || ...
        any(abs(Binary_Value-round(Binary_Value)) > 1e-5)
    error('FixedStateSCC:InvalidDiscreteState', ...
        '%s: %s is not a valid zero-one result.', State_Label, Value_Label);
end
Binary_Value = round(Binary_Value);

end
