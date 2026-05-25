function RunInfo = start_single_snapshot_planning_longrun(project_root)
%START_SINGLE_SNAPSHOT_PLANNING_LONGRUN Start the planning script in the background.
%
% The MATLAB MCP bridge has a short synchronous response window. This helper
% starts the original script from a timer callback, suppresses solver console
% output, and writes progress to a status file that can be polled externally.

if nargin < 1 || isempty(project_root)
    project_root = resolve_project_root();
end

project_root = canonical_path(project_root);
functions_dir = fullfile(project_root, 'code', 'functions');
scripts_dir = fullfile(project_root, 'code', 'scripts');
results_dir = fullfile(project_root, 'results');
script_file = fullfile(scripts_dir, 'run_single_snapshot_planning.m');

if ~isfolder(functions_dir)
    error('Missing functions directory: %s', functions_dir);
end
if ~isfile(script_file)
    error('Missing planning script: %s', script_file);
end

addpath(genpath(functions_dir));
ensure_directory(results_dir);

stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
status_file = fullfile(results_dir, ['mcp_single_snapshot_longrun_', stamp, '_status.txt']);
output_file = fullfile(results_dir, ['mcp_single_snapshot_longrun_', stamp, '_captured_output.txt']);
timer_key = ['single_snapshot_longrun_timer_', stamp];

RunInfo = struct();
RunInfo.project_root = project_root;
RunInfo.script_file = script_file;
RunInfo.status_file = status_file;
RunInfo.output_file = output_file;
RunInfo.timer_key = timer_key;

write_status(status_file, 'SCHEDULED', 'Timer has been created.', ...
    'script_file', script_file, ...
    'output_file', output_file);

t = timer( ...
    'ExecutionMode', 'singleShot', ...
    'StartDelay', 1, ...
    'Name', timer_key, ...
    'TimerFcn', {@run_single_snapshot_callback, RunInfo});
setappdata(0, timer_key, t);
start(t);

fprintf('status_file=%s\n', status_file);
fprintf('output_file=%s\n', output_file);

end

function run_single_snapshot_callback(timer_obj, ~, RunInfo)

started_at = datetime('now');
warning_state = warning;
had_old_options = isappdata(0, 'single_snapshot_mcp_gurobi_options');
if had_old_options
    old_options = getappdata(0, 'single_snapshot_mcp_gurobi_options');
else
    old_options = [];
end

write_status(RunInfo.status_file, 'RUNNING', 'Planning script is running.', ...
    'started_at', format_time(started_at), ...
    'script_file', RunInfo.script_file, ...
    'output_file', RunInfo.output_file);

try
    addpath(genpath(fullfile(RunInfo.project_root, 'code', 'functions')));
    setappdata(0, 'single_snapshot_mcp_gurobi_options', struct('quiet', true));
    warning('off', 'all');

    captured_output = evalc('run(RunInfo.script_file);');
    write_text_file(RunInfo.output_file, captured_output);

    [result_file, Result] = find_latest_result(fullfile(RunInfo.project_root, 'results'), started_at);
    if isempty(result_file)
        write_status(RunInfo.status_file, 'NO_RESULT', 'Script finished but no new result file was found.', ...
            'started_at', format_time(started_at), ...
            'finished_at', format_time(datetime('now')), ...
            'output_file', RunInfo.output_file);
    else
        problem = Result.Diagnostics.problem;
        info = Result.Diagnostics.info;
        if problem == 0
            state = 'DONE';
            message = 'Solver finished successfully.';
        else
            state = 'SOLVER_FAILED';
            message = 'Script finished, but the solver did not report success.';
        end

        write_status(RunInfo.status_file, state, message, ...
            'started_at', format_time(started_at), ...
            'finished_at', format_time(datetime('now')), ...
            'result_file', result_file, ...
            'output_file', RunInfo.output_file, ...
            'problem', problem, ...
            'info', info, ...
            'solve_time', Result.solve_time, ...
            'yalmiptime', Result.Diagnostics.yalmiptime, ...
            'solvertime', Result.Diagnostics.solvertime, ...
            'cost_total', Result.Cost.Total, ...
            'cost_gen', Result.Cost.GEN, ...
            'cost_con', Result.Cost.CON, ...
            'u_G', Result.u_G(:)');
    end
catch ME
    write_status(RunInfo.status_file, 'ERROR', ME.message, ...
        'started_at', format_time(started_at), ...
        'finished_at', format_time(datetime('now')), ...
        'output_file', RunInfo.output_file, ...
        'report', getReport(ME, 'extended', 'hyperlinks', 'off'));
end

warning(warning_state);
if had_old_options
    setappdata(0, 'single_snapshot_mcp_gurobi_options', old_options);
else
    rmappdata_if_present('single_snapshot_mcp_gurobi_options');
end

cleanup_timer(timer_obj, RunInfo.timer_key);

end

function [result_file, Result] = find_latest_result(results_dir, started_at)

result_file = '';
Result = struct();
files = dir(fullfile(results_dir, 'single_snapshot_planning_result_*.mat'));
if isempty(files)
    return;
end

start_time = started_at - seconds(1);
file_times = datetime([files.datenum], 'ConvertFrom', 'datenum');
is_new = file_times >= start_time;
files = files(is_new);
if isempty(files)
    return;
end

[~, latest_idx] = max(file_times(is_new));
result_file = fullfile(files(latest_idx).folder, files(latest_idx).name);
loaded = load(result_file, 'Result');
Result = loaded.Result;

end

function write_status(status_file, state, message, varargin)

fid = fopen(status_file, 'w');
if fid < 0
    error('Unable to write status file: %s', status_file);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'state=%s\n', value_to_text(state));
fprintf(fid, 'updated_at=%s\n', format_time(datetime('now')));
fprintf(fid, 'message=%s\n', value_to_text(message));

for idx = 1:2:numel(varargin)
    key = varargin{idx};
    value = varargin{idx + 1};
    fprintf(fid, '%s=%s\n', key, value_to_text(value));
end

delete(cleanup);

end

function text = value_to_text(value)

if ischar(value)
    text = value;
elseif isstring(value)
    text = char(value);
elseif isnumeric(value) || islogical(value)
    text = mat2str(value);
else
    try
        text = jsonencode(value);
    catch
        text = evalc('disp(value)');
    end
end

text = regexprep(text, '[\r\n]+', ' | ');

end

function write_text_file(file_path, content)

fid = fopen(file_path, 'w');
if fid < 0
    error('Unable to write output file: %s', file_path);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', content);
delete(cleanup);

end

function cleanup_timer(timer_obj, timer_key)

try
    stop(timer_obj);
catch
end
try
    delete(timer_obj);
catch
end
rmappdata_if_present(timer_key);

end

function rmappdata_if_present(key)

if isappdata(0, key)
    rmappdata(0, key);
end

end

function text = format_time(time_value)

text = char(time_value, 'yyyy-MM-dd HH:mm:ss');

end

function project_root = resolve_project_root()

candidate = fileparts(fileparts(fileparts(mfilename('fullpath'))));
if isfolder(fullfile(candidate, 'code', 'functions')) && ...
        isfile(fullfile(candidate, 'data', 'params', 'single_snapshot_default_params.json'))
    project_root = candidate;
else
    project_root = pwd;
end

end

function path_value = canonical_path(path_value)

path_value = char(java.io.File(path_value).getCanonicalPath());

end
