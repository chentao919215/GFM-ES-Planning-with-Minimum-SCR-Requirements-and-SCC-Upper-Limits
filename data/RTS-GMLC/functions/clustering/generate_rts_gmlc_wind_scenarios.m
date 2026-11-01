function Wind_Scenario_Sets = generate_rts_gmlc_wind_scenarios( ...
    Data, Typical_Day_Sets, Config)
%% 按每个典型日全部成员的RT实际风电24 h轨迹生成统一K场景
% 每个(D,K)组合要求D个典型日全部使用相同K；若任一成员数<K，整组明确
% 标记为不可用。代表场景是RT真实日medoid，不做DA+误差重构或人工clip。

D_Count = numel(Typical_Day_Sets);
K_Count = numel(Config.K_Values);
Scenario_Cells = cell(D_Count, K_Count);

for i_D = 1:D_Count
    Typical = Typical_Day_Sets(i_D);
    for i_K = 1:K_Count
        K = Config.K_Values(i_K);
        Scenario_Cells{i_D, i_K} = build_one_dk_set( ...
            Data, Typical, K, Config);
    end
end
Wind_Scenario_Sets = reshape([Scenario_Cells{:}], D_Count, K_Count);

end

function Scenario = build_one_dk_set(Data, Typical, K, Config)
%% 针对一个典型日数和场景数组合生成缩减风电场景。
D = Typical.D;
Period_Count = Config.Period_Count;
Member_Count_By_Typical_Day = cellfun(@numel, ...
    Typical.Member_Day_Index);
minimum_member_count = min(Member_Count_By_Typical_Day);

Scenario = initialize_scenario_structure( ...
    D, K, minimum_member_count, Period_Count);
% 不降低K，也不复制场景；不可用原因随结构体和审阅表一起保存。
if minimum_member_count < K
    Scenario.Available = false;
    Scenario.Unavailable_Reason = sprintf( ...
        'D=%d、K=%d不可用：最小典型日成员数%d小于K。', ...
        D, K, minimum_member_count);
    return;
end

Probability = zeros(D, K);
Wind_Scenario = zeros(D, K, Period_Count);
Medoid_Member_Day_Index = zeros(D, K);
Member_Assignment = cell(D, 1);
Member_Day_Index = cell(D, 1);
Scenario_Member_Count = zeros(D, K);
Cluster_RMSE = zeros(D, 1);
Reconstruction_RMSE = zeros(D, 1);
Reconstruction_MAE = zeros(D, 1);
All_Residual = zeros(sum(Member_Count_By_Typical_Day) * Period_Count, 1);
Residual_Offset = 0;

for d = 1:D
    members = Typical.Member_Day_Index{d};
    Member_Count = numel(members);
    Wind_RT_Trajectory = Data.Daily.Wind_RT_System_Normalized(members, :);

    rng(Config.Random_Seed + 10000 * D + 100 * d + K, 'twister');
    [assignment, Medoid_Wind, ~, ~, Medoid_Local_Index] = kmedoids( ...
        Wind_RT_Trajectory, K, ...
        'Distance', Config.KMedoids_Distance, ...
        'Algorithm', 'pam', ...
        'Replicates', Config.KMedoids_Replicates);

    [~, order] = sort(mean(Medoid_Wind, 2), 'ascend');
    % 按场景日均容量因子排序，仅统一输出编号，不改变聚类成员关系。
    Medoid_Wind = Medoid_Wind(order, :);
    Medoid_Local_Index = Medoid_Local_Index(order);
    assignment = remap_cluster_labels(assignment, order);
    probability = accumarray(assignment(:), 1, [K, 1]) ./ Member_Count;
    if abs(sum(probability) - 1) > Config.Probability_Tolerance || ...
            any(probability <= 0)
        error('RTS_GMLC:ScenarioProbabilityMismatch', ...
            'D=%d典型日%d、K=%d的统一场景概率无效。', D, d, K);
    end
    if any(~isfinite(Medoid_Wind), 'all') || ...
            any(Medoid_Wind < -Config.Numeric_Tolerance, 'all') || ...
            any(Medoid_Wind > 1 + Config.Numeric_Tolerance, 'all')
        error('RTS_GMLC:ScenarioPhysicalBoundaryViolation', ...
            'D=%d典型日%d、K=%d的RT medoid场景超出[0,1]。', D, d, K);
    end

    Assigned_Wind = Medoid_Wind(assignment, :);
    residual = Wind_RT_Trajectory - Assigned_Wind;
    Probability(d, :) = probability;
    Wind_Scenario(d, :, :) = Medoid_Wind;
    Medoid_Member_Day_Index(d, :) = members(Medoid_Local_Index(:));
    Member_Assignment{d} = assignment(:);
    Member_Day_Index{d} = members(:);
    Scenario_Member_Count(d, :) = accumarray( ...
        assignment(:), 1, [K, 1]);
    Cluster_RMSE(d) = sqrt(mean(residual.^2, 'all'));
    Reconstruction_RMSE(d) = Cluster_RMSE(d);
    Reconstruction_MAE(d) = mean(abs(residual), 'all');
    Residual_Index = Residual_Offset + (1:numel(residual));
    All_Residual(Residual_Index) = residual(:);
    Residual_Offset = Residual_Offset + numel(residual);
