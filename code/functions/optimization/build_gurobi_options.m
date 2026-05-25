function ops = build_gurobi_options()
%BUILD_GUROBI_OPTIONS Build Gurobi settings for single-snapshot planning.

mcp_options = get_mcp_longrun_options();
quiet_mode = isfield(mcp_options, 'quiet') && isequal(mcp_options.quiet, true);
if quiet_mode
    yalmip_verbose = 0;
else
    yalmip_verbose = 2;
end

ops = sdpsettings('solver', 'gurobi', ...
                  'verbose', yalmip_verbose, ...
                  'savesolveroutput', 1, ...
                  'gurobi.NumericFocus', 3, ...
                  'gurobi.ScaleFlag', 2);
ops.gurobi.BarHomogeneous = 1;
ops.gurobi.Method = 1;
ops.gurobi.NodeMethod = 1;
ops.gurobi.DualReductions = 0;

ops.gurobi.Threads         = 14;
ops.gurobi.MIPGap          = 1e-2;
ops.gurobi.DisplayInterval = 1;

if isfield(mcp_options, 'threads') && ~isempty(mcp_options.threads)
    ops.gurobi.Threads = mcp_options.threads;
end

if isfield(mcp_options, 'mip_gap') && ~isempty(mcp_options.mip_gap)
    ops.gurobi.MIPGap = mcp_options.mip_gap;
end

if quiet_mode
    % MCP calls have a strict response window. In quiet mode, suppress all
    % solver console output so a background timer can finish long solves.
    ops.gurobi.OutputFlag   = 0;
    ops.gurobi.LogToConsole = 0;
else
    ops.gurobi.OutputFlag      = 1;
    ops.gurobi.LogToConsole    = 1;
    ops.gurobi.LogFile         = fullfile(pwd, 'gurobi_run.log');
end

end

function options = get_mcp_longrun_options()
%GET_MCP_LONGRUN_OPTIONS Read opt-in runtime overrides for MCP long runs.

options = struct();
if isappdata(0, 'single_snapshot_mcp_gurobi_options')
    options = getappdata(0, 'single_snapshot_mcp_gurobi_options');
end

end
