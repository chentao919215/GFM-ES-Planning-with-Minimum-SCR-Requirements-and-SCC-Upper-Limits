function Diagnostics = build_single_snapshot_diagnostics(sol)
%% 本函数功能是汇总求解诊断信息。

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

end
