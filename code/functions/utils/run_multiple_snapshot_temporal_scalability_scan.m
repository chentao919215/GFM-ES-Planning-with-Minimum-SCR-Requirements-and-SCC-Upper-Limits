function [Summary_Table, Summary_File] = ...
    run_multiple_snapshot_temporal_scalability_scan( ...
    Project_Root, Period_Counts, Wind_Source_File)
%% 按IV-C两阶段流程比较聚合与逐时安全表示的时间尺度性能。
% 每个T仅构造和加载一份输入；运行本函数才会启动两种模型求解。

validateattributes(Period_Counts, {'numeric'}, ...
    {'vector', 'real', 'finite', 'integer', 'positive', 'nonempty'});
Period_Counts = Period_Counts(:).';
if any(mod(24, Period_Counts) ~= 0) || ...
        numel(unique(Period_Counts)) ~= numel(Period_Counts)
    error('TemporalScalability:InvalidPeriods', ...
        'Period counts must be unique integer divisors of 24.');
end

% 实验使用新版、双安全约束和原始四场景，不改写项目默认参数文件。
if nargin < 3
    Wind_Source_File = fullfile(Project_Root, 'data', 'RTS-GMLC', ...
        'processed', 'rts_gmlc_v0.2.3_fixed_extreme_medoids', ...
        'run_20260822_162606', ...
        'rts_gmlc_typical_days_and_wind_scenarios_20260822_162606.mat');
end
Source_Parameter_File = fullfile(Project_Root, 'data', 'params', ...
    'multiple_snapshot_default_params.json');
Baseline_Params = build_temporal_baseline(Source_Parameter_File, Wind_Source_File);
validate_temporal_baseline(Baseline_Params);
if ~isfield(Baseline_Params.solver.options, 'gurobi')
    error('TemporalScalability:MissingGurobiOptions', ...
        'The temporal baseline parameters do not define Gurobi options.');
end

Run_Stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
Run_Directory = fullfile(Project_Root, 'results', ...
    ['multiple_snapshot_temporal_scalability_', Run_Stamp]);
if isfolder(Run_Directory)
    error('TemporalScalability:ExistingRun', ...
        'The timestamped output directory already exists: %s', Run_Directory);
end
ensure_directory(Run_Directory);
Baseline_Parameter_File = fullfile(Run_Directory, 'baseline_parameters.json');
write_temporal_parameters(Baseline_Parameter_File, Baseline_Params);
Summary_File = fullfile(Run_Directory, ...
    ['temporal_scalability_summary_', Run_Stamp, '.mat']);
Summary_CSV_File = fullfile(Run_Directory, ...
    ['temporal_scalability_summary_', Run_Stamp, '.csv']);

Formulations = ["aggregated", "periodwise"];
Point_Count = numel(Period_Counts)*numel(Formulations);
Summary = repmat(empty_temporal_summary(), Point_Count, 1);
Planning_Results = cell(Point_Count, 1);
Planning_Results_Stage_1 = cell(Point_Count, 1);
Planning_Results_Stage_2 = cell(Point_Count, 1);
Summary_Table = struct2table(Summary);

