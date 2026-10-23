function Run_Info = start_multiple_snapshot_planning_longrun(Project_Root, Parameter_File)
%% 本函数功能是在后台启动多时段规划主脚本。
%
% MCP桥接调用的同步响应窗口较短。
% 本函数通过timer回调启动主脚本，抑制求解器控制台输出，并将进度写入状态文件。

if nargin < 1 || isempty(Project_Root)
    Project_Root = resolve_project_root();
end
if nargin < 2 || isempty(Parameter_File)
    error('MultipleSnapshot:ParameterFileRequired', ...
        '后台规划同样需要显式提供经确认的算例JSON路径。');
end
Parameter_File = canonical_path(Parameter_File);
assert(isfile(Parameter_File),'参数文件不存在。');

Project_Root = canonical_path(Project_Root);
Functions_Directory = fullfile(Project_Root, 'code', 'functions');
Scripts_Directory = fullfile(Project_Root, 'code', 'scripts');
Results_Directory = fullfile(Project_Root, 'results');
Script_File = fullfile(Scripts_Directory, 'system', 'run_multiple_snapshot_planning.m');

if ~isfolder(Functions_Directory)
    error('Missing functions directory: %s', Functions_Directory);
end
if ~isfile(Script_File)
    error('Missing planning script: %s', Script_File);
end

addpath(genpath(Functions_Directory));
ensure_directory(Results_Directory);

stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
Status_File = fullfile(Results_Directory, ['mcp_multiple_snapshot_longrun_', stamp, '_status.txt']);
Output_File = fullfile(Results_Directory, ['mcp_multiple_snapshot_longrun_', stamp, '_captured_output.txt']);
Timer_Key = ['multiple_snapshot_longrun_timer_', stamp];

Run_Info = struct();
Run_Info.Project_Root = Project_Root;
Run_Info.Script_File = Script_File;
Run_Info.Parameter_File = Parameter_File;
Run_Info.Status_File = Status_File;
Run_Info.Output_File = Output_File;
Run_Info.Timer_Key = Timer_Key;

write_status(Status_File, 'SCHEDULED', 'Timer has been created.', ...
    'script_file', Script_File, 'output_file', Output_File);

t = timer('ExecutionMode','singleShot', 'StartDelay',1, ...
    'Name',Timer_Key, 'TimerFcn',{@run_multiple_snapshot_callback,Run_Info});
setappdata(0, Timer_Key, t);
start(t);

fprintf('status_file=%s\n', Status_File);
fprintf('output_file=%s\n', Output_File);

end

function run_multiple_snapshot_callback(Timer_Obj, ~, Run_Info)
%% 本函数功能是执行后台求解并更新状态文件。

Started_At = datetime('now');
Warning_State = warning;
Option_Key = 'multiple_snapshot_mcp_gurobi_options';
Had_Old_Options = isappdata(0, Option_Key);
if Had_Old_Options
    Old_Options = getappdata(0, Option_Key);
else
    Old_Options = [];
end

write_status(Run_Info.Status_File, 'RUNNING', 'Planning script is running.', ...
    'started_at', format_time(Started_At), ...
    'script_file', Run_Info.Script_File, 'output_file', Run_Info.Output_File);

try
    addpath(genpath(fullfile(Run_Info.Project_Root, 'code', 'functions')));
    addpath(fileparts(Run_Info.Script_File));
    setappdata(0, Option_Key, struct('quiet',true));
    warning('off', 'all');

    Parameter_File = Run_Info.Parameter_File; %#ok<NASGU> 供下方入口脚本读取。
    Captured_Output = evalc('run(Run_Info.Script_File);');
    write_text_file(Run_Info.Output_File, Captured_Output);

    [Result_File, Result] = find_latest_result( ...
        fullfile(Run_Info.Project_Root, 'results'), Started_At);
    if isempty(Result_File)
        write_status(Run_Info.Status_File, 'NO_RESULT', ...
            'Script finished but no new result file was found.', ...
            'finished_at',format_time(datetime('now')), ...
            'output_file',Run_Info.Output_File);
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

        write_status(Run_Info.Status_File, state, message, ...
            'started_at',format_time(Started_At), ...
            'finished_at',format_time(datetime('now')), ...
            'result_file',Result_File, 'output_file',Run_Info.Output_File, ...
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
    write_status(Run_Info.Status_File, 'ERROR', ME.message, ...
        'started_at',format_time(Started_At), ...
        'finished_at',format_time(datetime('now')), ...
        'output_file',Run_Info.Output_File, ...
        'report',getReport(ME,'extended','hyperlinks','off'));
end

warning(Warning_State);
if Had_Old_Options
    setappdata(0, Option_Key, Old_Options);
else
    rmappdata_if_present(Option_Key);
end
cleanup_timer(Timer_Obj, Run_Info.Timer_Key);

end

function value = read_diagnostic(Diagnostics, Field_Name)
%% 本函数功能是安全读取可选诊断字段。

if isfield(Diagnostics, Field_Name)
    value = Diagnostics.(Field_Name);
else
    value = NaN;
end

end

function [Result_File, Result] = find_latest_result(Results_Directory, Started_At)
%% 本函数功能是查找本次后台运行生成的最新结果文件。

Result_File = '';
Result = struct();
files = dir(fullfile(Results_Directory, 'multiple_snapshot_planning_result_*.mat'));
if isempty(files)
    return;
end

Start_Time = Started_At - seconds(1);
File_Times = datetime([files.datenum], 'ConvertFrom', 'datenum');
Is_New = File_Times >= Start_Time;
files = files(Is_New);
if isempty(files)
    return;
end

[~, Latest_Index] = max(File_Times(Is_New));
Result_File = fullfile(files(Latest_Index).folder, files(Latest_Index).name);
loaded = load(Result_File, 'Result');
Result = loaded.Result;

end

function write_status(Status_File, state, message, varargin)
%% 本函数功能是覆盖写入后台求解状态。

fid = fopen(Status_File, 'w');
if fid < 0
    error('Unable to write status file: %s', Status_File);
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

function write_text_file(File_Path, content)
%% 本函数功能是保存后台脚本的命令行输出。

fid = fopen(File_Path, 'w');
if fid < 0
    error('Unable to write output file: %s', File_Path);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', content);
delete(cleanup);

end

function cleanup_timer(Timer_Obj, Timer_Key)
%% 本函数功能是清理后台timer及其应用数据。

try
    stop(Timer_Obj);
catch
end
try
    delete(Timer_Obj);
catch
end
rmappdata_if_present(Timer_Key);

end

function rmappdata_if_present(key)
%% 本函数功能是在应用数据存在时将其删除。

if isappdata(0, key)
    rmappdata(0, key);
end

end

function text = format_time(Time_Value)
%% 本函数功能是将时间转换为状态文件格式。

text = char(Time_Value, 'yyyy-MM-dd HH:mm:ss');

end

function Project_Root = resolve_project_root()
%% 本函数功能是解析项目根目录。

candidate = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
if isfolder(fullfile(candidate, 'code', 'functions')) && ...
        isfile(fullfile(candidate, 'data', 'params', ...
        'multiple_snapshot_default_params.json'))
    Project_Root = candidate;
else
    Project_Root = pwd;
end

end

function Path_Value = canonical_path(Path_Value)
%% 本函数功能是将路径转换为规范绝对路径。

Path_Value = char(java.io.File(Path_Value).getCanonicalPath());

end
