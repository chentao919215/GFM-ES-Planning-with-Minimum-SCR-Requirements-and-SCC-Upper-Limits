function Diagnostics = build_multiple_snapshot_diagnostics(sol)
%% 本函数功能是汇总多时刻模型的求解诊断信息。

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

Diagnostics.has_incumbent = false;
Diagnostics.objective = NaN;
Diagnostics.best_bound = NaN;
Diagnostics.mip_gap = NaN;
Diagnostics.node_count = NaN;
Diagnostics.iteration_count = NaN;

if isfield(sol, 'solveroutput') && isstruct(sol.solveroutput)
    solver_result = sol.solveroutput;
    if isfield(solver_result, 'result') && isstruct(solver_result.result)
        solver_result = solver_result.result;
    end

    Diagnostics.objective = read_numeric_field(solver_result, 'objval', NaN);
    Diagnostics.best_bound = read_numeric_field(solver_result, 'objbound', NaN);
    Diagnostics.mip_gap = read_numeric_field(solver_result, 'mipgap', NaN);
    Diagnostics.node_count = read_numeric_field(solver_result, 'nodecount', NaN);
    Diagnostics.iteration_count = read_numeric_field(solver_result, 'itercount', NaN);
    solution_count = read_numeric_field(solver_result, 'solcount', NaN);
    Diagnostics.has_incumbent = (~isnan(solution_count) && solution_count > 0) || ...
        isfinite(Diagnostics.objective);
end

end

function value = read_numeric_field(input_struct, field_name, default_value)
%% 本函数功能是读取Gurobi结果中的数值字段。

if isfield(input_struct, field_name) && isnumeric(input_struct.(field_name)) && ...
        isscalar(input_struct.(field_name))
    value = double(input_struct.(field_name));
else
    value = default_value;
end

end
