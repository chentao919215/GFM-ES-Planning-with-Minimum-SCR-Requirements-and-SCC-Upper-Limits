function Z_bounds = calculate_impedance_bounds(NET, CONF)
%CALCULATE_IMPEDANCE_BOUNDS Enumerate ver_2 configuration/state combinations.
%
% The SCC state is the within-day synchronous-machine union state.  The
% actual state is a sub-state of that union and is used to construct the
% fault-transfer network.  Non-invertible combinations are retained in the
% catalog as forbidden pairs and are never admitted by the optimization
% model.

if ~isfield(NET, 'Y0_Safety') || ~isfield(CONF, 'GFM_Config_Module_Matrix')
    error('ver_2 impedance preprocessing requires the safety network and configuration catalog.');
end

NS = NET.Safety_N;
G = NET.G;
NGFL = NET.Safety_GFL_Count;
gfl_columns = NET.Safety_GFL_Reduced_Indices(:);
config_status = logical(CONF.GFM_Config_Module_Matrix);
C = size(config_status,1);

sg_states = local_build_binary_states(G);
state_count = size(sg_states,1);
Y_sg_unit = 1./(1i*CONF.Xd_Gen(:));
Y_gfm_unit = 1./(1i*CONF.GFM_Module_X_res(:));

scc_extrema = local_initialize_extrema(NS,NS);
scr_extrema = local_initialize_extrema(NS,NGFL);
tau_scaled = zeros(C,NS,NGFL);
tau_seen = false(C,NS,NGFL);
invalid_pairs = zeros(0,3); % [configuration, union-state, actual-state]
valid_pairs = zeros(0,3);
config_has_valid_pair = false(C,1);

for c = 1:C
    gfm_status = config_status(c,:).';
    Y_gfm_diag = NET.Safety_GFM_Module_Loc_Mat*(gfm_status.*Y_gfm_unit);

    % SCR uses the synchronous-machine intersection state, which can be a
    % subset that is not itself one of the realized periods.  Bound every
    % source-online, invertible configuration/state network independently.
    for scr_idx = 1:state_count
        u_scr = sg_states(scr_idx,:).';
        if ~local_source_online(u_scr,gfm_status,CONF.Require_Source_Online)
            continue;
        end
        Y_scr = NET.Y0_Safety + spdiags( ...
            NET.Safety_Gen_Loc_Mat*(u_scr.*Y_sg_unit)+Y_gfm_diag,0,NS,NS);
        [Z_scr, scr_ok] = local_inverse(Y_scr);
        if scr_ok && local_valid_transfer_impedances(Z_scr,Z_scr)
            scr_extrema = local_update_extrema( ...
                scr_extrema,CONF.KZ*Z_scr(:,gfl_columns));
        end
    end

    for union_idx = 1:state_count
        u_union = sg_states(union_idx,:).';
        if ~local_source_online(u_union,gfm_status,CONF.Require_Source_Online)
            scc_ok = false;
            Z_scc = [];
        else
            Y_scc = NET.Y0_Safety + spdiags( ...
                NET.Safety_Gen_Loc_Mat*(u_union.*Y_sg_unit)+Y_gfm_diag,0,NS,NS);
            [Z_scc,scc_ok] = local_inverse(Y_scc);
        end

        for actual_idx = 1:state_count
            u_actual = sg_states(actual_idx,:).';
            if any(u_actual > u_union)
                continue;
            end

            if ~scc_ok || ~local_source_online( ...
                    u_actual,gfm_status,CONF.Require_Source_Online)
                invalid_pairs(end+1,:) = [c,union_idx,actual_idx]; %#ok<AGROW>
                continue;
            end

            Y_fault = NET.Y0_Safety + spdiags( ...
                NET.Safety_Gen_Loc_Mat*(u_actual.*Y_sg_unit)+Y_gfm_diag,0,NS,NS);
            [Z_fault,fault_ok] = local_inverse(Y_fault);
            if ~fault_ok || ~local_valid_transfer_impedances(Z_scc,Z_fault)
                invalid_pairs(end+1,:) = [c,union_idx,actual_idx]; %#ok<AGROW>
                continue;
            end

            valid_pairs(end+1,:) = [c,union_idx,actual_idx]; %#ok<AGROW>
            config_has_valid_pair(c) = true;

            Z_scc_scaled = CONF.KZ*Z_scc;
            Z_fault_scaled = CONF.KZ*Z_fault;
            scc_extrema = local_update_extrema(scc_extrema,Z_scc_scaled);
            scr_extrema = local_update_extrema(scr_extrema, ...
                Z_fault_scaled(:,gfl_columns));

            % tau(c,n,p) is the scaled version of
            % X_SCC(nn)*Z_fault(np)/Z_fault(nn).  Imaginary scalar-network
            % values follow the model's x-dominant approximation.
            x_scc = imag(diag(Z_scc));
            x_fault = imag(diag(Z_fault));
            z_fault_imag = imag(Z_fault);
            for n = 1:NS
                for p_idx = 1:NGFL
                    p = gfl_columns(p_idx);
                    ratio = z_fault_imag(n,p)/x_fault(n);
                    candidate = CONF.KZ*x_scc(n)*max(0,abs(ratio));
                    tau_scaled(c,n,p_idx) = max(tau_scaled(c,n,p_idx),candidate);
                    tau_seen(c,n,p_idx) = true;
                end
            end
        end
    end
