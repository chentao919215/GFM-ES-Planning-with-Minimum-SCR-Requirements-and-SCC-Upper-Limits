function ops = build_gurobi_options(Solver_Configuration)
%% 本函数功能是生成规划模型的YALMIP-Gurobi求解器参数。

% 读取长时间后台运行时传入的可选求解器设置
MCP_Options = get_mcp_longrun_options();

% quiet模式用于后台运行，避免求解器输出占用交互响应窗口
Quiet_Mode = isfield(MCP_Options, 'quiet') && isequal(MCP_Options.quiet, true);
if Quiet_Mode
    YALMIP_Verbose = 0;
else
    YALMIP_Verbose = 2;
end

% YALMIP基础设置。算法类参数保留Gurobi自动选择，避免固定双单纯形
% 在退化的阻抗重构松弛上产生大量迭代。
ops = sdpsettings('solver', 'gurobi', ...
                  'verbose', YALMIP_Verbose, ...
                  'savesolveroutput', 1);

% 开发阶段默认在有限时间内优先获得高质量可行方案。
ops.gurobi.Threads          = Solver_Configuration.Threads;
ops.gurobi.MIPGap           = Solver_Configuration.MIPGap;
ops.gurobi.TimeLimit        = Solver_Configuration.TimeLimit;
ops.gurobi.MIPFocus         = Solver_Configuration.MIPFocus;
ops.gurobi.Heuristics       = Solver_Configuration.Heuristics;
ops.gurobi.NoRelHeurWork    = Solver_Configuration.NoRelHeurWork;
ops.gurobi.DisplayInterval = 1;

% 两阶段最优性证明可选用并发MIP；未显式配置时保持Gurobi默认的单路搜索。
if isfield(Solver_Configuration, 'ConcurrentMIP') && ~isempty(Solver_Configuration.ConcurrentMIP)
    ops.gurobi.ConcurrentMIP = Solver_Configuration.ConcurrentMIP;
end

% 允许后台运行入口覆盖默认线程数
if isfield(MCP_Options, 'threads') && ~isempty(MCP_Options.threads)
    ops.gurobi.Threads = MCP_Options.threads;
end

% 允许后台运行入口覆盖默认MIP间隙
if isfield(MCP_Options, 'mip_gap') && ~isempty(MCP_Options.mip_gap)
    ops.gurobi.MIPGap = MCP_Options.mip_gap;
end

if isfield(MCP_Options, 'time_limit') && ~isempty(MCP_Options.time_limit)
    ops.gurobi.TimeLimit = MCP_Options.time_limit;
end

if isfield(MCP_Options, 'mip_focus') && ~isempty(MCP_Options.mip_focus)
    ops.gurobi.MIPFocus = MCP_Options.mip_focus;
end

if Quiet_Mode
    % quiet模式关闭求解器控制台输出
    ops.gurobi.OutputFlag   = 0;
    ops.gurobi.LogToConsole = 0;
else
    % 交互运行时保留求解器输出，并在当前工作目录写出日志
    ops.gurobi.OutputFlag      = 1;
    ops.gurobi.LogToConsole    = 1;
    Project_Root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
    Results_Directory = fullfile(Project_Root, 'results');
    if ~isfolder(Results_Directory)
        mkdir(Results_Directory);
    end
    ops.gurobi.LogFile         = fullfile(Results_Directory, 'gurobi_run.log');
end

end

function options = get_mcp_longrun_options()
% 该函数读取后台长时间运行入口传入的可选参数。

options = struct();
if isappdata(0, 'multiple_snapshot_mcp_gurobi_options')
    options = getappdata(0, 'multiple_snapshot_mcp_gurobi_options');
end

end
