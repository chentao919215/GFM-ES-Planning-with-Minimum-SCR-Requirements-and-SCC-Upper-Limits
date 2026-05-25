function ops = build_gurobi_options()
%% 本函数功能是生成单时刻规划模型的YALMIP-Gurobi求解器参数。

% 读取长时间后台运行时传入的可选求解器设置
mcp_options = get_mcp_longrun_options();

% quiet模式用于后台运行，避免求解器输出占用交互响应窗口
quiet_mode = isfield(mcp_options, 'quiet') && isequal(mcp_options.quiet, true);
if quiet_mode
    yalmip_verbose = 0;
else
    yalmip_verbose = 2;
end

% YALMIP基础设置和Gurobi数值稳定性设置
ops = sdpsettings('solver', 'gurobi', ...
                  'verbose', yalmip_verbose, ...
                  'savesolveroutput', 1, ...
                  'gurobi.NumericFocus', 3, ...
                  'gurobi.ScaleFlag', 2);
ops.gurobi.BarHomogeneous = 1;
ops.gurobi.Method = 1;
ops.gurobi.NodeMethod = 1;
ops.gurobi.DualReductions = 0;

% 默认并行线程数、MIP间隙和日志刷新间隔
ops.gurobi.Threads         = 14;
ops.gurobi.MIPGap          = 1e-2;
ops.gurobi.DisplayInterval = 1;

% 允许后台运行入口覆盖默认线程数
if isfield(mcp_options, 'threads') && ~isempty(mcp_options.threads)
    ops.gurobi.Threads = mcp_options.threads;
end

% 允许后台运行入口覆盖默认MIP间隙
if isfield(mcp_options, 'mip_gap') && ~isempty(mcp_options.mip_gap)
    ops.gurobi.MIPGap = mcp_options.mip_gap;
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

end

function options = get_mcp_longrun_options()
% 该函数读取后台长时间运行入口传入的可选参数。

options = struct();
if isappdata(0, 'single_snapshot_mcp_gurobi_options')
    options = getappdata(0, 'single_snapshot_mcp_gurobi_options');
end

end
