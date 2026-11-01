function Params = build_multiple_snapshot_case5_params(Parameter_File, Wind_Source_File)
%% 为Manuscript扫描算例启用双安全约束，并从原始数据恢复四个风电场景。
% 物理、成本和限值参数沿用当前JSON；不会改写参数源脚本或默认JSON。
% 确定性平均轨迹不能还原场景，必须读取生成它的原始RTS-GMLC结果。

%% 1. 读取参数与原始风电场景
if ~isfile(Parameter_File) || ~isfile(Wind_Source_File)
    error('Case5Parameters:MissingInput', ...
        '须同时提供已生成的参数JSON文件与原始风电场景MAT文件。');
end
Params = jsondecode(fileread(Parameter_File));
Loaded = load(Wind_Source_File, 'Result');
Data = Loaded.Result;
D = Params.Multiple_Snapshot.Typical_Day_Count;
T = Params.Multiple_Snapshot.Period_Count;
K = 4;
Typical_Days = Data.Typical_Day_Sets;
Wind = Data.Wind_Scenario_Sets;
if D ~= 4 || T ~= 24 || ~isscalar(Typical_Days) || ~isscalar(Wind) || ...
        Typical_Days.D ~= 4 || Wind.D ~= 4 || Wind.K ~= 4 || ~Wind.Available || ...
        Data.Dimensions.Period_Count ~= 24 || ...
        Data.Dimensions.Period_Duration_Hours ~= 1 || ...
        ~isequal(size(Typical_Days.System_Load_Normalized), [4 24]) || ...
        ~isequal(Params.Multiple_Snapshot.Period_Durations_Hours(:), ones(24, 1))
    error('Case5Parameters:InvalidWindSource', ...
        '固定RTS-GMLC输入须为单组D=4、K=4、24个1小时段。');
end
Probability = Wind.Probability;
Normalized = Wind.Wind_Scenario_Normalized;
N = size(Params.Network.mpc.bus, 1);

%% 2. 核对场景、概率、典型日权重与节点负荷
Expected_Load_P_MW = reshape(Params.Network.mpc.bus(:, 3), N, 1, 1) .* ...
    reshape(Typical_Days.System_Load_Normalized, 1, D, T);
if ~isequal(size(Probability), [D K]) || ...
        ~isequal(size(Normalized), [D K T]) || ...
        any(~isfinite(Probability(:))) || any(Probability(:) <= 0) || ...
        any(abs(sum(Probability, 2)-1) > 1e-12) || ...
        any(~isfinite(Normalized(:))) || any(Normalized(:) < 0) || ...
        ~same_numeric_values(Typical_Days.Weight_Days(:), ...
        Params.Multiple_Snapshot.Typical_Day_Weights_Days(:)) || ...
        ~same_numeric_values(Expected_Load_P_MW(:), ...
        Params.Multiple_Snapshot.Load_P_MW(:))
    error('Case5Parameters:InvalidWindSource', ...
        ['原始风电场景、场景概率、典型日权重', ...
        '或节点负荷与基准参数不一致。']);
end

%% 3. 构造双安全约束下的四场景参数副本
Buses = Params.GFL_WG.Built_Nodes(:);
Ratings = Params.GFL_WG.PN_MW(:);
if isscalar(Ratings)
    Ratings = repmat(Ratings, numel(Buses), 1);
end
Rated_Node = accumarray(Buses, Ratings, [N 1]);
Params.Security.Enable_SCC = true;
Params.Security.Enable_SCR = true;
Params.Security.Consider_Wind_Uncertainty = 1;
Params.Multiple_Snapshot.Wind.Count = K;
Params.Multiple_Snapshot.Wind.Probabilities = Probability;
Params.Multiple_Snapshot.Wind.P_GFL_Available_Scenarios = ...
    reshape(Rated_Node, N, 1, 1, 1).*reshape(Normalized, 1, D, K, T);
end

function Same = same_numeric_values(A, B)
%% 容许JSON写读引起的末位舍入，仍逐项核对原始时序。
Same = numel(A) == numel(B) && ...
    all(isfinite(A(:))) && all(isfinite(B(:)));
if Same
    Same = all(abs(A(:)-B(:)) <= 1e-10*max(1, abs(B(:))));
end
end
