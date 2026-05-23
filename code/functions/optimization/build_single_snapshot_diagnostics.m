function Diagnostics = build_single_snapshot_diagnostics(sol, num_gfm_candidates, num_constraints, M_Z, Z_bounds)
%BUILD_SINGLE_SNAPSHOT_DIAGNOSTICS 汇总求解诊断信息。

Diagnostics = struct();
Diagnostics.problem = sol.problem;
Diagnostics.info = sol.info;

if isfield(sol, 'yalmiptime')
    Diagnostics.yalmiptime = sol.yalmiptime;
else
    Diagnostics.yalmiptime = NaN;
end

if isfield(sol, 'solvertime')
    Diagnostics.solvertime = sol.solvertime;
else
    Diagnostics.solvertime = NaN;
end

Diagnostics.num_gfm_candidates = num_gfm_candidates;
Diagnostics.num_constraints = num_constraints;

if nargin >= 4
    Diagnostics.impedance_big_m = M_Z;
end

if nargin >= 5
    Diagnostics.z_bound_margin = Z_bounds.margin;
    Diagnostics.z_bound_rcond_min_support = Z_bounds.rcond_min_support;
    Diagnostics.z_bound_rcond_max_support = Z_bounds.rcond_max_support;
end

end
