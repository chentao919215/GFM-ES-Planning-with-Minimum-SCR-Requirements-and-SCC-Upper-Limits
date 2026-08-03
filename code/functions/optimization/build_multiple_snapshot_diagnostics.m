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
    Solver_Result = sol.solveroutput;
    if isfield(Solver_Result, 'result') && isstruct(Solver_Result.result)
        Solver_Result = Solver_Result.result;
    end

    Diagnostics.objective = read_numeric_field(Solver_Result, 'objval', NaN);
    Diagnostics.best_bound = read_numeric_field(Solver_Result, 'objbound', NaN);
    Diagnostics.mip_gap = read_numeric_field(Solver_Result, 'mipgap', NaN);
    Diagnostics.node_count = read_numeric_field(Solver_Result, 'nodecount', NaN);
    Diagnostics.iteration_count = read_numeric_field(Solver_Result, 'itercount', NaN);
    Solution_Count = read_numeric_field(Solver_Result, 'solcount', NaN);
    Diagnostics.has_incumbent = (~isnan(Solution_Count) && Solution_Count > 0) || ...
        isfinite(Diagnostics.objective);
end

end

function value = read_numeric_field(Input_Struct, Field_Name, Default_Value)
%% 本函数功能是读取Gurobi结果中的数值字段。

if isfield(Input_Struct, Field_Name) && isnumeric(Input_Struct.(Field_Name)) && ...
        isscalar(Input_Struct.(Field_Name))
    value = double(Input_Struct.(Field_Name));
else
    value = Default_Value;
end

end