for i = 1:numel(Period_Counts)
    T = Period_Counts(i);
    Period_Duration_Hours = 24/T;
    T_Directory = fullfile(Run_Directory, sprintf('T%02d', T));
    Parameter_File = fullfile(T_Directory, 'temporal_parameters.json');
    Input_File = fullfile(T_Directory, 'temporal_input_data.mat');

    try
        ensure_directory(T_Directory);
        Params = build_temporal_parameters(Baseline_Params, T);
        write_temporal_parameters(Parameter_File, Params);
        % MAT副本记录精确的数值数组、离散UC参数及其基准来源。
        save(Input_File, 'Params', 'Baseline_Parameter_File', '-v7.3');
        [mpc, CONF, paths] = load_multiple_snapshot_case( ...
            Project_Root, Parameter_File);
        validate_temporal_input(CONF, Params, Baseline_Params, T);
        % 同一T共用日志路径；记录实际求解进度且避免依赖当前工作目录。
        CONF.solver.options.gurobi.LogFile = fullfile(T_Directory,'gurobi.log');
    catch ME
        % 单个T的输入失败时，分别记录AG/PW两点并继续后续T。
        for j = 1:numel(Formulations)
            Index = 2*(i-1) + j;
            Row = initialize_temporal_row(T, Period_Duration_Hours, ...
                Formulations(j), T_Directory, Parameter_File, Input_File, ...
                Baseline_Params);
            Row.Status = "setup_failed";
            Row.Error_Identifier = string(ME.identifier);
            Row.Error_Message = string(ME.message);
            Summary(Index) = Row;
            Summary_Table = checkpoint_temporal_summary( ...
                Summary, Planning_Results, Planning_Results_Stage_1, ...
                Planning_Results_Stage_2, Period_Counts, Formulations, ...
                Baseline_Parameter_File, Run_Directory, Summary_File, ...
                Summary_CSV_File);
        end
        fprintf(2, 'Temporal input T=%d failed: %s\n', T, ME.message);
        continue;
    end

    for j = 1:numel(Formulations)
        Index = 2*(i-1) + j;
        Formulation = Formulations(j);
        fprintf('\nTemporal T=%d (%g h per period), %s\n', ...
            T, Period_Duration_Hours, Formulation);
        Formulation_Tic = tic;
        Current_Stage = "setup";
        Row = initialize_temporal_row(T, Period_Duration_Hours, ...
            Formulation, T_Directory, Parameter_File, Input_File, ...
            Baseline_Params);
        Formulation_Directory = fullfile(T_Directory, char(Formulation));
        Row.Formulation_Directory = string(Formulation_Directory);

        try
            Stage_1_Directory = fullfile(Formulation_Directory, 'stage_1');
            Stage_2_Directory = fullfile(Formulation_Directory, 'stage_2');
            ensure_directory(Stage_1_Directory);
            ensure_directory(Stage_2_Directory);

            % AG/PW采用完全相同的两阶段求解配置，包括原生TimeLimit。
            CONF_Formulation = CONF;
            validate_solver_pair(CONF, CONF_Formulation);
            Row.Stage_1_TimeLimit_s = active_stage_time_limit( ...
                CONF_Formulation, 'Stage_1');
            Row.Stage_2_TimeLimit_s = active_stage_time_limit( ...
                CONF_Formulation, 'Stage_2');

            Current_Stage = "stage_1";
            fprintf('Stage 1 TimeLimit=%g s; target gap=%g\n', ...
                Row.Stage_1_TimeLimit_s, ...
                CONF_Formulation.Solver.Two_Stage.Stage_1.MIP_Gap);
            CONF_Stage_1 = apply_multiple_snapshot_solver_stage( ...
                CONF_Formulation, ...
                CONF_Formulation.Solver.Two_Stage.Stage_1);
            Paths_Stage_1 = paths;
            Paths_Stage_1.results_dir = Stage_1_Directory;
            [Result_Stage_1, Result_File_Stage_1] = ...
                solve_temporal_stage(mpc, CONF_Stage_1, ...
                Paths_Stage_1, Formulation);
            Row.Stage_1_Result_File = string(Result_File_Stage_1);
            Row.Stage_1_Solve_Time_s = Result_Stage_1.solve_time;
            Planning_Results_Stage_1{Index} = Result_Stage_1;
            if ~Result_Stage_1.Diagnostics.has_incumbent
                error('TemporalScalability:NoStage1Incumbent', ...
                    'Stage 1 returned no feasible incumbent.');
            end
            Planning_Results{Index} = Result_Stage_1;
            Row.Is_Feasible = true;
            Row.Final_Stage = "stage_1";
            Row.Final_Result_File = string(Result_File_Stage_1);
            Row = summarize_temporal_result(Row, Result_Stage_1, ...
                Result_File_Stage_1, "stage_1");

            % 仅从本formulation自己的第一阶段结果构造第二阶段热启动。
            if ~(Result_Stage_1.Diagnostics.mip_gap <= ...
                    CONF_Formulation.Solver.Two_Stage.Stage_2.MIP_Gap)
                Current_Stage = "stage_2";
                fprintf('Stage 2 TimeLimit=%g s; target gap=%g\n', ...
                    Row.Stage_2_TimeLimit_s, ...
                    CONF_Formulation.Solver.Two_Stage.Stage_2.MIP_Gap);
                CONF_Stage_2 = apply_multiple_snapshot_solver_stage( ...
                    CONF_Formulation, ...
                    CONF_Formulation.Solver.Two_Stage.Stage_2);
                CONF_Stage_2.Solver.MIP_Start = ...
                    build_multiple_snapshot_mip_start_from_result( ...
                    Result_Stage_1, CONF_Stage_2);
                CONF_Stage_2.Solver.MIP_Start.Source_File = ...
                    Result_File_Stage_1;
                Paths_Stage_2 = paths;
                Paths_Stage_2.results_dir = Stage_2_Directory;
                [Result_Stage_2, Result_File_Stage_2] = ...
                    solve_temporal_stage(mpc, CONF_Stage_2, ...
                    Paths_Stage_2, Formulation);
                Row.Stage_2_Result_File = string(Result_File_Stage_2);
                Row.Stage_2_Solve_Time_s = Result_Stage_2.solve_time;
                Planning_Results_Stage_2{Index} = Result_Stage_2;
                if ~Result_Stage_2.Diagnostics.has_incumbent
                    error('TemporalScalability:NoStage2Incumbent', ...
                        'Stage 2 returned no feasible incumbent.');
                end
                Planning_Results{Index} = Result_Stage_2;
                Row.Is_Feasible = true;
                Row.Final_Stage = "stage_2";
                Row.Final_Result_File = string(Result_File_Stage_2);
                Row = summarize_temporal_result(Row, Result_Stage_2, ...
                    Result_File_Stage_2, "stage_2");
            end

            if ~Row.Security_Validation_Passed
                error('TemporalScalability:SecurityValidationFailed', ...
                    'The final incumbent failed the independent security checks.');
            end
            if Row.Final_MIP_Gap <= Row.Target_MIP_Gap
                Row.Status = "target_met";
            else
                Row.Status = "feasible_target_not_met";
            end
        catch ME
            % Stage 2失败时，已保存的Stage 1可行解仍是最终结果。
            Row.Status = Current_Stage + "_failed";
            if Row.Is_Feasible
                Row.Status = Row.Status + "_with_incumbent";
            end
            Row.Error_Identifier = string(ME.identifier);
            Row.Error_Message = string(ME.message);
            fprintf(2, 'Temporal point T=%d, %s failed: %s\n', ...
                T, Formulation, ME.message);
        end

        Row.Runtime_s = toc(Formulation_Tic);
        Stage_Times = [Row.Stage_1_Solve_Time_s, ...
            Row.Stage_2_Solve_Time_s];
        if any(isfinite(Stage_Times))
            Row.Total_Solve_Time_s = sum(Stage_Times, 'omitnan');
        end
        Summary(Index) = Row;
        Summary_Table = checkpoint_temporal_summary( ...
            Summary, Planning_Results, Planning_Results_Stage_1, ...
            Planning_Results_Stage_2, Period_Counts, Formulations, ...
            Baseline_Parameter_File, Run_Directory, Summary_File, ...
            Summary_CSV_File);
    end
