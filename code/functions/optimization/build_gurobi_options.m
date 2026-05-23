function ops = build_gurobi_options(CONF)
%BUILD_GUROBI_OPTIONS 构造单时刻规划模型的 Gurobi 求解器参数。

switch CONF.Num_Calculation
    case 1
        ops = sdpsettings('solver', 'gurobi', ...
                          'verbose', 2, ...
                          'savesolveroutput', 1, ...
                          'gurobi.NumericFocus', 3, ...
                          'gurobi.ScaleFlag', 2);
    otherwise
        ops = sdpsettings('solver', 'gurobi', ...
                          'verbose', 2, ...
                          'savesolveroutput', 1);
end

ops.gurobi.BarHomogeneous  = 1;
ops.gurobi.Method          = 1;
ops.gurobi.NodeMethod      = 1;
ops.gurobi.Threads         = 14;
ops.gurobi.MIPGap          = 1e-2;
ops.gurobi.DualReductions  = 0;
ops.gurobi.OutputFlag      = 1;
ops.gurobi.LogToConsole    = 1;
ops.gurobi.DisplayInterval = 1;
ops.gurobi.LogFile         = fullfile(pwd,'gurobi_run.log');

end
