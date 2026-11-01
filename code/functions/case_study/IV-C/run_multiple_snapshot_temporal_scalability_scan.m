function [Summary_Table, Summary_File] = ...
    run_multiple_snapshot_temporal_scalability_scan( ...
    Project_Root, Period_Counts, Wind_Source_File)
%% 按Manuscript第IV-C节比较聚合与逐时安全表示的时间尺度性能。
% 每个T共用一份输入；本函数编排输入准备、逐点求解与汇总导出。

%% 1. 校验时间尺度并准备Case 5基准
validateattributes(Period_Counts, {'numeric'}, ...
    {'vector', 'real', 'finite', 'integer', 'positive', 'nonempty'});
Period_Counts = Period_Counts(:).';
if any(mod(24, Period_Counts) ~= 0) || ...
        numel(unique(Period_Counts)) ~= numel(Period_Counts)
    error('TemporalScalability:InvalidPeriods', ...
        '时段数须为24的正整数因子，且不能重复。');
end
if nargin < 3
    Wind_Source_File = fullfile(Project_Root, 'data', 'RTS-GMLC', ...
        'processed', 'rts_gmlc_profiles.mat');
end
Source_Parameter_File = fullfile(Project_Root, 'data', 'params', ...
    'multiple_snapshot_default_params.json');
Baseline_Params = build_multiple_snapshot_case5_params( ...
    Source_Parameter_File, Wind_Source_File);
Baseline_Params.Temporal_Experiment = struct( ...
    'Source_Parameter_File', Source_Parameter_File, 'Wind_Source_File', Wind_Source_File);
[Solver, Backend] = prepare_multiple_snapshot_solver_parameters(Baseline_Params);
validate_temporal_baseline(Baseline_Params, Solver);
if ~isfield(Backend.options, 'gurobi')
    error('TemporalScalability:MissingGurobiOptions', ...
        '时间尺度分析的基准参数中未配置Gurobi选项。');
end
Stage_Settings = prepare_stage_time_limits(Solver, Backend.name);

%% 2. 创建输出目录与结果汇总容器
Run_Stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
Scan.Run_Directory = fullfile(Project_Root, 'results', ...
    ['multiple_snapshot_temporal_scalability_', Run_Stamp]);
if isfolder(Scan.Run_Directory)
    error('TemporalScalability:ExistingRun', ...
        '带时间戳的输出目录已存在：%s', Scan.Run_Directory);
end
ensure_directory(Scan.Run_Directory);
Scan.Baseline_Parameter_File = fullfile(Scan.Run_Directory, 'baseline_parameters.json');
write_json_file(Scan.Baseline_Parameter_File, Baseline_Params);
Scan.Summary_File = fullfile(Scan.Run_Directory, ...
    ['temporal_scalability_summary_', Run_Stamp, '.mat']);
Scan.Summary_CSV_File = fullfile(Scan.Run_Directory, ...
    ['temporal_scalability_summary_', Run_Stamp, '.csv']);
Scan.Period_Counts = Period_Counts;
Scan.Formulations = ["aggregated", "periodwise"];
Point_Count = numel(Period_Counts)*numel(Scan.Formulations);
Summary = repmat(empty_temporal_summary(), Point_Count, 1);
Summary_File = Scan.Summary_File;

%% 3. 每个时间尺度准备一次输入，再分别求解两种安全约束表示
for i = 1:numel(Period_Counts)
    T = Period_Counts(i);
    Files.T_Directory = fullfile(Scan.Run_Directory, sprintf('T%02d', T));
    Files.Parameter_File = fullfile(Files.T_Directory, 'temporal_parameters.json');
    Files.Input_File = fullfile(Files.T_Directory, 'temporal_input_data.mat');
    Preparation_Error = [];
    try
        Input = prepare_temporal_scalability_input( ...
            Baseline_Params, T, Files, Scan.Baseline_Parameter_File);
    catch ME
        Preparation_Error = ME;
    end

    for j = 1:numel(Scan.Formulations)
        Index = numel(Scan.Formulations)*(i-1) + j;
        Row = initialize_temporal_row(T, Scan.Formulations(j), Files, Baseline_Params);
        if isempty(Preparation_Error)
            Row = solve_temporal_scalability_point(Row, Input, Stage_Settings);
        else
            % 同一T的输入失败时，分别记录两点并继续后续时间尺度。
            Row.Status = "setup_failed";
            Row.Error_Identifier = string(Preparation_Error.identifier);
            Row.Error_Message = string(Preparation_Error.message);
        end
        Summary(Index) = Row;
        Summary_Table = export_temporal_scalability_summary(Summary, Scan);
    end
    if ~isempty(Preparation_Error)
        fprintf(2, '时间尺度T=%d的输入准备失败：%s\n', T, Preparation_Error.message);
    end
end

%% 4. 输出汇总文件位置
fprintf('\n时间尺度分析汇总已保存至：%s\n', Summary_File);
end

