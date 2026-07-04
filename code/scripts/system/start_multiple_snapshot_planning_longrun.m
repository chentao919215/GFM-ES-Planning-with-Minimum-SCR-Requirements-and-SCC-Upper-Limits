function RunInfo = start_multiple_snapshot_planning_longrun(project_root)
%% 本函数功能是在后台启动多时段规划主脚本。
%
% MCP桥接调用的同步响应窗口较短。
% 本函数通过timer回调启动主脚本，抑制求解器控制台输出，并将进度写入状态文件。

if nargin < 1 || isempty(project_root)
    project_root = resolve_project_root();
end

project_root = canonical_path(project_root);
functions_dir = fullfile(project_root, 'code', 'functions');
scripts_dir = fullfile(project_root, 'code', 'scripts');
results_dir = fullfile(project_root, 'results');
script_file = fullfile(scripts_dir, 'system', 'run_multiple_snapshot_planning.m');

if ~isfolder(functions_dir)
    error('Missing functions directory: %s', functions_dir);
end
if ~isfile(script_file)
    error('Missing planning script: %s', script_file);
end

addpath(genpath(functions_dir));
ensure_directory(results_dir);

stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
status_file = fullfile(results_dir, ['mcp_multiple_snapshot_longrun_', stamp, '_status.txt']);
output_file = fullfile(results_dir, ['mcp_multiple_snapshot_longrun_', stamp, '_captured_output.txt']);
timer_key = ['multiple_snapshot_longrun_timer_', stamp];

RunInfo = struct();
RunInfo.project_root = project_root;
RunInfo.script_file = script_file;
RunInfo.status_file = status_file;
RunInfo.output_file = output_file;
RunInfo.timer_key = timer_key;

write_status(status_file, 'SCHEDULED', 'Timer has been created.', ...
    'script_file', script_file, 'output_file', output_file);

t = timer('ExecutionMode','singleShot', 'StartDelay',1, ...
    'Name',timer_key, 'TimerFcn',{@run_multiple_snapshot_callback,RunInfo});
setappdata(0, timer_key, t);
start(t);

fprintf('status_file=%s\n', status_file);
fprintf('output_file=%s\n', output_file);

end

function run_multiple_snapshot_callback(timer_obj, ~, RunInfo)
%% 本函数功能是执行后台求解并更新状态文件。

started_at = datetime('now');
warning_state = warning;
option_key = 'multiple_snapshot_mcp_gurobi_options';
had_old_options = isappdata(0, option_key);
if had_old_options
    old_options = getappdata(0, option_key);
else
    old_options = [];
end

write_status(RunInfo.status_file, 'RUNNING', 'Planning script is running.', ...
    'started_at', format_time(started_at), ...
    'script_file', RunInfo.script_file, 'output_file', RunInfo.output_file);

try
    addpath(genpath(fullfile(RunInfo.project_root, 'code', 'functions')));
    setappdata(0, option_key, struct('quiet',true));
    warning('off', 'all');

    captured_output = evalc('run(RunInfo.script_file);');
    write_text_file(RunInfo.output_file, captured_output);

    [result_file, Result] = find_latest_result( ...
        fullfile(RunInfo.project_root, 'results'), started_at);
    if isempty(result_file)
        write_status(RunInfo.status_file, 'NO_RESULT', ...
            'Script finished but no new result file was found.', ...
            'finished_at',format_time(datetime('now')), ...
            'output_file',RunInfo.output_file);
    else
        if Result.Diagnostics.problem == 0
            state = 'DONE';
            message = 'Solver finished successfully.';
        elseif isfield(Result.Diagnostics, 'has_incumbent') && ...
                Result.Diagnostics.has_incumbent
            state = 'TIME_LIMIT_WITH_INCUMBENT';
            message = 'Solver stopped before proof of optimality; the best incumbent was saved.';
        else
            state = 'SOLVER_FAILED';
            message = 'Script finished, but the solver did not report success.';
        end

        write_status(RunInfo.status_file, state, message, ...
            'started_at',format_time(started_at), ...
            'finished_at',format_time(datetime('now')), ...
            'result_file',result_file, 'output_file',RunInfo.output_file, ...
            'problem',Result.Diagnostics.problem, ...
            'info',Result.Diagnostics.info, ...
            'solve_time',Result.solve_time, ...
            'yalmiptime',Result.Diagnostics.yalmiptime, ...
            'solvertime',Result.Diagnostics.solvertime, ...
            'best_bound',read_diagnostic(Result.Diagnostics,'best_bound'), ...
            'mip_gap',read_diagnostic(Result.Diagnostics,'mip_gap'), ...
            'node_count',read_diagnostic(Result.Diagnostics,'node_count'), ...
            'cost_total',Result.Cost.Total, ...
            'wind_scenario_names',Result.CONF.WindScenarioNames, ...
            'wind_scenario_probabilities',Result.CONF.WindScenarioProbabilities, ...
            'u_G_SCC',Result.u_G_SCC, ...
            'u_G_SCR',Result.u_G_SCR, ...
            'u_GFM_Mod',Result.u_GFM_Mod);
    end