end

fprintf('\nTemporal scalability summary: %s\n', Summary_File);
end

function Summary_Table = checkpoint_temporal_summary( ...
    Summary, Planning_Results, Planning_Results_Stage_1, ...
    Planning_Results_Stage_2, Period_Counts, Formulations, ...
    Baseline_Parameter_File, Run_Directory, Summary_File, Summary_CSV_File)
%% 每个formulation后保存完整MAT和可直接绘图的CSV。
Summary_Table = struct2table(Summary);
save(Summary_File, 'Summary', 'Summary_Table', 'Planning_Results', ...
    'Planning_Results_Stage_1', 'Planning_Results_Stage_2', ...
    'Period_Counts', 'Formulations', 'Baseline_Parameter_File', ...
    'Run_Directory', 'Summary_CSV_File', '-v7.3');
writetable(Summary_Table, Summary_CSV_File);
end

function validate_temporal_baseline(Params)
%% 核对新版随机实验基准，物理参数与成本沿用当前参数源。
Time = Params.Multiple_Snapshot.Time;
Wind = Params.Multiple_Snapshot.Wind_Scenarios;
if ~strcmp(Params.ModelVersion,'2026-10-23') || ...
        ~Params.Security.Enable_SCC || ~Params.Security.Enable_SCR || ...
        Params.Security.Consider_Wind_Uncertainty ~= 1 || ...
        ~isfinite(Params.Security.I_limit_kA) || ...
        Params.Security.I_limit_kA <= 0 || ...
        ~isfinite(Params.Security.SCR_min) || Params.Security.SCR_min <= 0 || ...
        ~Params.Solver.Two_Stage.Enabled || ...
        Time.Typical_Day_Count ~= 4 || Time.Period_Count ~= 24 || ...
        Wind.Count ~= 4 || ...
        ~strcmpi(char(Wind.Generation_Mode), 'explicit') || ...
        ~isequal(Time.Period_Durations_Hours(:), ones(24,1))
    error('TemporalScalability:UnexpectedBaseline', ...
        'The temporal experiment requires the new 24-hour, four-scenario security baseline.');
