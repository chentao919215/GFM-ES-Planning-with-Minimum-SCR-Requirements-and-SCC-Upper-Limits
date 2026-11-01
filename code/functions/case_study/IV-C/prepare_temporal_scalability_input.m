function Input = prepare_temporal_scalability_input( ...
    Baseline_Params, T, Files, Baseline_Parameter_File)
%% 生成并归档单个时间尺度的共用输入，供聚合与逐时模型使用。

%% 1. 派生时间尺度参数并保存精确数值副本
ensure_directory(Files.T_Directory);
Params = build_temporal_parameters(Baseline_Params, T);
write_json_file(Files.Parameter_File, Params);
% MAT副本记录精确的数值数组、离散UC参数及其基准来源。
save(Files.Input_File, 'Params', 'Baseline_Parameter_File', '-v7.3');

%% 2. 加载并核对输入，设置同一时间尺度共用的求解日志
[Input.mpc, Input.CONF] = prepare_multiple_snapshot_case(Files.Parameter_File);
validate_temporal_input(Input.CONF, Params, Baseline_Params, T);
Input.CONF.solver.options.gurobi.LogFile = fullfile(Files.T_Directory, 'gurobi.log');
end

function Params = build_temporal_parameters(Baseline_Params, T)
%% 沿现有JSON参数链将24个1 h功率点按连续区间取均值。
Params = Baseline_Params;
% AG/PW使用相同物理模型，仅安全状态的时间聚合方式不同。
if T == 24
    return;
end
D = Baseline_Params.Multiple_Snapshot.Typical_Day_Count;
K = Baseline_Params.Multiple_Snapshot.Wind.Count;
Baseline_Wind = Baseline_Params.Multiple_Snapshot.Wind;
Baseline_Snapshot = Baseline_Params.Multiple_Snapshot;
N = numel(Baseline_Params.Multiple_Snapshot.Load_P_MW)/(D*24);
if N ~= round(N) || N < 1
    error('TemporalScalability:InvalidBaselineProfile', ...
        '基准负荷曲线的节点维度不符合要求。');
end
Params.Multiple_Snapshot.Period_Count = T;
Params.Multiple_Snapshot.Period_Durations_Hours = ...
    (24/T)*ones(1, T);
Params.Multiple_Snapshot.Load_P_MW = ...
    average_contiguous_hours( ...
    Baseline_Params.Multiple_Snapshot.Load_P_MW, [N D], T);
Params.Multiple_Snapshot.Wind.P_GFL_Available_Scenarios = ...
    average_contiguous_hours( ...
    Baseline_Wind.P_GFL_Available_Scenarios, [N D K], T);

% 算例准备函数直接读取离散时段数，因此先将最小开停机时间换算为
% 新时间尺度下的时段数并向上取整，其余UC物理参数保持不变。
Baseline_Hours = Baseline_Snapshot.Period_Durations_Hours(1);
Params.UC.Min_Up_Periods = max(1, ceil( ...
    Baseline_Params.UC.Min_Up_Periods*Baseline_Hours/(24/T)));
Params.UC.Min_Down_Periods = max(1, ceil( ...
    Baseline_Params.UC.Min_Down_Periods*Baseline_Hours/(24/T)));
end

function Output = average_contiguous_hours(Input, Prefix_Dimensions, T)
%% 对最后的时间维按q=24/T连续均值；逐组检查日能量守恒。
Expected_Size = prod(Prefix_Dimensions)*24;
if numel(Input) ~= Expected_Size || any(~isfinite(Input(:)))
    error('TemporalScalability:InvalidHourlyData', ...
        '基准24小时输入的尺寸不符合要求，或包含非有限数值。');
end
Hourly = reshape(Input, [], 24);
Block_Size = 24/T;
Averaged = zeros(size(Hourly, 1), T);
for t = 1:T
    Hours = (t-1)*Block_Size + (1:Block_Size);
    Averaged(:, t) = mean(Hourly(:, Hours), 2);
end
Energy_Error = abs(sum(Averaged, 2)*Block_Size - sum(Hourly, 2));
Energy_Tolerance = 1e-10*max(1, abs(sum(Hourly, 2)));
if any(Energy_Error > Energy_Tolerance)
    error('TemporalScalability:EnergyNotPreserved', ...
        '连续时间块平均前后的日内能量不一致。');
end
Output = reshape(Averaged, [Prefix_Dimensions, T]);
end

function validate_temporal_input(CONF, Params, Baseline_Params, T)
%% 复核已加载输入与归档JSON，确保同一T的两种模型使用同一数据。
Param_Wind = Params.Multiple_Snapshot.Wind;
if CONF.PeriodCount ~= T || CONF.TypicalDayCount ~= 4 || ...
        CONF.WindScenarioCount ~= 4 || ...
        ~strcmpi(char(CONF.solver.name), 'gurobi') || ...
        ~isequal(CONF.TypicalDayWeights_Days(:), ...
        Baseline_Params.Multiple_Snapshot.Typical_Day_Weights_Days(:)) || ...
        ~same_numeric_values(CONF.WindScenarioProbabilities(:), ...
        Baseline_Params.Multiple_Snapshot.Wind.Probabilities(:)) || ...
        ~same_numeric_values(CONF.P_Load_Profile(:), ...
        Params.Multiple_Snapshot.Load_P_MW(:)) || ...
        ~same_numeric_values(CONF.P_GFL_Available_Scenarios(:), ...
        Param_Wind.P_GFL_Available_Scenarios(:)) || ...
        ~isequal(CONF.Gen_Min_Up_Periods(:), Params.UC.Min_Up_Periods(:)) || ...
        ~isequal(CONF.Gen_Min_Down_Periods(:), Params.UC.Min_Down_Periods(:))
    error('TemporalScalability:LoadedInputMismatch', ...
        '已加载算例与同一时间尺度的共用输入不一致。');
end
if T == 24 && ~isequaln(Params, Baseline_Params)
    error('TemporalScalability:Baseline24Mismatch', ...
        'T=24时须直接使用原始基准参数。');
end
end

function Same = same_numeric_values(A, B)
%% 容许JSON写读引起的末位舍入，仍逐项核对归档数组。
Same = numel(A) == numel(B) && ...
    all(isfinite(A(:))) && all(isfinite(B(:)));
if Same
    Same = all(abs(A(:)-B(:)) <= 1e-10*max(1, abs(B(:))));
end
end
