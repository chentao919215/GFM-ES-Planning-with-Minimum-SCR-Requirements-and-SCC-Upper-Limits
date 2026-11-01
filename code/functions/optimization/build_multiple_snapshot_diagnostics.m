function Diagnostics = build_multiple_snapshot_diagnostics(sol, Objective, Objective_Scale)
%% 整理求解状态与原生诊断，补齐目标值并还原成本尺度。
% Objective为传入YALMIP的缩放后目标表达式，Objective_Scale为成本缩放系数。

%% 1. 记录YALMIP状态、耗时与缺省诊断值
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
Diagnostics.solver_status = '';

%% 2. 提取Gurobi原生结果并判断是否返回可行解
if isfield(sol, 'solveroutput') && isstruct(sol.solveroutput)
    Solver_Output = sol.solveroutput;
    if isfield(Solver_Output, 'result') && isstruct(Solver_Output.result)
        Solver_Output = Solver_Output.result;
    end
    if isfield(Solver_Output, 'status')
        Diagnostics.solver_status = char(string(Solver_Output.status));
    end
    Diagnostics.objective = read_numeric_field(Solver_Output, 'objval');
    Diagnostics.best_bound = read_numeric_field(Solver_Output, 'objbound');
    Diagnostics.mip_gap = read_numeric_field(Solver_Output, 'mipgap');
    Diagnostics.node_count = read_numeric_field(Solver_Output, 'nodecount');
    Diagnostics.iteration_count = read_numeric_field(Solver_Output, 'itercount');
    Solution_Count = read_numeric_field(Solver_Output, 'solcount');
    Diagnostics.has_incumbent = ...
        (~isnan(Solution_Count) && Solution_Count > 0) || ...
        isfinite(Diagnostics.objective) || ...
        (isfield(Solver_Output, 'x') && ~isempty(Solver_Output.x));
end

%% 3. 补齐当前可行解目标值，并将目标值与最佳界还原为年成本
if Diagnostics.has_incumbent && ~isfinite(Diagnostics.objective)
    Objective_Value = value(Objective);
    if isscalar(Objective_Value) && isfinite(Objective_Value)
        Diagnostics.objective = Objective_Value;
    end
end
Diagnostics.objective = Diagnostics.objective*Objective_Scale;
Diagnostics.best_bound = Diagnostics.best_bound*Objective_Scale;

%% 4. 原生间隙缺失时，根据已还原的目标值与最佳界补算
if Diagnostics.has_incumbent && ~isfinite(Diagnostics.mip_gap) && ...
        isfinite(Diagnostics.objective) && isfinite(Diagnostics.best_bound)
    Gap_Scale = max(abs(Diagnostics.objective), abs(Diagnostics.best_bound));
    if Gap_Scale > 0
        Diagnostics.mip_gap = abs(Diagnostics.objective - ...
            Diagnostics.best_bound)/Gap_Scale;
    else
        Diagnostics.mip_gap = 0;
    end
end
end

function Value = read_numeric_field(Input, Field_Name)
%% 读取原生结果中的数值标量，字段缺失或类型不符时返回NaN。
Value = NaN;
if isfield(Input, Field_Name) && isnumeric(Input.(Field_Name)) && ...
        isscalar(Input.(Field_Name))
    Value = double(Input.(Field_Name));
end
end
