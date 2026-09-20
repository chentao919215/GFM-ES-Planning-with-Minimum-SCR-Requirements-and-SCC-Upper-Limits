function [SCR, X_Self] = calculate_fixed_state_scr( ...
    NET, CONF, Module_State, u_GFL, SG_State, SCR_Nodes, ...
    State_Label, Fixed_State_Network)
%% Recalculate classic SCR at selected GFL-WG buses for one fixed state.
% SCR and X_Self follow SCR_Nodes. X_Self is in p.u.; SCR is dimensionless.

CONF = normalize_multiple_snapshot_conf(CONF);
if nargin < 7 || isempty(State_Label)
    State_Label = 'fixed-state SCR calculation';
end
if nargin < 8 || isempty(Fixed_State_Network)
    Fixed_State_Network = build_fixed_state_safety_network( ...
        NET, CONF, Module_State, SG_State, State_Label);
end

N = NET.N;
u_GFL = u_GFL(:);
SCR_Nodes = SCR_Nodes(:);
if numel(u_GFL) ~= N || any(~isfinite(u_GFL)) || ...
        any(abs(u_GFL-round(u_GFL)) > 1e-5)
    error('FixedStateSCR:InvalidGFLState', ...
        '%s: the GFL-WG node state is not a valid zero-one vector.', State_Label);
end
u_GFL = round(u_GFL);
if any(~isfinite(SCR_Nodes)) || any(SCR_Nodes ~= round(SCR_Nodes)) || ...
        any(SCR_Nodes < 1) || any(SCR_Nodes > N) || ...
        numel(unique(SCR_Nodes,'stable')) ~= numel(SCR_Nodes)
    error('FixedStateSCR:InvalidNodeList', ...
        '%s: the SCR GFL-WG bus list is invalid.', State_Label);
end
if any(u_GFL(SCR_Nodes) < 0.5)
    Invalid_Node = SCR_Nodes(find(u_GFL(SCR_Nodes) < 0.5,1));
    error('FixedStateSCR:InactiveGFLNode', ...
        '%s: SCR bus %d is not an active GFL-WG bus.', ...
        State_Label, Invalid_Node);
end
if ~isequal(size(Fixed_State_Network.X_Fault), [N N])
    error('FixedStateSCR:InvalidSharedNetwork', ...
        '%s: the shared fixed-state safety network has invalid dimensions.', ...
        State_Label);
end

X_Diag = diag(Fixed_State_Network.X_Fault);
X_Self = X_Diag(SCR_Nodes);
Invalid_Index = find(~isfinite(X_Self) | X_Self <= 0,1);
if ~isempty(Invalid_Index)
    error('FixedStateSCR:InvalidSelfReactance', ...
        '%s: GFL-WG bus %d has invalid self reactance %.15g p.u.', ...
        State_Label, SCR_Nodes(Invalid_Index), X_Self(Invalid_Index));
end

PN_PU = CONF.PN_GFL_pu_Node(:);
Invalid_Index = find(~isfinite(PN_PU(SCR_Nodes)) | ...
    PN_PU(SCR_Nodes) <= 0,1);
if ~isempty(Invalid_Index)
    error('FixedStateSCR:InvalidCapacityBase', ...
        '%s: GFL-WG bus %d has invalid rated-capacity base %.15g p.u.', ...
        State_Label, SCR_Nodes(Invalid_Index), ...
        PN_PU(SCR_Nodes(Invalid_Index)));
end

% Reuse the project's sole implementation of the classic SCR formula.
SCR_All = calculate_classic_scr(X_Diag, u_GFL, PN_PU);
SCR = SCR_All(SCR_Nodes);
Invalid_Index = find(~isfinite(SCR) | SCR <= 0,1);
if ~isempty(Invalid_Index)
    error('FixedStateSCR:InvalidSCR', ...
        '%s: GFL-WG bus %d gives invalid classic SCR %.15g.', ...
        State_Label, SCR_Nodes(Invalid_Index), SCR(Invalid_Index));
end

end
