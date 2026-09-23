function ops = build_copt_options(Solver_Configuration)
%% 生成规划模型的YALMIP-COPT求解器参数。

% 读取长时间后台运行时传入的可选求解器设置。
MCP_Options = get_mcp_longrun_options();

% quiet模式用于后台运行，避免求解器输出占用交互响应窗口。
Quiet_Mode = isfield(MCP_Options, 'quiet') && isequal(MCP_Options.quiet, true);
if Quiet_Mode
    YALMIP_Verbose = 0;
else
    YALMIP_Verbose = 2;
end

% 保留YALMIP框架、求解器输出保存与原verbosity策略。
ops = sdpsettings('solver', 'copt', ...
                  'verbose', YALMIP_Verbose, ...
                  'savesolveroutput', 1);

% 通用MILP参数迁移到COPT名称。
ops.copt.Threads   = Solver_Configuration.Threads;
ops.copt.RelGap    = Solver_Configuration.MIPGap;
ops.copt.TimeLimit = Solver_Configuration.TimeLimit;

% 保留COPT日志开关；当前YALMIP适配器在verbose非零时将文件日志写为copt.log。
ops.copt.Logging = double(~Quiet_Mode);
ops.copt.LogToConsole = double(~Quiet_Mode);

% Gurobi专属MIPFocus、Heuristics、NoRelHeurWork、DisplayInterval及
% ConcurrentMIP在COPT中没有等价控制，故不映射以避免改变算法策略。

% 允许后台运行入口覆盖通用求解参数。
if isfield(MCP_Options, 'threads') && ~isempty(MCP_Options.threads)
    ops.copt.Threads = MCP_Options.threads;
end

if isfield(MCP_Options, 'mip_gap') && ~isempty(MCP_Options.mip_gap)
    ops.copt.RelGap = MCP_Options.mip_gap;
end

if isfield(MCP_Options, 'time_limit') && ~isempty(MCP_Options.time_limit)
    ops.copt.TimeLimit = MCP_Options.time_limit;
end

% MCP_Options.mip_focus仍可由原入口传入，但COPT无等价MIP focus参数，忽略该值。

end

function options = get_mcp_longrun_options()
% 该函数读取后台长时间运行入口传入的可选参数。

options = struct();
if isappdata(0, 'multiple_snapshot_mcp_gurobi_options')
    options = getappdata(0, 'multiple_snapshot_mcp_gurobi_options');
end

end
