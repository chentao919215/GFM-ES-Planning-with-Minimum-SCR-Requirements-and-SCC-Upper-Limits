function [Data, output_dir] = load_figure_data(result_file, output_dir, param_file, category, scenario_index)
%% 加载绘图所需的结果、参数和公共数据。

figure_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(fileparts(fileparts(figure_dir)));

if nargin < 1 || isempty(result_file)
    result_file = find_latest_result(fullfile(project_root, 'results'));
end
if nargin < 2 || isempty(output_dir)
    output_dir = fullfile(project_root, 'figs', category);
end
if nargin < 3 || isempty(param_file)
    param_file = fullfile(project_root, 'data', 'params', ...
        'multiple_snapshot_default_params.json');
end

result_file = char(result_file);
output_dir = char(output_dir);
param_file = char(param_file);

if ~isfile(result_file)
    error('结果文件不存在：%s', result_file);
end
if ~isfile(param_file)
    error('参数文件不存在：%s', param_file);
end
if ~isfolder(output_dir)
    mkdir(output_dir);
end

loaded = load(result_file, 'Result');
if ~isfield(loaded, 'Result') || ~isstruct(loaded.Result)
    error('MAT文件必须包含Result结构体：%s', result_file);
end

params = jsondecode(fileread(param_file));
if nargin < 5
    scenario_index = [];
end
Data = prepare_figure_data(loaded.Result, params, result_file, param_file, ...
    scenario_index);

end

function result_file = find_latest_result(results_dir)
files = dir(fullfile(results_dir, 'multiple_snapshot_planning_result_*.mat'));
if isempty(files)
    error('在results目录中没有找到多时段结果文件：%s', results_dir);
end
[~, idx] = max([files.datenum]);
result_file = fullfile(files(idx).folder, files(idx).name);
end
