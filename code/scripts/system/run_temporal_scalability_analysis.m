%% IV-C 计算性能与时间尺度分析
% 运行本脚本才会启动规划求解。
% 物理参数取当前默认JSON；修改参数源脚本后，应先重新生成该JSON。

Script_File = mfilename('fullpath');
if isempty(Script_File)
    error('TemporalScalability:RunScriptFile', ...
        'Run this script from its saved file so the project root can be located.');
end
Script_Directory = fileparts(Script_File);
addpath(Script_Directory);
Project_Root = resolve_project_root_for_script();
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));

% 本次调试仅运行T=3；聚合和逐时模型均采用新版方程与原始四场景。
% Period_Counts = [3, 6, 12, 24];
Period_Counts = 3;
Wind_Source_File = fullfile(Project_Root, 'data', 'RTS-GMLC', ...
    'processed', 'rts_gmlc_v0.2.3_fixed_extreme_medoids', ...
    'run_20260822_162606', ...
    'rts_gmlc_typical_days_and_wind_scenarios_20260822_162606.mat');

% Load supported external MATLAB dependencies from existing paths or environment paths.
add_temporal_dependency('MATPOWER_PATH', 'case30');
add_temporal_dependency('YALMIP_PATH', 'optimize');
remove_matpower_metadata_paths();
configure_gurobi_matlab_path();

[Summary_Table, Summary_File] = ...
    run_multiple_snapshot_temporal_scalability_scan( ...
    Project_Root, Period_Counts, Wind_Source_File);

function add_temporal_dependency(Environment_Name, Required_Function)
if ~isempty(which(Required_Function))
    return;
end

Dependency_Root = getenv(Environment_Name);
if isempty(Dependency_Root) || ~isfolder(Dependency_Root)
    error('TemporalScalability:MissingDependency', ...
        ['Cannot find %s. Install the dependency and add it to the MATLAB path, ' ...
        'or set the %s environment variable to its installation directory.'], ...
        Required_Function, Environment_Name);
end
addpath(genpath(Dependency_Root));
if isempty(which(Required_Function))
    error('TemporalScalability:InvalidDependencyPath', ...
        '%s does not provide %s on the MATLAB path.', ...
        Dependency_Root, Required_Function);
end
end

function remove_matpower_metadata_paths()
%% MATPOWER的仓库元数据包含未安装的可选求解器测试包装，不应进入搜索路径。
MATPOWER_Root = fileparts(fileparts(which('case30')));
Search_Paths = strsplit(path,pathsep);
for k = 1:numel(Search_Paths)
    Candidate = Search_Paths{k};
    if startsWith(lower(Candidate),lower([MATPOWER_Root filesep])) && ...
            (contains(Candidate,[filesep '.github' filesep]) || ...
            endsWith(Candidate,[filesep '.github']))
        rmpath(Candidate);
    end
end
end

function configure_gurobi_matlab_path()
if ~isempty(which('gurobi'))
    return;
end

Candidate_Paths = {getenv('GUROBI_MATLAB_PATH')};
Gurobi_Home = getenv('GUROBI_HOME');
if ~isempty(Gurobi_Home)
    Candidate_Paths = [Candidate_Paths, ...
        {fullfile(Gurobi_Home, 'matlab'), ...
        fullfile(Gurobi_Home, 'win64', 'matlab'), ...
        fullfile(Gurobi_Home, 'linux64', 'matlab'), ...
        fullfile(Gurobi_Home, 'macos_universal2', 'matlab')}];
end

for k = 1:numel(Candidate_Paths)
    if ~isempty(Candidate_Paths{k}) && isfolder(Candidate_Paths{k})
        addpath(Candidate_Paths{k});
        if ~isempty(which('gurobi'))
            return;
        end
    end
end

error('TemporalScalability:MissingGurobi', ...
    ['Cannot find the Gurobi MATLAB API. Install Gurobi with a valid license ' ...
    'and add its MATLAB folder to the path, or set GUROBI_MATLAB_PATH or GUROBI_HOME.']);
end
