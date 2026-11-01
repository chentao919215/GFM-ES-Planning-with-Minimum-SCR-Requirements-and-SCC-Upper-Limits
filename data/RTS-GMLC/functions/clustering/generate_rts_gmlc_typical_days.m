function Typical_Day_Sets = generate_rts_gmlc_typical_days(Data, Config)
%% 以最大/最小日前净负荷日为固定medoid生成指定数量的典型日
% 输入日矩阵均为[day, hour]=[365, 24]；D表示最终典型日总数。
% 两个极端日期固定为不可交换medoid，但全部365天仍按最近中心统一分配，
% 因而极端medoid的权重也是其成员数，不固定为1。

Load_Daily = Data.Daily.System_Load_Normalized;
Wind_DA_Daily = Data.Daily.Wind_DA_System_Normalized;
Net_Load_Daily = Data.Daily.DA_Net_Load_Normalized_On_Load_Base;
Day_Count = size(Load_Daily, 1);
Period_Count = size(Load_Daily, 2);
if Period_Count ~= Config.Period_Count || ...
        ~isequal(size(Load_Daily), size(Wind_DA_Daily), ...
        size(Net_Load_Daily))
    error('RTS_GMLC:TypicalDayInputDimensionMismatch', ...
        '典型日负荷、日前风电与日前净负荷矩阵必须同为N×24。');
end
if Day_Count ~= Config.Calendar.Expected_Day_Count
    error('RTS_GMLC:TypicalDayCalendarMismatch', ...
        '典型日生成输入必须恰好包含365个自然日。');
end

%% 1. 识别全年最大、最小日前净负荷所在日期
[maximum_net_load, maximum_linear_index] = max(Net_Load_Daily, [], 'all');
[minimum_net_load, minimum_linear_index] = min(Net_Load_Daily, [], 'all');
[maximum_day_index, maximum_hour] = ind2sub(size(Net_Load_Daily), ...
    maximum_linear_index);
[minimum_day_index, minimum_hour] = ind2sub(size(Net_Load_Daily), ...
    minimum_linear_index);
if maximum_day_index == minimum_day_index
    error('RTS_GMLC:CoincidentExtremeDays', ...
        '全年最大与最小日前净负荷落在同一日，无法构造两个独立固定medoid。');
end
Fixed_Medoid_Day_Index = [maximum_day_index; minimum_day_index];
Extreme_Days = struct( ...
    'Maximum_Day_Index', maximum_day_index, ...
    'Maximum_Date', Data.Dates(maximum_day_index), ...
    'Maximum_Hour', maximum_hour, ...
    'Maximum_Value', maximum_net_load, ...
    'Minimum_Day_Index', minimum_day_index, ...
    'Minimum_Date', Data.Dates(minimum_day_index), ...
    'Minimum_Hour', minimum_hour, ...
    'Minimum_Value', minimum_net_load);

%% 2. 对全年365天的两类24维轨迹分别标准化
[Load_Standardized, Load_Mean, Load_Std] = ...
    standardize_feature_block(Load_Daily, '负荷');
[Wind_Standardized, Wind_Mean, Wind_Std] = ...
    standardize_feature_block(Wind_DA_Daily, '日前风电');
% 两块24维特征分别z-score后再拼接，避免负荷或风电方差单独主导距离。
Joint_Feature = [Load_Standardized, Wind_Standardized];
if any(~isfinite(Joint_Feature), 'all')
    error('RTS_GMLC:InvalidJointFeature', ...
        '标准化后的全年联合特征存在NaN或Inf。');
end
Feature_Standardization = struct( ...
    'Method', '各24维小时特征分别按全年365个自然日做z-score', ...
    'Load_Mean_By_Hour', Load_Mean, ...
    'Load_Std_By_Hour', Load_Std, ...
    'Wind_DA_Mean_By_Hour', Wind_Mean, ...
    'Wind_DA_Std_By_Hour', Wind_Std, ...
    'Joint_Feature_Dimensions', {{'day', ...
    'load_hour_1_to_24', 'wind_da_hour_1_to_24'}});