end
end

function Params = build_temporal_baseline(Parameter_File, Wind_Source_File)
%% 从原始RTS-GMLC结果恢复四场景，避免从确定性平均轨迹反推场景。
if ~isfile(Parameter_File) || ~isfile(Wind_Source_File)
    error('TemporalScalability:MissingBaselineInput', ...
        'Both the generated parameter JSON and the original wind MAT file are required.');
end
Params = jsondecode(fileread(Parameter_File));
Loaded = load(Wind_Source_File, 'Result');
Data = Loaded.Result;
D = Params.Multiple_Snapshot.Time.Typical_Day_Count;
T = Params.Multiple_Snapshot.Time.Period_Count;
K = 4;
D_Index = find([Data.Typical_Day_Sets.D] == D, 1);
if isempty(D_Index)
    error('TemporalScalability:MissingTypicalDays', ...
        'The original wind source has no D=%d typical-day set.', D);
end
Typical_Days = Data.Typical_Day_Sets(D_Index);
Scenario_Row = Data.Wind_Scenario_Sets(D_Index,:);
K_Index = find([Scenario_Row.K] == K, 1);
if isempty(K_Index) || ~Scenario_Row(K_Index).Available
    error('TemporalScalability:MissingWindScenarios', ...
        'The original source does not provide D=%d, K=%d wind scenarios.', D, K);
end
Wind = Scenario_Row(K_Index);
Probability = Wind.Probability;
Normalized = Wind.Wind_Scenario_Normalized;
if ~isequal(size(Probability),[D K]) || ...
        ~isequal(size(Normalized),[D K T]) || ...
        any(~isfinite(Probability(:))) || any(Probability(:) <= 0) || ...
        any(abs(sum(Probability,2)-1) > 1e-12) || ...
        any(~isfinite(Normalized(:))) || any(Normalized(:) < 0) || ...
        ~same_numeric_values(Typical_Days.Weight_Days(:), ...
        Params.Multiple_Snapshot.Time.Typical_Day_Weights_Days(:)) || ...
        ~same_numeric_values(Typical_Days.System_Load_Normalized(:), ...
        Params.Multiple_Snapshot.Profiles.Load_Factor(:))
    error('TemporalScalability:InvalidWindSource', ...
        'Original scenario probabilities, profiles, or typical days do not match the baseline.');