end
if Residual_Offset ~= numel(All_Residual)
    error('RTS_GMLC:ScenarioResidualDimensionMismatch', ...
        'D=%d、K=%d的场景残差数量与成员日×24 h不一致。', D, K);
end

if any(abs(sum(Probability, 2) - 1) > Config.Probability_Tolerance)
    error('RTS_GMLC:ScenarioProbabilityMatrixMismatch', ...
        'D=%d、K=%d存在典型日内部概率和不为1。', D, K);
end

Scenario.Available = true;
Scenario.Unavailable_Reason = "";
Scenario.Probability = Probability;
% 可用组合固定保存为[D, K]概率和[D, K, 24]场景，不使用cell或有效K别名。
Scenario.Wind_Scenario_Normalized = Wind_Scenario;
Scenario.Medoid_Member_Day_Index = Medoid_Member_Day_Index;
Scenario.Medoid_Member_Date = reshape( ...
    Data.Dates(Medoid_Member_Day_Index), D, K);
Scenario.Member_Assignment = Member_Assignment;
Scenario.Member_Day_Index = Member_Day_Index;
Scenario.Scenario_Member_Count = Scenario_Member_Count;
Scenario.Error.Cluster_RMSE_By_Typical_Day = Cluster_RMSE;
Scenario.Error.Wind_Reconstruction_RMSE_By_Typical_Day = ...
    Reconstruction_RMSE;
Scenario.Error.Wind_Reconstruction_MAE_By_Typical_Day = ...
    Reconstruction_MAE;
Overall_RMSE = sqrt(mean(All_Residual.^2));
Scenario.Error.Cluster_RMSE_Overall = Overall_RMSE;
Scenario.Error.Wind_Reconstruction_RMSE_Overall = Overall_RMSE;
Scenario.Error.Wind_Reconstruction_MAE_Overall = mean(abs(All_Residual));

end

%% 1. 本地函数：固定输出模式
function Scenario = initialize_scenario_structure( ...
    D, K, Minimum_Member_Count, Period_Count)
%% 初始化风电场景组合的可用状态、曲线、概率及诊断字段。
Scenario = struct();
Scenario.D = D;
Scenario.K = K;
Scenario.Available = false;
Scenario.Unavailable_Reason = "";
Scenario.Minimum_Typical_Day_Member_Count = Minimum_Member_Count;
Scenario.Probability = zeros(0, 0);
Scenario.Wind_Scenario_Normalized = zeros(0, 0, Period_Count);
Scenario.Medoid_Member_Day_Index = zeros(0, 0);
Scenario.Medoid_Member_Date = NaT(0, 0);
Scenario.Member_Assignment = cell(D, 1);
Scenario.Member_Day_Index = cell(D, 1);
Scenario.Scenario_Member_Count = zeros(0, 0);
Scenario.Error = struct();
Scenario.Error.Cluster_RMSE_By_Typical_Day = NaN(D, 1);
Scenario.Error.Wind_Reconstruction_RMSE_By_Typical_Day = NaN(D, 1);
Scenario.Error.Wind_Reconstruction_MAE_By_Typical_Day = NaN(D, 1);
Scenario.Error.Cluster_RMSE_Overall = NaN;
Scenario.Error.Wind_Reconstruction_RMSE_Overall = NaN;
Scenario.Error.Wind_Reconstruction_MAE_Overall = NaN;
Scenario.Definition = ...
    '对各典型日全部成员的系统聚合归一化RT实际风电完整24 h轨迹直接做k-medoids；每个可用D/K组合的所有典型日均使用统一K';
Scenario.GFL_WG_Use = ...
    '各GFL-WG按额定容量共用系统聚合归一化风电场景；IEEE-30容量映射由项目参数脚本完成';
Scenario.Dimensions = struct( ...
    'Probability', {{'typical_day', 'wind_scenario'}}, ...
    'Wind_Profile', {{'typical_day', 'wind_scenario', 'hour'}});
end

function New_Assignment = remap_cluster_labels(Assignment, Order)
% kmedoids原标签按排序后的medoid位置一一重编号。
Cluster_Count = numel(Order);
Old_To_New = zeros(Cluster_Count, 1);
Old_To_New(Order) = 1:Cluster_Count;
New_Assignment = Old_To_New(Assignment);
end
