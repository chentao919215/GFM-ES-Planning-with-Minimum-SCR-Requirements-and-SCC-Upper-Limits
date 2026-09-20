function State = build_fixed_state_safety_network( ...
    NET, CONF, Module_State, SG_State, State_Label)
%% Rebuild the lossless safety network for one fixed equipment state.

CONF = normalize_multiple_snapshot_conf(CONF);
if nargin < 5 || isempty(State_Label)
    State_Label = 'fixed-state safety calculation';
end

N = NET.N;
G = NET.G;
M = CONF.GFM_Module_Count;
if numel(Module_State) ~= M || numel(SG_State) ~= G
    error('FixedStateSecurity:StateDimensionMismatch', ...
        '%s: equipment-state dimensions do not match the network.', State_Label);
end
if ~isequal(size(NET.B_0_Safety_Full), [N N])
    error('FixedStateSecurity:NetworkDimensionMismatch', ...
        '%s: the full safety-network matrix must be %d-by-%d.', ...
        State_Label, N, N);
end
if any(~isfinite(CONF.Xd_Gen(:))) || any(CONF.Xd_Gen(:) <= 0) || ...
        any(~isfinite(CONF.GFM_Module_X_Res(:))) || ...
        any(CONF.GFM_Module_X_Res(:) <= 0)
    error('FixedStateSecurity:InvalidSourceReactance', ...
        '%s: SG or GFM-ES source reactance is invalid.', State_Label);
end

Module_State = validate_binary_state(Module_State(:), ...
    'GFM-ES module build state', State_Label);
SG_State = validate_binary_state(SG_State(:), ...
    'SG commitment state', State_Label);

SG_Source_Susceptance = NET.Generator_Location_Matrix * ...
    (SG_State.*(-imag(1./(1i*CONF.Xd_Gen(:)))));
GFM_Source_Susceptance = CONF.GFM_Module_Loc_Mat * ...
    (Module_State.*(1./CONF.GFM_Module_X_Res(:)));
Source_Susceptance = SG_Source_Susceptance+GFM_Source_Susceptance;

% Manuscript Section II-B, Eqs. (3)-(6): B=Im(Y), X=-B^{-1}.
% The safety network is lossless: line resistance and shunt susceptance
% from the normal operating network are deliberately excluded.
B_Manuscript = NET.B_0_Safety_Full - ...
    spdiags(Source_Susceptance,0,N,N);
Reciprocal_Condition = rcond(full(B_Manuscript));
if ~isfinite(Reciprocal_Condition) || Reciprocal_Condition < 1e-12
    error('FixedStateSecurity:SingularNetwork', ...
        '%s: the safety-network susceptance matrix is singular or ill-conditioned (rcond %.3e).', ...
        State_Label, Reciprocal_Condition);
end

X_Fault = -(full(B_Manuscript)\eye(N));
if any(~isfinite(X_Fault(:))) || any(X_Fault(:) < -1e-10)
    error('FixedStateSecurity:InvalidReactanceMatrix', ...
        '%s: the reconstructed safety reactance matrix is non-finite or violates non-negativity.', ...
        State_Label);
end

State = struct();
State.B_Manuscript = B_Manuscript;
State.B_Fault = -B_Manuscript;
State.X_Fault = X_Fault;
State.SourceSusceptance = Source_Susceptance;
State.ReciprocalCondition = Reciprocal_Condition;

end

function Binary_State = validate_binary_state(Binary_State, Value_Label, State_Label)
%% Validate and fix a solved discrete state to exact zero-one values.

if any(~isfinite(Binary_State)) || ...
        any(abs(Binary_State-round(Binary_State)) > 1e-5)
    error('FixedStateSecurity:InvalidDiscreteState', ...
        '%s: %s is not a valid zero-one result.', State_Label, Value_Label);
end
Binary_State = round(Binary_State);

end