catch ME
    write_status(RunInfo.status_file, 'ERROR', ME.message, ...
        'started_at',format_time(started_at), ...
        'finished_at',format_time(datetime('now')), ...
        'output_file',RunInfo.output_file, ...
        'report',getReport(ME,'extended','hyperlinks','off'));
end

warning(warning_state);
if had_old_options
    setappdata(0, option_key, old_options);
else
    rmappdata_if_present(option_key);
end
cleanup_timer(timer_obj, RunInfo.timer_key);

end

function value = read_diagnostic(Diagnostics, field_name)
%% 本函数功能是安全读取可选诊断字段。

if isfield(Diagnostics, field_name)
    value = Diagnostics.(field_name);
else
    value = NaN;
end

end

function [result_file, Result] = find_latest_result(results_dir, started_at)
%% 本函数功能是查找本次后台运行生成的最新结果文件。

result_file = '';
Result = struct();
files = dir(fullfile(results_dir, 'multiple_snapshot_planning_result_*.mat'));
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
%% 本函数功能是覆盖写入后台求解状态。

fid = fopen(status_file, 'w');
if fid < 0
    error('Unable to write status file: %s', status_file);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'state=%s\n', value_to_text(state));
fprintf(fid, 'updated_at=%s\n', format_time(datetime('now')));
fprintf(fid, 'message=%s\n', value_to_text(message));
for idx = 1:2:numel(varargin)
    fprintf(fid, '%s=%s\n', varargin{idx}, value_to_text(varargin{idx+1}));
end
delete(cleanup);

end

function text = value_to_text(value)
%% 本函数功能是将状态字段转换为单行文本。

if ischar(value)
    text = value;
elseif isstring(value)
    text = char(value);
elseif isnumeric(value) || islogical(value)
    text = mat2str(value);
else
    text = jsonencode(value);
end
text = regexprep(text, '[\r\n]+', ' | ');

end

function write_text_file(file_path, content)
%% 本函数功能是保存后台脚本的命令行输出。

fid = fopen(file_path, 'w');
if fid < 0
    error('Unable to write output file: %s', file_path);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', content);
delete(cleanup);

end

function cleanup_timer(timer_obj, timer_key)
%% 本函数功能是清理后台timer及其应用数据。

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
%% 本函数功能是在应用数据存在时将其删除。

if isappdata(0, key)
    rmappdata(0, key);
end

end

function text = format_time(time_value)
%% 本函数功能是将时间转换为状态文件格式。

text = char(time_value, 'yyyy-MM-dd HH:mm:ss');

end

function project_root = resolve_project_root()
%% 本函数功能是解析项目根目录。

candidate = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
if isfolder(fullfile(candidate, 'code', 'functions')) && ...
        isfile(fullfile(candidate, 'data', 'params', ...
        'multiple_snapshot_default_params.json'))
    project_root = candidate;
else
    project_root = pwd;
end

end

function path_value = canonical_path(path_value)
%% 本函数功能是将路径转换为规范绝对路径。

path_value = char(java.io.File(path_value).getCanonicalPath());

end