end
N = size(Params.Network.mpc.bus,1);
Buses = Params.GFL_WG.Built_Nodes(:);
Ratings = Params.GFL_WG.PN_MW(:);
if isscalar(Ratings), Ratings = repmat(Ratings,numel(Buses),1); end
Rated_Node = accumarray(Buses,Ratings,[N 1]);
Params.ModelVersion = '2026-10-23';
Params.Security.Enable_SCC = true;
Params.Security.Enable_SCR = true;
Params.Security.Consider_Wind_Uncertainty = 1;
Params.Multiple_Snapshot.Wind_Scenarios.Count = K;
Params.Multiple_Snapshot.Wind_Scenarios.Generation_Mode = 'explicit';
Params.Multiple_Snapshot.Wind_Scenarios.Names = ...
    arrayfun(@(k) sprintf('scenario_%d',k),1:K,'UniformOutput',false);
Params.Multiple_Snapshot.Wind_Scenarios.Probabilities = Probability;
Params.Multiple_Snapshot.Wind_Scenarios.P_GFL_Available_Scenarios = ...
    reshape(Rated_Node,N,1,1,1).*reshape(Normalized,1,D,K,T);
Params.Temporal_Experiment = struct('Source_Parameter_File',Parameter_File, ...
    'Wind_Source_File',Wind_Source_File);
end

function Params = build_temporal_parameters(Baseline_Params, T)
%% 沿现有JSON参数链将24个1 h功率点按连续区间取均值。
Params = Baseline_Params;
% AG/PW使用相同新版物理模型，仅安全状态的时间聚合方式不同。
if T == 24
    return;
end
D = Baseline_Params.Multiple_Snapshot.Time.Typical_Day_Count;
K = Baseline_Params.Multiple_Snapshot.Wind_Scenarios.Count;
Baseline_Wind = Baseline_Params.Multiple_Snapshot.Wind_Scenarios;
Baseline_Time = Baseline_Params.Multiple_Snapshot.Time;
N = numel(Baseline_Params.Multiple_Snapshot.Profiles.Load_P_MW)/(D*24);
if N ~= round(N) || N < 1
    error('TemporalScalability:InvalidBaselineProfile', ...
        'The baseline load profile has an invalid node dimension.');
end
Params.Multiple_Snapshot.Time.Period_Count = T;
Params.Multiple_Snapshot.Time.Period_Durations_Hours = ...
    (24/T)*ones(1,T);
Params.Multiple_Snapshot.Profiles.Load_Factor = ...
    average_contiguous_hours( ...
    Baseline_Params.Multiple_Snapshot.Profiles.Load_Factor, D, T);
Params.Multiple_Snapshot.Profiles.Load_P_MW = ...
    average_contiguous_hours( ...
    Baseline_Params.Multiple_Snapshot.Profiles.Load_P_MW, [N D], T);
Params.Multiple_Snapshot.Profiles.GFL_Available_P_MW = ...
    average_contiguous_hours( ...
    Baseline_Params.Multiple_Snapshot.Profiles.GFL_Available_P_MW, ...
    [N D], T);
Params.Multiple_Snapshot.Wind_Scenarios.P_GFL_Available_Scenarios = ...
    average_contiguous_hours( ...
    Baseline_Wind.P_GFL_Available_Scenarios, [N D K], T);

% Loader直接读取离散period count，不按时长换算；在同一JSON参数链
% 写出ceil(基准1 h时段数 / 新时段小时数)，其余UC物理参数原样保留。
Baseline_Hours = Baseline_Time.Period_Durations_Hours(1);
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
        'A baseline 24-hour input has invalid size or nonfinite values.');
end
Hourly = reshape(Input, [], 24);
Block_Size = 24/T;
Averaged = zeros(size(Hourly,1), T);
for t = 1:T
    Hours = (t-1)*Block_Size + (1:Block_Size);
    Averaged(:,t) = mean(Hourly(:,Hours), 2);
end
Energy_Error = abs(sum(Averaged,2)*Block_Size - sum(Hourly,2));
Energy_Tolerance = 1e-10*max(1, abs(sum(Hourly,2)));
if any(Energy_Error > Energy_Tolerance)
    error('TemporalScalability:EnergyNotPreserved', ...
        'Contiguous averaging did not preserve daily energy.');