Output_Dimensions = struct( ...
    'System_Profile', {{'typical_day', 'hour'}}, ...
    'Node_Load', {{'node', 'typical_day', 'hour'}}, ...
    'Wind_Site_Profile', {{'wind_site', 'typical_day', 'hour'}});

%% 3. 采用固定极端medoid约束的PAM生成各D对应的典型日
Typical_Day_Cells = cell(numel(Config.D_Values), 1);
for i_D = 1:numel(Config.D_Values)
    D = Config.D_Values(i_D);
    if D <= numel(Fixed_Medoid_Day_Index) || Day_Count < D
        error('RTS_GMLC:InvalidTypicalDayCount', ...
            '总典型日数量D=%d必须大于固定medoid数量且不超过365。', D);
    end

    [assignment, medoid_day_index, minimum_distance, ...
        constrained_pam] = constrained_fixed_medoid_pam( ...
        Joint_Feature, D, Fixed_Medoid_Day_Index, Config);
    weights = accumarray(assignment, 1, [D, 1]);
    if sum(weights) ~= Day_Count || any(weights <= 0)
        error('RTS_GMLC:TypicalDayWeightMismatch', ...
            'D=%d的典型日权重必须均为正且总和等于365。', D);
    end
    if ~all(ismember(Fixed_Medoid_Day_Index, medoid_day_index))
        error('RTS_GMLC:FixedMedoidLost', ...
            'D=%d的受约束聚类结果未保留两个固定极端medoid。', D);
    end

    Cluster_Error = compute_cluster_error(Load_Daily, Wind_DA_Daily, ...
        Net_Load_Daily, Joint_Feature, assignment, medoid_day_index, ...
        minimum_distance);

    members = cell(D, 1);
    Member_Dates = cell(D, 1);
    for d = 1:D
        members{d} = find(assignment == d);
        Member_Dates{d} = Data.Dates(members{d});
    end

    Set = struct();
    Set.D = D;
    Set.Total_Typical_Day_Count = D;
    Set.Forced_Extreme_Medoid_Count = numel(Fixed_Medoid_Day_Index);
    Set.Typical_Day_Type = ["maximum_da_net_load_fixed_medoid"; ...
        "minimum_da_net_load_fixed_medoid"; ...
        repmat("constrained_pam_medoid", D - 2, 1)];
    Set.Assignment = assignment;
    Set.Medoid_Day_Index = medoid_day_index;
    Set.Medoid_Date = Data.Dates(medoid_day_index);
    Set.Weight_Days = weights;
    Set.Weight_Probability = weights ./ Day_Count;
    Set.Member_Day_Index = members;
    Set.Member_Date = Member_Dates;
    Set.System_Load_Normalized = Load_Daily(medoid_day_index, :);
    Set.Node_Load_Normalized = Data.Daily.Node_Load_Normalized( ...
        :, medoid_day_index, :);
    Set.Wind_DA_System_Normalized = Wind_DA_Daily(medoid_day_index, :);
    Set.Wind_DA_Site_Normalized = ...
        Data.Daily.Wind_DA_Site_Normalized(:, medoid_day_index, :);
    Set.Wind_RT_Site_Normalized = ...
        Data.Daily.Wind_RT_Site_Normalized(:, medoid_day_index, :);
    Set.Cluster_Error = Cluster_Error;
    Set.Constrained_PAM = constrained_pam;
    Set.Extreme_Days = Extreme_Days;
    Set.Feature_Standardization = Feature_Standardization;
    Set.Dimensions = Output_Dimensions;
    Typical_Day_Cells{i_D} = Set;
end

Typical_Day_Sets = vertcat(Typical_Day_Cells{:});

end

%% 4. 本地函数：聚类误差
function Error = compute_cluster_error(Load, Wind, Net_Load, ...
    Joint_Feature, Assignment, Medoid_Index, Minimum_Distance)
