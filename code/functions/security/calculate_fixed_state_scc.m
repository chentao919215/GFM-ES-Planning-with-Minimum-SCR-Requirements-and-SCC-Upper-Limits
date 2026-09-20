function SCC_kA = calculate_fixed_state_scc( ...
    NET, CONF, Module_State, u_GFL, SG_State, Fault_Nodes, ...
    State_Label, Fixed_State_Network)
%% Recalculate SCC at selected fault nodes for one fixed equipment state.
% The returned vector follows Fault_Nodes and is expressed in kA.

CONF = normalize_multiple_snapshot_conf(CONF);
if nargin < 7 || isempty(State_Label)
    State_Label = 'fixed-state SCC calculation';
end
if nargin < 8 || isempty(Fixed_State_Network)
    Fixed_State_Network = build_fixed_state_safety_network( ...
        NET, CONF, Module_State, SG_State, State_Label);
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

% The base network contains the local GFM-ES residual reactance. At a
% faulted GFM-ES bus, DeltaY switches only that local contribution to the
% virtual-impedance-limited fault characteristic used by the online model.
GFM_Delta_Node = CONF.GFM_Module_Loc_Mat * ...
    (CONF.GFM_Module_DeltaY_abs(:).*Module_State);
GFL_Fault_Increment_Node = CONF.Delta_I_GFL_pu_Node(:).*u_GFL;
GFL_Nodes = find(u_GFL > 0.5);
SCC_kA = zeros(numel(Fault_Nodes),1);

for Fault_Index = 1:numel(Fault_Nodes)
    Fault_Node = Fault_Nodes(Fault_Index);
    X_Self = X_Fault(Fault_Node,Fault_Node);
    if ~isfinite(X_Self) || X_Self <= 0
        error('FixedStateSCC:InvalidSelfReactance', ...
            '%s: bus %d has invalid self reactance %.15g p.u.', ...
            State_Label, Fault_Node, X_Self);
    end

    try
        Delta_I_LVRT = solve_lvrt_increment_current( ...
            B_Fault, Source_Susceptance, Fault_Node, GFL_Nodes, CONF);
    catch Cause
        Context = MException('FixedStateSCC:LVRTFailure', ...
            '%s: LVRT incremental-current solution failed for fault bus %d.', ...
            State_Label, Fault_Node);
        throwAsCaller(addCause(Context,Cause));
    end

    Nonfault_GFL_Nodes = GFL_Nodes(GFL_Nodes ~= Fault_Node);
    Transfer_Current = 0;
    for GFL_Node = reshape(Nonfault_GFL_Nodes,1,[])
        Transfer_Current = Transfer_Current + ...
            X_Fault(Fault_Node,GFL_Node)/X_Self*Delta_I_LVRT(GFL_Node);
    end

    SCC_PU = 1/X_Self-GFM_Delta_Node(Fault_Node) + ...
        GFL_Fault_Increment_Node(Fault_Node)+Transfer_Current;
    if ~isfinite(SCC_PU) || SCC_PU < 0
        error('FixedStateSCC:InvalidSCC', ...
            '%s: fault bus %d gives invalid SCC %.15g p.u.', ...
            State_Label, Fault_Node, SCC_PU);
    end
    SCC_kA(Fault_Index) = SCC_PU*CONF.Base_kA;
end

end

function Delta_I = solve_lvrt_increment_current( ...
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
