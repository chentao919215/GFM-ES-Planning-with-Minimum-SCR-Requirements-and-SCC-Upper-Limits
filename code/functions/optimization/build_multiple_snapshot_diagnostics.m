function Diagnostics = build_multiple_snapshot_diagnostics(sol)
%% 汇总多时刻模型的求解诊断信息。

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
    % 若求解器未返回MIP gap，则根据 incumbent 与 best bound 计算。
    if ~isfinite(Diagnostics.mip_gap) && ...
            isfinite(Diagnostics.objective) && ...
            isfinite(Diagnostics.best_bound)
        Gap_Scale = max(abs(Diagnostics.objective), ...
            abs(Diagnostics.best_bound));
        if Gap_Scale > 0
            Diagnostics.mip_gap = abs(Diagnostics.objective - ...
                Diagnostics.best_bound)/Gap_Scale;
        elseif Diagnostics.objective == Diagnostics.best_bound
            Diagnostics.mip_gap = 0;
        else
            Diagnostics.mip_gap = Inf;
        end
    end
    Diagnostics.node_count = read_numeric_field(Solver_Result, 'nodecount', NaN);
    Diagnostics.iteration_count = read_numeric_field(Solver_Result, 'itercount', NaN);
    Solution_Count = read_numeric_field(Solver_Result, 'solcount', NaN);
    Diagnostics.has_incumbent = ...
        (~isnan(Solution_Count) && Solution_Count > 0) || ...
        isfinite(Diagnostics.objective) || ...
        (isfield(Solver_Result,'x') && ~isempty(Solver_Result.x));
end
end

function value = read_numeric_field(Input_Struct, Field_Name, Default_Value)
%% 读取Gurobi求解结果中的数值字段。

value = Default_Value;
if isfield(Input_Struct, Field_Name) && ...
        isnumeric(Input_Struct.(Field_Name)) && ...
        isscalar(Input_Struct.(Field_Name))
    value = double(Input_Struct.(Field_Name));
end

end