end

if ~any(config_has_valid_pair)
    error('No invertible ver_2 configuration/state combination was found.');
end

% A configuration with no valid state pair cannot be selected.  Every
% selectable configuration must also have a finite tau bound for every
% fault/GFL-node pair.
for c = 1:C
    if config_has_valid_pair(c) && ~all(tau_seen(c,:,:),'all')
        config_has_valid_pair(c) = false;
    end
end
if ~any(config_has_valid_pair)
    error('No GFM-ES configuration has a complete finite fault-transfer bound.');
end

Z_bounds = struct();
Z_bounds.SCC = local_finalize_extrema(scc_extrema,CONF.ZBoundMargin);
Z_bounds.SCR = local_finalize_extrema(scr_extrema,CONF.ZBoundMargin);
Z_bounds.SCC.column_reduced_indices = (1:NS).';
Z_bounds.SCR.column_reduced_indices = gfl_columns;
Z_bounds.valid_case_count = size(valid_pairs,1);
Z_bounds.typical_day_count = CONF.TypicalDayCount;
Z_bounds.shared_across_typical_days = true;
Z_bounds.Tau_GFL_Scaled = tau_scaled;
Z_bounds.ConfigurationAllowed = config_has_valid_pair;
Z_bounds.ValidStatePairs = valid_pairs;
Z_bounds.InvalidStatePairs = invalid_pairs;
Z_bounds.StateCatalog = struct( ...
    'SynchronousStates',sg_states, ...
    'StateDefinition','[union_state, actual_state], actual_state <= union_state');

end

function states = local_build_binary_states(n)
if n > 20
    error('Synchronous-machine state enumeration is limited to at most 20 units.');
end
states = logical(dec2bin(0:(2^n-1))-'0');
end

function tf = local_source_online(u_sg,u_gfm,require_source)
tf = ~require_source || any(u_sg) || any(u_gfm);
end

function [Z,is_invertible] = local_inverse(Y)
Y_full = full(Y);
if any(~isfinite(Y_full(:))) || rcond(Y_full) < 1e-10
    Z = [];
    is_invertible = false;
    return;
end
Z = Y_full\eye(size(Y_full));
is_invertible = all(isfinite(Z(:)));
end

function tf = local_valid_transfer_impedances(Z_scc,Z_fault)
if isempty(Z_scc) || isempty(Z_fault)
    tf = false;
    return;
end
x_scc = imag(diag(Z_scc));
x_fault = imag(diag(Z_fault));
tf = all(isfinite(x_scc)) && all(isfinite(x_fault)) && ...
    all(x_scc > 1e-10) && all(x_fault > 1e-10);
end

function extrema = local_initialize_extrema(n_rows,n_columns)
extrema.real_min = inf(n_rows,n_columns);
extrema.real_max = -inf(n_rows,n_columns);
extrema.imag_min = inf(n_rows,n_columns);
extrema.imag_max = -inf(n_rows,n_columns);
end

function extrema = local_update_extrema(extrema,Z_case)
extrema.real_min = min(extrema.real_min,real(Z_case));
extrema.real_max = max(extrema.real_max,real(Z_case));
extrema.imag_min = min(extrema.imag_min,imag(Z_case));
extrema.imag_max = max(extrema.imag_max,imag(Z_case));
end

function bounds = local_finalize_extrema(extrema,margin)
if any(~isfinite(extrema.real_min(:))) || any(~isfinite(extrema.real_max(:))) || ...
        any(~isfinite(extrema.imag_min(:))) || any(~isfinite(extrema.imag_max(:)))
    error('Impedance bounds contain uninitialized entries.');
end
real_pad = local_padding(extrema.real_min,extrema.real_max,margin);
imag_pad = local_padding(extrema.imag_min,extrema.imag_max,margin);
bounds.real_min = extrema.real_min-real_pad;
bounds.real_max = extrema.real_max+real_pad;
bounds.imag_min = extrema.imag_min-imag_pad;
bounds.imag_max = extrema.imag_max+imag_pad;
end

function pad = local_padding(lower_bound,upper_bound,margin)
span = upper_bound-lower_bound;
scale = max(abs(lower_bound),abs(upper_bound));
pad = margin*max(span,scale);
pad = max(pad,1e-6);
end
