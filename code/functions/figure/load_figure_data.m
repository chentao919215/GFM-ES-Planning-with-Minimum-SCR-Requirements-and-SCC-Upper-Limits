function [Data, Output_Directory, Result_File] = load_figure_data(Result_File, Output_Directory, ...
    category, Scenario_Index)
%% 读取规划结果并整理调试图共用的场景、时间轴和设备容量。
Project_Root = find_project_root(mfilename('fullpath'));
if nargin < 1 || isempty(Result_File)
    Result_File = find_latest_result(fullfile(Project_Root, 'results'));
end
if nargin < 2 || isempty(Output_Directory)
    Output_Directory = fullfile(Project_Root, 'figs', category);
end
if nargin < 4 || isempty(Scenario_Index)
    Scenario_Index = 1;
end
Result_File = char(Result_File);
Output_Directory = char(Output_Directory);
if ~isfile(Result_File)
    error('结果文件不存在：%s', Result_File);
end
Loaded = load(Result_File, 'Result');
assert(isfield(Loaded, 'Result') && isstruct(Loaded.Result) && isscalar(Loaded.Result), ...
    'FigureData:InvalidResult', 'MAT文件必须包含Result标量结构体：%s', Result_File);
Data = prepare_debug_data(Loaded.Result, Scenario_Index);
ensure_directory(Output_Directory);
end

function Result_File = find_latest_result(Results_Directory)
%% 按文件修改时间定位主规划结果目录中的最新归档。
Files = dir(fullfile(Results_Directory, 'multiple_snapshot_planning_result_*.mat'));
if isempty(Files)
    error('在results目录中没有找到多时段结果文件：%s', Results_Directory);
end
[~, Index] = max([Files.datenum]);
Result_File = fullfile(Files(Index).folder, Files(Index).name);
end

function Data = prepare_debug_data(Result, Scenario_Index)
%% 提取指定风电场景，并整理时间轴、设备容量和绘图数组。
C = Result.CONF;
N = C.Bn;
D = C.TypicalDayCount;
T = C.PeriodCount;
K = C.WindScenarioCount;
validateattributes(Scenario_Index, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'integer', '>=', 1, '<=', K});

Data.CONF = C;
Data.D = D;
Data.K = K;
Data.G = C.Gn;
Data.L = C.Ln;
Data.Candidate_Buses = C.GFM_Candidate_Buses(:);
Data.Candidate_Count = numel(Data.Candidate_Buses);
Data.Period_Hours = C.PeriodDurations_Hours(:).';
Data.Time_Edges = [0, cumsum(Data.Period_Hours)];
Data.Time_Centers = Data.Time_Edges(1:end-1) + Data.Period_Hours/2;

% 场景运行数组由[元件,典型日,场景,时段]切片为三维数组。
Fields = {'P_Line', 'P_G', 'P_GFL', 'P_GFL_Curt', ...
    'P_GFM_Dis', 'P_GFM_Ch', 'E_GFM', 'u_GFM_Ch'};
Rows = [C.Ln, C.Gn, N, N, repmat(Data.Candidate_Count, 1, 4)];
for k = 1:numel(Fields)
    Values = Result.(Fields{k});
    assert_size(Values, [Rows(k), D, K, T], Fields{k});
    Result.(Fields{k}) = reshape(Values(:, :, Scenario_Index, :), Rows(k), D, T);
end
Data.Result = Result;

Unit_Bus = C.GFM_Unit_Bus(:);
[Found, Candidate_Index] = ismember(Unit_Bus, C.GFM_Candidate_Buses(:));
assert(all(Found), 'FigureData:InvalidUnitBus', ...
    '设备节点必须属于GFM_Candidate_Buses。');
Index = sub2ind(size(Result.u_GFM_Unit), Candidate_Index, C.GFM_Unit_Order(:));
Unit_Built = reshape(round(Result.u_GFM_Unit(Index)), [], 1);
Data.Units_Per_Candidate = full(C.GFM_Candidate_Unit_Mat * Unit_Built);
Data.Installed_Power_MW = full(C.GFM_Candidate_Unit_Mat * ...
    (C.GFM_Unit_PN_MW(:).*Unit_Built));
Data.Installed_Energy_MWh = full(C.GFM_Candidate_Unit_Mat * ...
    (C.GFM_Unit_Energy_MWh(:).*Unit_Built));
Data.Built_Candidate_Mask = Data.Units_Per_Candidate > 0.5;
Data.GFL_Buses = find(C.u_GFL(:) > 0.5);
Data.Generator_Buses = C.Generator_Buses;
Data.Load_MW = C.P_Load_Profile;
Data.GFL_Available_MW = reshape(C.P_GFL_Available_Scenarios( ...
    :, :, Scenario_Index, :), N, D, T).*reshape(C.u_GFL(:), N, 1, 1);
end

function assert_size(Value, Expected, Name)
%% 核验数组维度，允许MATLAB省略尾部单维。
Actual = size(Value);
Actual(end+1:numel(Expected)) = 1;
assert(isequal(Actual, Expected), 'FigureData:DimensionMismatch', ...
    '%s has size %s; expected %s.', Name, mat2str(Actual), mat2str(Expected));
end