% 每个原始日用所属medoid的真实轨迹重构；标准化误差和物理量误差分开保存。
D = numel(Medoid_Index);
Assigned_Index = Medoid_Index(Assignment);
Error = struct();
Error.SSE_Standardized = sum(Minimum_Distance);
Error.Mean_Euclidean_Standardized = mean(sqrt(Minimum_Distance));
Error.RMSE_Per_Standardized_Feature = sqrt( ...
    mean(Minimum_Distance) / size(Joint_Feature, 2));
Error.Load_Trajectory_RMSE_Normalized = profile_rmse( ...
    Load, Load(Assigned_Index, :));
Error.Wind_DA_Trajectory_RMSE_Normalized = profile_rmse( ...
    Wind, Wind(Assigned_Index, :));
Error.DA_Net_Load_Trajectory_RMSE_Normalized = profile_rmse( ...
    Net_Load, Net_Load(Assigned_Index, :));
Error.Sum_Distance_By_Cluster = accumarray( ...
    Assignment, Minimum_Distance, [D, 1], @sum);
end

function Value = profile_rmse(Original, Reconstructed)
%% 按各日曲线计算相对代表曲线的均方根误差。
Value = sqrt(mean((Original - Reconstructed).^2, 'all'));
end

%% 1. 本地函数：固定medoid的PAM交换搜索
function [Assignment, Medoid_Day_Index, Minimum_Distance, Metadata] = ...
    constrained_fixed_medoid_pam(Joint_Feature, D, ...
    Fixed_Medoid_Day_Index, Config)
%% 固定极端日中心，迭代选择其余典型日代表。
Day_Count = size(Joint_Feature, 1);
Fixed_Count = numel(Fixed_Medoid_Day_Index);
Free_Count = D - Fixed_Count;
Candidate_Pool = setdiff((1:Day_Count).', ...
    Fixed_Medoid_Day_Index, 'stable');
Distance_Matrix = pdist2(Joint_Feature, Joint_Feature, ...
    Config.Pairwise_Distance);
Distance_Matrix(1:Day_Count + 1:end) = 0;

Best_Objective = Inf;
Best_Medoid = zeros(D, 1);
Best_Assignment = zeros(Day_Count, 1);
Best_Minimum_Distance = Inf(Day_Count, 1);
Best_Replicate = NaN;
Best_Swap_Iterations = NaN;
Replicate_Objective = Inf(Config.KMedoids_Replicates, 1);

for replicate = 1:Config.KMedoids_Replicates
    % 每个D/重复使用独立且可复现的随机流；第一次以普通PAM结果作为较优初值。
    rng(Config.Random_Seed + 1000 * D + replicate, 'twister');
    if replicate == 1
        [~, ~, ~, ~, initial_local_index] = kmedoids( ...
            Joint_Feature(Candidate_Pool, :), Free_Count, ...
            'Distance', Config.KMedoids_Distance, ...
            'Algorithm', 'pam', 'Replicates', 1);
        initial_free_medoid = Candidate_Pool(initial_local_index(:));
    else
        initial_free_medoid = Candidate_Pool( ...
            randperm(numel(Candidate_Pool), Free_Count));
    end

    [free_medoid, ~, swap_iterations] = fixed_medoid_swap( ...
        Distance_Matrix, Fixed_Medoid_Day_Index, ...
        initial_free_medoid, Config);
    medoid = [Fixed_Medoid_Day_Index; sort(free_medoid(:))];
    [minimum_distance, assignment] = min( ...
        Distance_Matrix(:, medoid), [], 2);
    objective = sum(minimum_distance);
    Replicate_Objective(replicate) = objective;
    if objective < Best_Objective - Config.Numeric_Tolerance || ...
            (abs(objective - Best_Objective) <= Config.Numeric_Tolerance && ...
            lexicographically_precedes(medoid, Best_Medoid))
        Best_Objective = objective;
        Best_Medoid = medoid;
        Best_Assignment = assignment;
        Best_Minimum_Distance = minimum_distance;
        Best_Replicate = replicate;
        Best_Swap_Iterations = swap_iterations;
    end
