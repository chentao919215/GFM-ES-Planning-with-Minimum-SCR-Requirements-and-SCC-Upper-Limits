function ops = build_gurobi_options(solver_config)
%% 本函数功能是生成规划模型的YALMIP-Gurobi求解器参数。

if nargin < 1 || isempty(solver_config)
    solver_config = struct();
end

% 读取长时间后台运行时传入的可选求解器设置
mcp_options = get_mcp_longrun_options();

% quiet模式用于后台运行，避免求解器输出占用交互响应窗口
quiet_mode = isfield(mcp_options, 'quiet') && isequal(mcp_options.quiet, true);
if quiet_mode
    yalmip_verbose = 0;
else
    yalmip_verbose = 2;
end

% YALMIP基础设置。算法类参数保留Gurobi自动选择，避免固定双单纯形
% 在退化的阻抗重构松弛上产生大量迭代。
ops = sdpsettings('solver', 'gurobi', ...
                  'verbose', yalmip_verbose, ...
                  'savesolveroutput', 1);

% 开发阶段默认在有限时间内优先获得高质量可行方案。
ops.gurobi.Threads          = get_option(solver_config, 'Threads', 14);
ops.gurobi.MIPGap           = get_option(solver_config, 'MIPGap', 0.005);
ops.gurobi.TimeLimit        = get_option(solver_config, 'TimeLimit', 600);
ops.gurobi.MIPFocus         = get_option(solver_config, 'MIPFocus', 1);
ops.gurobi.Heuristics       = get_option(solver_config, 'Heuristics', 0.2);
ops.gurobi.NoRelHeurWork    = get_option(solver_config, 'NoRelHeurWork', 0);
ops.gurobi.DisplayInterval = 1;

% 两阶段最优性证明可选用并发MIP；未显式配置时保持Gurobi默认的单路搜索。
if isfield(solver_config, 'ConcurrentMIP') && ~isempty(solver_config.ConcurrentMIP)
    ops.gurobi.ConcurrentMIP = solver_config.ConcurrentMIP;
end

% 允许后台运行入口覆盖默认线程数
if isfield(mcp_options, 'threads') && ~isempty(mcp_options.threads)
    ops.gurobi.Threads = mcp_options.threads;
end

% 允许后台运行入口覆盖默认MIP间隙
if isfield(mcp_options, 'mip_gap') && ~isempty(mcp_options.mip_gap)
    ops.gurobi.MIPGap = mcp_options.mip_gap;
end

if isfield(mcp_options, 'time_limit') && ~isempty(mcp_options.time_limit)
    ops.gurobi.TimeLimit = mcp_options.time_limit;
end

if isfield(mcp_options, 'mip_focus') && ~isempty(mcp_options.mip_focus)
    ops.gurobi.MIPFocus = mcp_options.mip_focus;
end

if quiet_mode
    % quiet模式关闭求解器控制台输出
    ops.gurobi.OutputFlag   = 0;
    ops.gurobi.LogToConsole = 0;
else
    % 交互运行时保留求解器输出，并在当前工作目录写出日志
    ops.gurobi.OutputFlag      = 1;
    ops.gurobi.LogToConsole    = 1;
    ops.gurobi.LogFile         = fullfile(pwd, 'gurobi_run.log');
end

function value = get_option(options, field_name, default_value)
%% 本函数功能是读取可选求解器参数。

if isfield(options, field_name) && ~isempty(options.(field_name))
    value = options.(field_name);
else
    value = default_value;
end

end

end

function options = get_mcp_longrun_options()
% 该函数读取后台长时间运行入口传入的可选参数。

options = struct();
if isappdata(0, 'multiple_snapshot_mcp_gurobi_options')
    options = getappdata(0, 'multiple_snapshot_mcp_gurobi_options');
elseif isappdata(0, 'single_snapshot_mcp_gurobi_options')
    options = getappdata(0, 'single_snapshot_mcp_gurobi_options');
end

end
