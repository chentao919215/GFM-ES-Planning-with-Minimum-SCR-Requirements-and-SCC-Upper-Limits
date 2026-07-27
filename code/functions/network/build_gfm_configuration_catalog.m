function CATALOG = build_gfm_configuration_catalog(GFMModules)
%BUILD_GFM_CONFIGURATION_CATALOG Enumerate feasible module configurations.
% The catalog is an offline parameter set.  The optimization model selects
% exactly one row through lambda_c and maps that row back to module status.

M = GFMModules.Count;
N = numel(GFMModules.CandidateBus);
E = max(GFMModules.Order);

if M > 20
    error('GFM configuration enumeration is limited to at most 20 modules.');
end
if any(GFMModules.CandidateIndex < 1 | GFMModules.CandidateIndex > N) || ...
        any(GFMModules.Order < 1 | GFMModules.Order > E)
    error('GFM module candidate/order indices are invalid.');
end

% Enumerate all module status rows, then retain the module-count and
% sequential-build feasible rows.  The zero-module configuration is valid.
all_status = logical(dec2bin(0:(2^M-1)) - '0');
keep = sum(all_status,2) <= floor(GFMModules.N_Module_Max);
all_status = all_status(keep,:);

if GFMModules.EnforceSequentialBuild
    keep = false(size(all_status,1),1);
    for r = 1:size(all_status,1)
        keep(r) = local_is_sequential(all_status(r,:), ...
            GFMModules.CandidateIndex(:), GFMModules.Order(:), N);
    end
    all_status = all_status(keep,:);
end

if isempty(all_status)
    error('No feasible GFM-ES configuration was enumerated.');
end

candidate_module_mat = sparse(GFMModules.CandidateIndex(:), ...
    (1:M).', 1, N, M);
candidate_status = double(all_status)*full(candidate_module_mat.');

% a(c,n,e) is the document-level configuration mapping parameter.
a_cne = zeros(size(all_status,1),N,E);
for m = 1:M
    a_cne(:,GFMModules.CandidateIndex(m),GFMModules.Order(m)) = ...
        double(all_status(:,m));
end

CATALOG = struct();
CATALOG.Count = size(all_status,1);
CATALOG.ModuleStatus = double(all_status);
CATALOG.CandidateStatus = candidate_status;
CATALOG.A_cne = a_cne;
CATALOG.ModuleCount = sum(all_status,2);

end

function is_valid = local_is_sequential(status, candidate_index, order, candidate_count)
is_valid = true;
for n = 1:candidate_count
    idx = find(candidate_index == n);
    [~,sort_idx] = sort(order(idx));
    ordered_status = status(idx(sort_idx));
    if any(ordered_status(2:end) > ordered_status(1:end-1))
        is_valid = false;
        return;
    end
end
end
