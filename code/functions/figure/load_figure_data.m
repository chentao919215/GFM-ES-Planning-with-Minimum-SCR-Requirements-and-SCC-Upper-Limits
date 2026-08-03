function [Data, Output_Directory] = load_figure_data(Result_File, Output_Directory, Parameter_File, category, Scenario_Index)
%% 加载绘图所需的结果、参数和公共数据。

Figure_Directory = fileparts(mfilename('fullpath'));
Project_Root = fileparts(fileparts(fileparts(Figure_Directory)));

if nargin < 1 || isempty(Result_File)
    Result_File = find_latest_result(fullfile(Project_Root, 'results'));
end
if nargin < 2 || isempty(Output_Directory)
    Output_Directory = fullfile(Project_Root, 'figs', category);
end
if nargin < 3 || isempty(Parameter_File)
    Parameter_File = fullfile(Project_Root, 'data', 'params', ...
        'multiple_snapshot_default_params.json');
end

Result_File = char(Result_File);
Output_Directory = char(Output_Directory);
Parameter_File = char(Parameter_File);

if ~isfile(Result_File)
    error('结果文件不存在：%s', Result_File);
end
if ~isfile(Parameter_File)
    error('参数文件不存在：%s', Parameter_File);
end
if ~isfolder(Output_Directory)
    mkdir(Output_Directory);
end

loaded = load(Result_File, 'Result');
if ~isfield(loaded, 'Result') || ~isstruct(loaded.Result)
    error('MAT文件必须包含Result结构体：%s', Result_File);
end

params = jsondecode(fileread(Parameter_File));
if nargin < 5
    Scenario_Index = [];
end
Data = prepare_figure_data(loaded.Result, params, Result_File, Parameter_File, ...
    Scenario_Index);

end

function Result_File = find_latest_result(Results_Directory)
files = dir(fullfile(Results_Directory, 'multiple_snapshot_planning_result_*.mat'));
if isempty(files)
    error('在results目录中没有找到多时段结果文件：%s', Results_Directory);
end
[~, idx] = max([files.datenum]);
Result_File = fullfile(files(idx).folder, files(idx).name);
end
