function [Summary_Table, Summary_File] = ...
    run_multiple_snapshot_sensitivity_scan(Project_Root, Mode, Scan_Values, Fixed_Value)
%% 按IV-B两阶段流程运行一个安全阈值的单因素扫描。
% 各点调用现有算例加载、阶段配置、求解、结果打包与保存函数。

Mode = lower(char(Mode));
if ~any(strcmp(Mode, {'scc', 'scr'}))
    error('Sensitivity:InvalidMode', 'Mode must be scc or scr.');
end
validateattributes(Scan_Values, {'numeric'}, ...
    {'vector', 'real', 'finite', 'positive'});
validateattributes(Fixed_Value, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'});

% 与run_multiple_snapshot_planning相同，先从参数源生成当前IV-B JSON。
run(fullfile(Project_Root, 'data', 'params', ...
    'generate_multiple_snapshot_default_params.m'));
Baseline_Parameter_File = fullfile(Project_Root, 'data', 'params', ...
    'multiple_snapshot_default_params.json');
Baseline_Params = jsondecode(fileread(Baseline_Parameter_File));
validate_ivb_baseline(Baseline_Params);

Run_Stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
Run_Directory = fullfile(Project_Root, 'results', ...
    ['multiple_snapshot_', Mode, '_sensitivity_', Run_Stamp]);
if isfolder(Run_Directory)
    error('Sensitivity:ExistingRun', ...
        'The timestamped output directory already exists: %s', Run_Directory);
end
ensure_directory(Run_Directory);
Summary_File = fullfile(Run_Directory, ...
    ['multiple_snapshot_', Mode, '_sensitivity_summary_', Run_Stamp, '.mat']);

Scan_Values = Scan_Values(:);
Summary = repmat(empty_summary(), numel(Scan_Values), 1);
Planning_Results = cell(numel(Scan_Values), 1);
Planning_Results_Stage_1 = cell(numel(Scan_Values), 1);
Planning_Results_Stage_2 = cell(numel(Scan_Values), 1);

for k = 1:numel(Scan_Values)
    Point_Tic = tic;
    Current_Stage = "setup";
    Row = empty_summary();
    Params = Baseline_Params;
    if strcmp(Mode, 'scc')
        Params.Security.I_limit_kA = Scan_Values(k);
        Params.Security.SCR_min = Fixed_Value;
        Point_Label = sprintf('point_%02d_I_limit_%s_kA', k, ...
            strrep(sprintf('%.1f', Scan_Values(k)), '.', 'p'));
    else
        Params.Security.I_limit_kA = Fixed_Value;
        Params.Security.SCR_min = Scan_Values(k);
        Point_Label = sprintf('point_%02d_CSCR_%s', k, ...
            strrep(sprintf('%.1f', Scan_Values(k)), '.', 'p'));
    end
    Row.I_limit_kA = Params.Security.I_limit_kA;
    Row.CSCR = Params.Security.SCR_min;
    Row.Target_MIP_Gap = Baseline_Params.Solver.Two_Stage.Stage_2.MIP_Gap;
    Point_Directory = fullfile(Run_Directory, Point_Label);
    Row.Point_Directory = string(Point_Directory);

    try
        ensure_directory(Point_Directory);
        % 每点的完整输入独立归档；基准JSON及非扫描参数保持不变。
        Parameter_File = fullfile(Point_Directory, 'sensitivity_parameters.json');
        write_parameter_file(Parameter_File, Params);
        Row.Parameter_File = string(Parameter_File);
        [mpc, CONF, paths] = load_multiple_snapshot_case( ...
            Project_Root, Parameter_File);
        paths.results_dir = Point_Directory;
        Stage_1_Directory = fullfile(Point_Directory, 'stage_1');
        Stage_2_Directory = fullfile(Point_Directory, 'stage_2');
        ensure_directory(Stage_1_Directory);
        ensure_directory(Stage_2_Directory);
        if any(abs(CONF.Security.I_limit_kA(:)-Row.I_limit_kA) > 1e-12) || ...
                abs(CONF.Security.SCR_min-Row.CSCR) > 1e-12
            error('Sensitivity:LoadedParameterMismatch', ...
                'The loaded security thresholds differ from the scan point.');
        end

        Current_Stage = "stage_1";
        CONF_Stage_1 = apply_multiple_snapshot_solver_stage( ...
            CONF, CONF.Solver.Two_Stage.Stage_1);
        Paths_Stage_1 = paths;
        Paths_Stage_1.results_dir = Stage_1_Directory;
        [Result_Stage_1, Result_File_Stage_1] = ...
            solve_one_stage(mpc, CONF_Stage_1, Paths_Stage_1);
        Row.Stage_1_Result_File = string(Result_File_Stage_1);
        Row.Stage_1_Solve_Time_s = Result_Stage_1.solve_time;
        if ~Result_Stage_1.Diagnostics.has_incumbent
            error('Sensitivity:NoStage1Incumbent', ...
                'Stage 1 returned no feasible incumbent.');
        end
        Planning_Results_Stage_1{k} = Result_Stage_1;
        Planning_Results{k} = Result_Stage_1;
        Row = summarize_planning_result(Row, Result_Stage_1, ...
            Result_File_Stage_1, "stage_1");

        % 完全复用IV-B的阶段切换条件与第一阶段整数解热启动。
        if ~(Result_Stage_1.Diagnostics.mip_gap <= ...
                CONF.Solver.Two_Stage.Stage_2.MIP_Gap)
            Current_Stage = "stage_2";
            CONF_Stage_2 = apply_multiple_snapshot_solver_stage( ...
                CONF, CONF.Solver.Two_Stage.Stage_2);
            CONF_Stage_2.Solver.MIP_Start = ...
                build_multiple_snapshot_mip_start_from_result( ...
                Result_Stage_1, CONF_Stage_2);
            CONF_Stage_2.Solver.MIP_Start.Source_File = Result_File_Stage_1;
            Paths_Stage_2 = paths;
            Paths_Stage_2.results_dir = Stage_2_Directory;
            [Result_Stage_2, Result_File_Stage_2] = ...
                solve_one_stage(mpc, CONF_Stage_2, Paths_Stage_2);
            Row.Stage_2_Result_File = string(Result_File_Stage_2);
            Row.Stage_2_Solve_Time_s = Result_Stage_2.solve_time;
            if ~Result_Stage_2.Diagnostics.has_incumbent
                error('Sensitivity:NoStage2Incumbent', ...
                    'Stage 2 returned no feasible incumbent.');
            end
            Planning_Results_Stage_2{k} = Result_Stage_2;
            Planning_Results{k} = Result_Stage_2;
            Row = summarize_planning_result(Row, Result_Stage_2, ...
                Result_File_Stage_2, "stage_2");
        end

        if Row.Final_MIP_Gap <= Row.Target_MIP_Gap
            Row.Status = "target_met";
        else
            Row.Status = "feasible_target_not_met";
        end
    catch ME
        % 保留已经保存的第一阶段可行解；单点失败不影响其余扫描点。
        Row.Status = Current_Stage + "_failed";
        if Row.Is_Feasible
            Row.Status = Row.Status + "_with_incumbent";
        end
        Row.Error_Identifier = string(ME.identifier);
        Row.Error_Message = string(ME.message);
        fprintf(2, 'Sensitivity point %s failed: %s\n', ...
            Point_Label, ME.message);
    end

    Row.Runtime_s = toc(Point_Tic);
    Stage_Times = [Row.Stage_1_Solve_Time_s, Row.Stage_2_Solve_Time_s];
    if any(isfinite(Stage_Times))
        Row.Total_Solve_Time_s = sum(Stage_Times, 'omitnan');
    end
    Summary(k) = Row;
    Summary_Table = struct2table(Summary);
    % 每点后更新检查点；各Result与标准planning result MAT同时保留。
    save(Summary_File, 'Summary', 'Summary_Table', 'Planning_Results', ...
        'Planning_Results_Stage_1', 'Planning_Results_Stage_2', ...
        'Scan_Values', 'Mode', 'Fixed_Value', 'Baseline_Parameter_File', ...
        'Run_Directory', '-v7.3');
end

fprintf('\nSensitivity summary: %s\n', Summary_File);

end

function validate_ivb_baseline(Params)
%% 防止参数源变化时静默运行不同于IV-B的算例。
if ~Params.Security.Enable_SCC || ~Params.Security.Enable_SCR || ...
        abs(Params.Security.I_limit_kA-5.6) > 1e-12 || ...
        abs(Params.Security.SCR_min-2.8) > 1e-12 || ...
        ~Params.Solver.Two_Stage.Enabled || ...
        abs(Params.Solver.MIP_Gap-0.005) > 1e-12 || ...
        abs(Params.Solver.Two_Stage.Stage_2.MIP_Gap-0.005) > 1e-12 || ...
        Params.Multiple_Snapshot.Time.Typical_Day_Count ~= 4 || ...
        Params.Multiple_Snapshot.Wind_Scenarios.Count ~= 4 || ...
        ~isequal(Params.GFM_Modules.Candidates.Bus(:).', [6 10 16]) || ...
        ~isequal(Params.GFM_Modules.Module.Bus(:).', [6 6 10 10 16 16])
    error('Sensitivity:UnexpectedIVBBaseline', ...
        'The generated parameters no longer match the IV-B baseline.');
end
end

function write_parameter_file(File_Path, Params)
%% 按现有参数搜索脚本的JSON格式写出单点输入。
fid = fopen(File_Path, 'w', 'n', 'UTF-8');
if fid < 0
    error('Sensitivity:ParameterWriteFailed', ...
        'Cannot write parameter file: %s', File_Path);
end
File_Cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', jsonencode(Params, 'PrettyPrint', true));
end

function Row = summarize_planning_result(Row, Result, Result_File, Stage)
%% 只读取现有Result字段，不重新计算模型指标。
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
Row.SG_Total_Cost = Result.Cost.GEN + Result.Cost.UC;
Row.Wind_Curtailment_Cost = Result.Cost.Curt;

% package_multiple_snapshot_result保存的是normalize_multiple_snapshot_conf
% 的内部CONF，因此候选节点从GFM_Module_Candidates读取。
Candidate_Buses = Result.CONF.GFM_Module_Candidates(:);
Module_Counts = Result.CONF.GFM_Candidate_Module_Mat * ...
    round(Result.u_GFM_Mod(:));
Row.GFM_Modules_Bus_6 = Module_Counts(Candidate_Buses == 6);
Row.GFM_Modules_Bus_10 = Module_Counts(Candidate_Buses == 10);
Row.GFM_Modules_Bus_16 = Module_Counts(Candidate_Buses == 16);
Row.GFM_Module_Configuration = string(mat2str(round(Result.u_GFM_Mod)));
if isfield(Result,'lambda_c')
    Row.GFM_Configuration_Selection = string(mat2str(round(Result.lambda_c(:).')));
else
    Row.GFM_Configuration_Selection = "direct_module_decisions";
end

SCC_Nodes = Result.SafetyNetwork.SCCConstraintOriginalNodes(:);
SCR_Nodes = Result.SafetyNetwork.SCRTimeResolvedOriginalNodes(:);
Row.Maximum_SCC_Hourly_kA = finite_extreme( ...
    Result.SCC_TimeResolved, 'max');
Row.Maximum_SCC_Aggregated_Bound_kA = finite_extreme( ...
    Result.SCC_1(SCC_Nodes, :), 'max');
Row.Minimum_SCR_Hourly = finite_extreme( ...
    Result.SCR_TimeResolved, 'min');
Row.Minimum_SCR_Aggregated_Bound = finite_extreme( ...
    Result.SCR(SCR_Nodes, :), 'min');
Row.Security_Validation_Passed = logical(Result.SecurityValidation.Passed);
end

function Value = finite_extreme(Values, Direction)
Values = Values(isfinite(Values));
if isempty(Values)
    Value = NaN;
elseif strcmp(Direction, 'max')
    Value = max(Values);
else
    Value = min(Values);
end
end

function Row = empty_summary()
%% 所有字段为标量，便于同时保存struct和论文用table。
Row = struct();
Row.I_limit_kA = NaN;
Row.CSCR = NaN;
Row.Status = "pending";
Row.Is_Feasible = false;
Row.Solver_Problem = NaN;
Row.Solver_Info = "";
Row.Total_Annual_Cost = NaN;
Row.GFM_ES_Fixed_Cost = NaN;
Row.SG_Generation_Cost = NaN;
Row.SG_UC_Cost = NaN;
Row.SG_Total_Cost = NaN;
Row.Wind_Curtailment_Cost = NaN;
Row.GFM_Modules_Bus_6 = NaN;
Row.GFM_Modules_Bus_10 = NaN;
Row.GFM_Modules_Bus_16 = NaN;
Row.GFM_Module_Configuration = "";
Row.GFM_Configuration_Selection = "";
Row.Maximum_SCC_Hourly_kA = NaN;
Row.Maximum_SCC_Aggregated_Bound_kA = NaN;
Row.Minimum_SCR_Hourly = NaN;
Row.Minimum_SCR_Aggregated_Bound = NaN;
Row.Security_Validation_Passed = false;
Row.Runtime_s = NaN;
Row.Stage_1_Solve_Time_s = NaN;
Row.Stage_2_Solve_Time_s = NaN;
Row.Total_Solve_Time_s = NaN;
Row.Target_MIP_Gap = NaN;
Row.Final_MIP_Gap = NaN;
Row.Final_Stage = "";
Row.Point_Directory = "";
Row.Parameter_File = "";
Row.Stage_1_Result_File = "";
Row.Stage_2_Result_File = "";
Row.Final_Result_File = "";
Row.Error_Identifier = "";
Row.Error_Message = "";
end