function validate_temporal_baseline(Params, Solver)
%% 核对随机算例基准，物理参数与成本沿用当前参数源。
Snapshot = Params.Multiple_Snapshot;
Wind = Params.Multiple_Snapshot.Wind;
if ~Params.Security.Enable_SCC || ~Params.Security.Enable_SCR || ...
        Params.Security.Consider_Wind_Uncertainty ~= 1 || ...
        ~isfinite(Params.Security.I_limit_kA) || ...
        Params.Security.I_limit_kA <= 0 || ...
        ~isfinite(Params.Security.SCR_min) || Params.Security.SCR_min <= 0 || ...
        ~Solver.Two_Stage.Enabled || ...
        Snapshot.Typical_Day_Count ~= 4 || Snapshot.Period_Count ~= 24 || ...
        Wind.Count ~= 4 || ...
        ~isequal(Snapshot.Period_Durations_Hours(:), ones(24, 1))
    error('TemporalScalability:UnexpectedBaseline', ...
        '时间尺度分析要求采用24个1小时段、四典型日和四风电场景的双安全约束基准。');
end
end

function Settings = prepare_stage_time_limits(Solver, Backend)
%% 统一读取两阶段原生时限；缺项仍交由各对比点记录为准备失败。
Settings.Limits = [NaN, NaN];
Settings.Error = [];
try
    for k = 1:2
        Stage_Name = sprintf('Stage_%d', k);
        Stage = Solver.Two_Stage.(Stage_Name);
        if ~isfield(Stage.Options, Backend) || ...
                ~isfield(Stage.Options.(Backend), 'TimeLimit')
            error('TemporalScalability:MissingActiveTimeLimit', ...
                '当前求解器%s的%s阶段未配置原生TimeLimit参数。', ...
                Backend, Stage_Name);
        end
        Settings.Limits(k) = Stage.Options.(Backend).TimeLimit;
    end
catch ME
    Settings.Error = ME;
end
end

function Row = initialize_temporal_row(T, Formulation, Files, Baseline_Params)
%% 初始化一个时间尺度与安全约束表示组合的汇总记录。
Row = empty_temporal_summary();
Row.WindScenarioCount = Baseline_Params.Multiple_Snapshot.Wind.Count;
Row.Period_Count = T;
Row.Period_Duration_Hours = 24/T;
Row.Formulation = Formulation;
Row.Solver_Backend = "gurobi";
Row.Target_MIP_Gap = Baseline_Params.Solver.MIP_Gap;
Row.TimeLimit_Multiplier = 1;
Row.T_Directory = string(Files.T_Directory);
Row.Parameter_File = string(Files.Parameter_File);
Row.Input_Data_File = string(Files.Input_File);
end

function Row = empty_temporal_summary()
%% 定义空汇总记录，每个时间尺度与安全约束表示组合对应一行MAT/CSV结果。
Row = struct();
Row.WindScenarioCount = NaN;
Row.Period_Count = NaN;
Row.Period_Duration_Hours = NaN;
Row.Formulation = "";
Row.Solver_Backend = "";
Row.Status = "pending";
Row.Is_Feasible = false;
Row.Solver_Problem = NaN;
Row.Solver_Info = "";
Row.Final_MIP_Gap = NaN;
Row.Target_MIP_Gap = NaN;
Row.Final_Stage = "";
Row.Total_Annual_Cost = NaN;
Row.GFM_ES_Fixed_Cost = NaN;
Row.SG_Generation_Cost = NaN;
Row.SG_UC_Cost = NaN;
Row.Wind_Curtailment_Cost = NaN;
Row.GFM_Unit_Configuration = "";
Row.Runtime_s = NaN;
Row.Stage_1_Solve_Time_s = NaN;
Row.Stage_2_Solve_Time_s = NaN;
Row.Total_Solve_Time_s = NaN;
Row.Stage_1_TimeLimit_s = NaN;
Row.Stage_2_TimeLimit_s = NaN;
Row.TimeLimit_Multiplier = NaN;
Row.Maximum_SCC_TimeResolved_kA = NaN;
Row.Minimum_SCR_TimeResolved = NaN;
Row.Security_Validation_Passed = false;
Row.Maximum_SCC_Aggregated_Bound_kA = NaN;
Row.Minimum_SCR_Aggregated_Bound = NaN;
Row.AG_Aggregated_Conservatism_Passed = false;
Row.PW_SCC_Posthoc_MaxAbsDifference_kA = NaN;
Row.PW_SCR_Posthoc_MaxAbsDifference = NaN;
Row.T_Directory = "";
Row.Formulation_Directory = "";
Row.Parameter_File = "";
Row.Input_Data_File = "";
Row.Stage_1_Result_File = "";
Row.Stage_2_Result_File = "";
Row.Final_Result_File = "";
Row.Error_Identifier = "";
Row.Error_Message = "";
end

function Summary_Table = export_temporal_scalability_summary(Summary, Scan)
%% 保存指标汇总与实验设置；完整Result仅保存在各阶段文件中。
% Summary_Table中的阶段路径用于定位原始结果，不在汇总中嵌入结果副本。
Summary_Table = struct2table(Summary);
Experiment = struct();
Fields = {'Period_Counts', 'Formulations', 'Baseline_Parameter_File', ...
    'Run_Directory', 'Summary_CSV_File'};
for k = 1:numel(Fields)
    Field = Fields{k};
    Experiment.(Field) = Scan.(Field);
end
save(Scan.Summary_File, 'Summary_Table', 'Experiment', '-v7.3');
writetable(Summary_Table, Scan.Summary_CSV_File);
end