end
Output = reshape(Averaged, [Prefix_Dimensions, T]);
end

function write_temporal_parameters(File_Path, Params)
%% 每个T只写一份派生JSON，供AG/PW共用。
fid = fopen(File_Path, 'w', 'n', 'UTF-8');
if fid < 0
    error('TemporalScalability:ParameterWriteFailed', ...
        'Cannot write parameter file: %s', File_Path);
end
try
    fprintf(fid, '%s\n', jsonencode(Params, 'PrettyPrint', true));
catch ME
    fclose(fid);
    rethrow(ME);
end
fclose(fid);
end

function validate_temporal_input(CONF, Params, Baseline_Params, T)
%% 复核已加载输入与归档JSON，确保同一T的两种模型使用同一数据。
Time = CONF.Multiple_Snapshot.Time;
Wind = CONF.Multiple_Snapshot.Wind_Scenarios;
Profile = CONF.Multiple_Snapshot.Profiles;
Param_Wind = Params.Multiple_Snapshot.Wind_Scenarios;
if Time.Period_Count ~= T || Time.Typical_Day_Count ~= 4 || ...
        Wind.Count ~= 4 || ...
        ~strcmpi(char(CONF.solver.name), 'gurobi') || ...
        ~isequal(Time.Typical_Day_Weights_Days(:), ...
        Baseline_Params.Multiple_Snapshot.Time.Typical_Day_Weights_Days(:)) || ...
        ~same_numeric_values(Wind.Probabilities(:), ...
        Baseline_Params.Multiple_Snapshot.Wind_Scenarios.Probabilities(:)) || ...
        ~same_numeric_values(Profile.P_Load_Profile(:), ...
        Params.Multiple_Snapshot.Profiles.Load_P_MW(:)) || ...
        ~same_numeric_values(Profile.P_GFL_Available_Profile(:), ...
        Params.Multiple_Snapshot.Profiles.GFL_Available_P_MW(:)) || ...
        ~same_numeric_values(Wind.P_GFL_Available_Scenarios(:), ...
        Param_Wind.P_GFL_Available_Scenarios(:)) || ...
        ~isequal(CONF.UC.Min_Up_Periods(:), Params.UC.Min_Up_Periods(:)) || ...
        ~isequal(CONF.UC.Min_Down_Periods(:), Params.UC.Min_Down_Periods(:))
    error('TemporalScalability:LoadedInputMismatch', ...
        'The loaded case differs from the shared temporal input.');
end
if T == 24 && ~isequaln(Params, Baseline_Params)
    error('TemporalScalability:Baseline24Mismatch', ...
        'T=24 must use the original baseline parameters unchanged.');
end
end

function Same = same_numeric_values(A, B)
%% 容许JSON写读引起的末位舍入，仍逐项核对归档数组。
Same = numel(A) == numel(B) && ...
    all(isfinite(A(:))) && all(isfinite(B(:)));
if Same
    Same = all(abs(A(:)-B(:)) <= 1e-10*max(1,abs(B(:))));
end
end

function validate_solver_pair(AG_CONF, PW_CONF)
%% 运行时确保两个模型的基础选项及两阶段选项完全一致。
if ~isequaln(AG_CONF.solver, PW_CONF.solver) || ...
        ~isequaln(AG_CONF.Solver, PW_CONF.Solver)
    error('TemporalScalability:SolverSettingsMismatch', ...
        'AG and PW solver settings must be identical.');
end
end

function Limit = active_stage_time_limit(CONF, Stage_Name)
%% 读取apply_multiple_snapshot_solver_stage实际覆盖的原生参数。
Stage = CONF.Solver.Two_Stage.(Stage_Name);
Backend = lower(char(CONF.solver.name));
if ~isfield(Stage.Options, Backend) || ...
        ~isfield(Stage.Options.(Backend), 'TimeLimit')
    error('TemporalScalability:MissingActiveTimeLimit', ...
        'Active backend %s has no native %s TimeLimit.', ...
        Backend, Stage_Name);