end

Assignment = Best_Assignment;
Medoid_Day_Index = Best_Medoid;
Minimum_Distance = Best_Minimum_Distance;
Metadata = struct();
Metadata.Method = ...
    'PAM交换搜索；最大/最小日前净负荷日固定不可交换，其余D-2个medoid可交换';
Metadata.Objective_SSE_Standardized = Best_Objective;
Metadata.Best_Replicate = Best_Replicate;
Metadata.Best_Swap_Iteration_Count = Best_Swap_Iterations;
Metadata.Replicate_Objective = Replicate_Objective;
Metadata.Fixed_Medoid_Day_Index = Fixed_Medoid_Day_Index;
Metadata.Free_Medoid_Day_Index = Best_Medoid(Fixed_Count + 1:end);
end

function [Free_Medoid, Objective, Iteration_Count] = fixed_medoid_swap( ...
    Distance_Matrix, Fixed_Medoid, Initial_Free_Medoid, Config)
%% 搜索保持固定中心的代表日交换，并接受目标值改进。
day_count = size(Distance_Matrix, 1);
Fixed_Count = numel(Fixed_Medoid);
Free_Medoid = Initial_Free_Medoid(:);
Medoid = [Fixed_Medoid(:); Free_Medoid];
Objective = sum(min(Distance_Matrix(:, Medoid), [], 2));
Iteration_Count = 0;

for iteration = 1:Config.Fixed_Medoid_Swap_Max_Iterations
    Non_Medoid = setdiff((1:day_count).', Medoid, 'stable');
    Best_Objective = Objective;
    Best_Free_Position = NaN;
    Best_Candidate = NaN;
    % 只允许交换D-2个自由medoid，两个极端medoid始终保留。
    for Free_Position = 1:numel(Free_Medoid)
        Medoid_Position = Fixed_Count + Free_Position;
        for i = 1:numel(Non_Medoid)
            Trial_Medoid = Medoid;
            Trial_Medoid(Medoid_Position) = Non_Medoid(i);
            Trial_Objective = sum(min( ...
                Distance_Matrix(:, Trial_Medoid), [], 2));
            if Trial_Objective < Best_Objective - Config.Numeric_Tolerance
                Best_Objective = Trial_Objective;
                Best_Free_Position = Free_Position;
                Best_Candidate = Non_Medoid(i);
            end
        end
    end
    if isnan(Best_Free_Position)
        break;
    end
    Free_Medoid(Best_Free_Position) = Best_Candidate;
    Medoid = [Fixed_Medoid(:); Free_Medoid];
    Objective = Best_Objective;
    Iteration_Count = iteration;
end
end

function Passed = lexicographically_precedes(Candidate, Reference)
% 目标值相同时按日期索引字典序决胜，保证不同运行得到相同结果。
if all(Reference == 0)
    Passed = true;
    return;
end
First_Difference = find(Candidate ~= Reference, 1, 'first');
Passed = ~isempty(First_Difference) && ...
    Candidate(First_Difference) < Reference(First_Difference);
end

function [X_Standardized, Feature_Mean, Feature_Std] = ...
    standardize_feature_block(X, Description)
% 对每个自然小时跨365天做z-score，禁止逐日或min-max归一化。
Feature_Mean = mean(X, 1);
Feature_Std = std(X, 0, 1);
if any(~isfinite(Feature_Mean)) || any(~isfinite(Feature_Std)) || ...
        any(Feature_Std <= 0)
    error('RTS_GMLC:InvalidFeatureStandardDeviation', ...
        '%s特征存在无效或零标准差小时，无法标准化。', Description);
end
X_Standardized = (X - Feature_Mean) ./ Feature_Std;
end
