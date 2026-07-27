function C_forbid = add_forbidden_state_pair_constraints( ...
    invalid_pairs, state_table, lambda_config, u_sg_scc, u_sg)
%ADD_FORBIDDEN_STATE_PAIR_CONSTRAINTS
% Forbid lambda_c=1 together with a non-invertible (union,actual) pair.

C_forbid = [];
if isempty(invalid_pairs)
    return;
end

[G,D] = size(u_sg_scc);
G2 = size(u_sg,1);
D2 = size(u_sg,2);
T = size(u_sg,3);
if G2 ~= G || D2 ~= D
    error('Synchronous-machine state variable dimensions are inconsistent.');
end
if size(state_table,2) ~= G
    error('State catalog dimension is inconsistent with the UC variables.');
end

for r = 1:size(invalid_pairs,1)
    c = invalid_pairs(r,1);
    union_state = state_table(invalid_pairs(r,2),:).';
    actual_state = state_table(invalid_pairs(r,3),:).';
    if c < 1 || c > numel(lambda_config)
        error('Invalid configuration index in the forbidden state catalog.');
    end

    % Expand the catalog state explicitly across typical days.  YALMIP
    % does not rely on MATLAB's implicit singleton-dimension expansion.
    union_state_by_day = repmat(union_state,1,D);
    union_mismatch = sum((1-union_state_by_day).*u_sg_scc + ...
        union_state_by_day.*(1-u_sg_scc),1);
    for d = 1:D
        for t = 1:T
            actual_status = u_sg(:,d,t);
            actual_mismatch = sum((1-actual_state).*actual_status + ...
                actual_state.*(1-actual_status));
            % lambda_c=1 requires at least one mismatch, so the exact
            % forbidden pair cannot occur in any typical-day period.
            C_forbid = [C_forbid, lambda_config(c) <= ...
                union_mismatch(d) + actual_mismatch]; %#ok<AGROW>
        end
    end
end
end