end
Limit = Stage.Options.(Backend).TimeLimit;
end

function [Result, Result_File] = ...
    solve_temporal_stage(mpc, CONF, paths, Formulation)
%% 保持IV-C结果接口，仅按formulation选择已有AG或新PW求解函数。
CONF = normalize_multiple_snapshot_conf(CONF);
CONF.SecurityFormulation = char(Formulation);
switch Formulation
    case "aggregated"
        Solver = @solve_multiple_snapshot_planning;
    case "periodwise"
        Solver = @solve_multiple_snapshot_planning_periodwise;
    otherwise
        error('TemporalScalability:InvalidFormulation', ...
            'Unknown security formulation: %s', Formulation);
end

Solve_Tic = tic;
[~,SCC_1,~,P_Line,theta,P_G,P_GFL,P_GFM,SCR,Z_SCC,Z_SCR, ...
    ~,u_G,u_G_SCC,u_G_SCR,Cost_CON,Cost_GEN,Cost_Total,Diagnostics, ...
    u_GFM_Module,P_GFM_Dis,P_GFM_Ch,E_GFM,u_GFM_Ch,P_GFL_Curt,Cost_Curt, ...
    u_G_Start,u_G_Stop,Cost_UC,SCC_TimeResolved,SCR_TimeResolved, ...
    SecurityValidation] = Solver(mpc, CONF);
Solve_Time = toc(Solve_Tic);

Result = package_multiple_snapshot_result( ...
    SCC_1,SCC_TimeResolved,P_Line,theta,P_G,P_GFL,P_GFM,SCR, ...
    SCR_TimeResolved,Z_SCC,Z_SCR,u_G,u_G_SCC,u_G_SCR, ...
    Cost_CON,Cost_GEN,Cost_Total,Solve_Time,CONF,Diagnostics, ...
    u_GFM_Module,P_GFM_Dis,P_GFM_Ch,E_GFM,u_GFM_Ch,P_GFL_Curt, ...
    Cost_Curt,u_G_Start,u_G_Stop,Cost_UC,SecurityValidation);
Result.SecurityFormulation = char(Formulation);
if Formulation == "periodwise"
    Result.SafetyNetwork.OptimizationScope = 'actual_sg_state_per_period';
    Result.TimingDefinition.solve_time = [ ...
        'Wall-clock seconds from entry to ', ...
        'solve_multiple_snapshot_planning_periodwise through model ', ...
        'construction, optimization, result extraction, and time-resolved ', ...
        'security post-processing; excludes packaging and save I/O.'];
end
Result_File = save_multiple_snapshot_result(Result, paths.results_dir);
print_multiple_snapshot_summary(Result, Result_File);
end

function Row = summarize_temporal_result(Row, Result, Result_File, Stage)
%% 只读取已保存Result的成本、配置、求解和逐时安全指标。
Row.Is_Feasible = logical(Result.Diagnostics.has_incumbent);
Row.Final_Stage = Stage;
Row.Final_Result_File = string(Result_File);
Row.Solver_Problem = Result.Diagnostics.problem;
Row.Solver_Info = string(Result.Diagnostics.info);
Row.Final_MIP_Gap = Result.Diagnostics.mip_gap;
Row.Total_Annual_Cost = Result.Cost.Total;
Row.GFM_ES_Fixed_Cost = Result.Cost.CON;
Row.SG_Generation_Cost = Result.Cost.GEN;
Row.SG_UC_Cost = Result.Cost.UC;
Row.Wind_Curtailment_Cost = Result.Cost.Curt;
Row.GFM_Module_Configuration = string(mat2str(round(Result.u_GFM_Mod)));

SCC = Result.SCC_TimeResolved;
SCR = Result.SCR_TimeResolved;
SCC_Nodes = Result.SafetyNetwork.SCCTimeResolvedOriginalNodes(:);
SCR_Nodes = Result.SafetyNetwork.SCRTimeResolvedOriginalNodes(:);
Expected_SCC_Size = [Result.CONF.PeriodCount, ...
    Result.CONF.TypicalDayCount, numel(SCC_Nodes)];
