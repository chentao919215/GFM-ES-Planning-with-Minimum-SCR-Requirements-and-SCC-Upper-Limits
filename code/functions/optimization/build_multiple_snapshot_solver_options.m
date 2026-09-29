function ops = build_multiple_snapshot_solver_options(Solver_Configuration, Has_MIP_Start)
%% Build YALMIP settings from the selected backend's native configuration.

if nargin < 2
    Has_MIP_Start = false;
end
if ~isstruct(Solver_Configuration) || ~isfield(Solver_Configuration, 'name') || ...
        ~isfield(Solver_Configuration, 'options')
    error('MultipleSnapshot:InvalidSolverConfiguration', ...
        'solver must contain name and options fields.');
end

Solver_Name = lower(char(Solver_Configuration.name));
if ~any(strcmp(Solver_Name, {'gurobi','copt'}))
    error('MultipleSnapshot:InvalidSolverName', ...
        'Unsupported solver: %s.', Solver_Name);
end
Options = Solver_Configuration.options;
if ~isfield(Options, Solver_Name) || ~isstruct(Options.(Solver_Name))
    error('MultipleSnapshot:MissingSolverOptions', ...
        'No native options configured for solver %s.', Solver_Name);
end

ops = sdpsettings('solver', Solver_Name);
if isfield(Options, 'yalmip')
    ops = apply_yalmip_options(ops, Options.yalmip);
end
ops = apply_native_options(ops, Solver_Name, Options.(Solver_Name));

if Has_MIP_Start && isfield(Options, 'mip_start')
    MIP_Start_Options = Options.mip_start;
    if isfield(MIP_Start_Options, 'yalmip')
        ops = apply_yalmip_options(ops, MIP_Start_Options.yalmip);
    end
    if isfield(MIP_Start_Options, Solver_Name)
        ops = apply_native_options(ops, Solver_Name, ...
            MIP_Start_Options.(Solver_Name));
    end
end

MCP_Options = get_mcp_longrun_options();
Quiet_Mode = isfield(MCP_Options, 'quiet') && ...
    isequal(MCP_Options.quiet, true);
if Quiet_Mode && isfield(Options, 'quiet')
    Quiet_Options = Options.quiet;
    if isfield(Quiet_Options, 'yalmip')
        ops = apply_yalmip_options(ops, Quiet_Options.yalmip);
    end
    if isfield(Quiet_Options, Solver_Name)
        ops = apply_native_options(ops, Solver_Name, ...
            Quiet_Options.(Solver_Name));
    end
end

% Resolve a configured relative log path against the project root and create its directory.
if isfield(Options.(Solver_Name), 'LogFile') && ...
        ~isempty(Options.(Solver_Name).LogFile) && ~Quiet_Mode
    Log_File = char(Options.(Solver_Name).LogFile);
    if ~is_absolute_log_path(Log_File)
        Project_Root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
        Log_File = fullfile(Project_Root, Log_File);
    end
    Log_Directory = fileparts(Log_File);
    if ~isempty(Log_Directory) && ~isfolder(Log_Directory)
        mkdir(Log_Directory);
    end
    ops.(Solver_Name).LogFile = Log_File;
end

end

function ops = apply_yalmip_options(ops, Option_Values)
Option_Names = fieldnames(Option_Values);
for k = 1:numel(Option_Names)
    Field_Name = Option_Names{k};
    ops.(Field_Name) = Option_Values.(Field_Name);
end
end

function ops = apply_native_options(ops, Solver_Name, Option_Values)
Option_Names = fieldnames(Option_Values);
for k = 1:numel(Option_Names)
    Field_Name = Option_Names{k};
    ops.(Solver_Name).(Field_Name) = Option_Values.(Field_Name);
end
end

function Is_Absolute = is_absolute_log_path(Path)
Is_Absolute = startsWith(Path, filesep) || ...
    (ispc && numel(Path) >= 2 && Path(2) == ':');
end

function options = get_mcp_longrun_options()
options = struct();
if isappdata(0, 'multiple_snapshot_mcp_gurobi_options')
    options = getappdata(0, 'multiple_snapshot_mcp_gurobi_options');
end
end