Expected_SCR_Size = [Result.CONF.PeriodCount, ...
    Result.CONF.TypicalDayCount, numel(SCR_Nodes)];
if ~isequal([size(SCC,1), size(SCC,2), size(SCC,3)], ...
        Expected_SCC_Size) || ...
        ~isequal([size(SCR,1), size(SCR,2), size(SCR,3)], ...
        Expected_SCR_Size) || ...
        any(~isfinite(SCC(:))) || any(~isfinite(SCR(:)))
    error('TemporalScalability:InvalidSecurityPosthoc', ...
        'A feasible result lacks finite time-resolved SCC/SCR arrays.');
end
Row.Maximum_SCC_TimeResolved_kA = max(SCC(:));
Row.Minimum_SCR_TimeResolved = min(SCR(:));
SCC_Tolerance = max(1e-6, abs(Result.CONF.ERR_TOL)* ...
    Result.CONF.Base_kA);
SCR_Tolerance = max(1e-6, abs(Result.CONF.ERR_TOL));
SCC_Limits = reshape(Result.CONF.I_limit_kA_Node(SCC_Nodes), 1, 1, []);
SCC_Passed = all(SCC <= SCC_Limits + SCC_Tolerance, 'all');
SCR_Passed = all(SCR >= Result.CONF.SCR_min - SCR_Tolerance, 'all');
Row.Security_Validation_Passed = SCC_Passed && SCR_Passed;

if Row.Formulation == "aggregated"
    Row.Maximum_SCC_Aggregated_Bound_kA = ...
        max(Result.SCC_1(SCC_Nodes,:), [], 'all');
    Row.Minimum_SCR_Aggregated_Bound = ...
        min(Result.SCR(SCR_Nodes,:), [], 'all');
    Row.AG_Aggregated_Conservatism_Passed = ...
        logical(Result.SecurityValidation.Passed);
else
    Regression = Result.Diagnostics.SecurityPosthocRegression;
    Row.PW_SCC_Posthoc_MaxAbsDifference_kA = ...
        Regression.SCC_MaxAbsDifference_kA;
    Row.PW_SCR_Posthoc_MaxAbsDifference = ...
        Regression.SCR_MaxAbsDifference;
    Row.Security_Validation_Passed = ...
        Row.Security_Validation_Passed && ...
        isfinite(Row.PW_SCC_Posthoc_MaxAbsDifference_kA) && ...
        isfinite(Row.PW_SCR_Posthoc_MaxAbsDifference) && ...
        Row.PW_SCC_Posthoc_MaxAbsDifference_kA <= SCC_Tolerance && ...
        Row.PW_SCR_Posthoc_MaxAbsDifference <= SCR_Tolerance;
end
end

function Row = initialize_temporal_row( ...
    T, Period_Duration_Hours, Formulation, T_Directory, ...
    Parameter_File, Input_File, Baseline_Params)
Row = empty_temporal_summary();
Row.ModelVersion = string(Baseline_Params.ModelVersion);
Row.WindScenarioCount = Baseline_Params.Multiple_Snapshot.Wind_Scenarios.Count;
Row.Period_Count = T;
Row.Period_Duration_Hours = Period_Duration_Hours;
Row.Formulation = Formulation;
Row.Solver_Backend = "gurobi";
Row.Target_MIP_Gap = Baseline_Params.Solver.Two_Stage.Stage_2.MIP_Gap;
Row.TimeLimit_Multiplier = 1;
Row.T_Directory = string(T_Directory);
Row.Parameter_File = string(Parameter_File);
Row.Input_Data_File = string(Input_File);
end

function Row = empty_temporal_summary()
%% 标量字段支持每个(T,formulation)一行MAT/CSV结果。
Row = struct();
Row.ModelVersion = "";
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
Row.GFM_Module_Configuration = "";
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
