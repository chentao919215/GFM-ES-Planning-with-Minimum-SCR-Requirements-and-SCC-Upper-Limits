function Row = solve_joint_sensitivity_point(Row, Scan, Options)
%% 准备并处理一个扫描点，按需复用续算记录或执行两阶段求解。
% Row为当前网格中新建的记录；重试时仅复用缓存中的合法第一阶段结果。

%% 1. 构造当前点参数并通过原有算例准备流程换算单位
Params = Scan.Params;
Params.Security.I_limit_kA = Row.I_limit_kA;
Params.Security.SCR_min = Row.CSCR;
Label = ['SCC_', number_token(Row.I_limit_kA), '_kA_CSCR_', number_token(Row.CSCR)];
Point_Directory = fullfile(Scan.Run_Directory, Label);
ensure_directory(Point_Directory);
Parameter_File = fullfile(Point_Directory, [Label, '_parameters.json']);
if isfile(Parameter_File)
    assert(isequaln(jsondecode(fileread(Parameter_File)), Params), ...
        'JointScan:InputChanged', '扫描点输入与已保存参数不一致：%s', Parameter_File);
else
    write_json_file(Parameter_File, Params);
end
[mpc, CONF] = prepare_multiple_snapshot_case(Parameter_File);
assert(isequaln(mpc, Scan.mpc), 'JointScan:NetworkChanged', '扫描点网络与基准不一致。');
validate_joint_scan_configuration(CONF, Scan.CONF, Row.I_limit_kA, Row.CSCR);
Solver_Name = CONF.solver.name;
Row.Target_MIP_Gap = CONF.Solver.Two_Stage.Stage_2.Options.(Solver_Name).MIPGap;
Row.Parameter_File = string(Parameter_File);
Row.Point_File = string(fullfile(Point_Directory, [Label, '_point.mat']));

Point.CONF = CONF;
Point.mpc = mpc;
% 参数JSON和运行清单各有独立文件，续算记录仅保存引用与校验值。
Point.Parameter_SHA256 = calculate_joint_scan_file_hash(Parameter_File);
Point.Manifest_File = Scan.Manifest_File;
Point.Manifest_SHA256 = Scan.Manifest_SHA256;
Point.Directory = Point_Directory;
Point.Label = Label;

%% 2. 核验续算记录并判断是否需要求解
[Cached, Row.Resume_Note] = read_checkpoint(Row, Point);
if ~isempty(Cached)
    Cached_Row = Cached.Row;
    Cached_Row.SCR_Row = Row.SCR_Row;
    Cached_Row.SCC_Column = Row.SCC_Column;
    Cached_Row.Resume_Note = Row.Resume_Note;
    Skip = Cached_Row.Completed && (Cached_Row.Status == "target_met" || ...
        Cached_Row.Status == "proven_infeasible" || ...
        (~Options.Retry_Unfinished && Cached_Row.Status == "feasible_target_not_met"));
    if ~Options.Execute || Skip
        Row = Cached_Row;
        return;
    end
elseif ~Options.Execute
    return;
end

%% 3. 使用当前新记录执行求解，缓存只提供可复用的第一阶段结果
Row = execute_point(Row, Point, Cached);
end

function Row = execute_point(Row, Point, Cached)
%% 执行单个扫描点的两阶段求解，并保存过程记录与最终状态。
Clock = tic;
Attempt = tempname(Point.Directory);
ensure_directory(Attempt);
Row.Attempt_Directory = string(Attempt);
Row.Error_Identifier = "";
Row.Error_Message = "";
Row.Status = "running";
Row.Completed = false;
Stage = 1;
Stage_1_Result = [];
try
    % 重试中断或未完成的第二阶段时，复用已通过校验的第一阶段结果。
    if ~isempty(Cached) && ~isempty(Cached.Stage_1_Result) && ...
            Cached.Stage_1_Result.Diagnostics.has_incumbent && ...
            classify_status(Cached.Stage_1_Result.Diagnostics, Row.Target_MIP_Gap) ~= "solver_or_model_error"
        Stage_1_Result = Cached.Stage_1_Result;
        Row.Stage_1_Result_File = Cached.Row.Stage_1_Result_File;
        Row.Stage_1_Solve_Time_s = Stage_1_Result.Diagnostics.walltime;
    end
    if isempty(Stage_1_Result)
        [Stage_1_Result, Result_File] = run_stage(Point, 1, Attempt, [], "");
        Row.Stage_1_Result_File = string(Result_File);
        Row.Stage_1_Solve_Time_s = Stage_1_Result.Diagnostics.walltime;
        validate_joint_sensitivity_result(Stage_1_Result, Point.CONF, 1);
    end
    Row.Stage_1_Status = classify_status(Stage_1_Result.Diagnostics, Row.Target_MIP_Gap);
    if Stage_1_Result.Diagnostics.has_incumbent
        Row = summarize_result(Row, Stage_1_Result, Row.Stage_1_Result_File, "stage_1", Point.CONF);
        Row.Status = "running";
        save_checkpoint(Row, Point);
        if Row.Stage_1_Status == "solver_or_model_error"
            Row.Status = "solver_or_model_error";
        elseif Row.Final_MIP_Gap <= Row.Target_MIP_Gap
            Row.Status = "target_met";
        else
            Stage = 2;
            [Stage_2_Result, Result_File] = run_stage(Point, 2, Attempt, Stage_1_Result, ...
                Row.Stage_1_Result_File);
            Row.Stage_2_Result_File = string(Result_File);
            Row.Stage_2_Solve_Time_s = Stage_2_Result.Diagnostics.walltime;
            validate_joint_sensitivity_result(Stage_2_Result, Point.CONF, 2);
            Row.Stage_2_Status = classify_status(Stage_2_Result.Diagnostics, Row.Target_MIP_Gap);
            if Stage_2_Result.Diagnostics.has_incumbent
                Row = summarize_result(Row, Stage_2_Result, Result_File, "stage_2", Point.CONF);
                Row.Status = Row.Stage_2_Status;
            elseif Row.Stage_2_Status == "proven_infeasible"
                error('JointScan:ContradictoryStages', ...
                    '第一阶段已有可行解，但第二阶段报告不可行，两个阶段结果矛盾。');
            elseif Row.Stage_2_Status == "solver_or_model_error"
                Row.Status = "solver_or_model_error";
            else
                % 保留第一阶段实际得到的可行解及其对应间隙。
                Row.Status = "feasible_target_not_met";
            end
        end
    else
        Row.Status = Row.Stage_1_Status;
        Row.Solver_Problem = Stage_1_Result.Diagnostics.problem;
        Row.Solver_Status = string(Stage_1_Result.Diagnostics.solver_status);
        Row.Solver_Info = string(Stage_1_Result.Diagnostics.info);
        Row.Final_Result_File = Row.Stage_1_Result_File;
        Row.Final_Stage = "stage_1";
    end
catch ME
    Row.Status = "solver_or_model_error";
    Row.Error_Identifier = string(ME.identifier);
    Row.Error_Message = string(ME.message);
    if Stage == 1
        Row.Stage_1_Status = "solver_or_model_error";
    else
        Row.Stage_2_Status = "solver_or_model_error";
    end
    fprintf(2, '扫描点%s求解失败：%s\n', Point.Label, ME.message);
end
Row.Runtime_s = toc(Clock);
Times = [Row.Stage_1_Solve_Time_s, Row.Stage_2_Solve_Time_s];
Row.Total_Solve_Time_s = sum(Times, 'omitnan');
Row.Completed = true;
Record = save_checkpoint(Row, Point);
% 保留本次尝试的小型历史记录；参数、来源清单与阶段结果均不嵌入副本。
save_joint_scan_data(fullfile(Attempt, [Point.Label, '_record.mat']), ...
    struct('Record', Record));
end

function [Result, Result_File] = run_stage(Point, Stage, Attempt, Stage_1_Result, Stage_1_File)
%% 配置当前阶段的求解选项与热启动，保存并重命名阶段结果。
if Stage == 1
    Config = Point.CONF.Solver.Two_Stage.Stage_1;
else
    Config = Point.CONF.Solver.Two_Stage.Stage_2;
end
Stage_CONF = apply_multiple_snapshot_solver_stage(Point.CONF, Config);
Directory = fullfile(Attempt, sprintf('stage_%d', Stage));
ensure_directory(Directory);
% 仅调整日志保存位置，数值求解设置沿用已配置的阶段选项。
Stage_CONF.solver.options.gurobi.LogFile = fullfile(Directory, [Point.Label, '.log']);
if Stage == 2
    Stage_CONF.MIPStart = ...
        build_multiple_snapshot_mip_start_from_result(Stage_1_Result, Stage_CONF);
    Stage_CONF.MIPStart.Source_File = char(Stage_1_File);
end
[Result, Original_File] = solve_one_stage(Point.mpc, Stage_CONF, ...
    Directory, true);
Result_File = fullfile(Directory, sprintf('%s_stage_%d.mat', Point.Label, Stage));
movefile(Original_File, Result_File);
end

function Status = classify_status(Diagnostics, Target_MIP_Gap)
%% 根据可行解、目标间隙与求解器状态确定扫描点状态。
Solver_Status = upper(string(Diagnostics.solver_status));
if Diagnostics.has_incumbent
    if isfinite(Diagnostics.mip_gap) && Diagnostics.mip_gap <= Target_MIP_Gap
        Status = "target_met";
    else
        Status = "feasible_target_not_met";
    end
elseif Solver_Status == "INFEASIBLE" || (Diagnostics.problem == 1 && Solver_Status ~= "INF_OR_UNBD")
    Status = "proven_infeasible";
elseif any(Solver_Status == ["TIME_LIMIT", "NODE_LIMIT", "ITERATION_LIMIT", "SOLUTION_LIMIT", ...
        "WORK_LIMIT", "MEM_LIMIT", "INTERRUPTED", "USER_OBJ_LIMIT"]) || Diagnostics.problem == 3
    Status = "stopped_no_incumbent";
elseif Solver_Status == "INF_OR_UNBD" || Diagnostics.problem == 12 || Diagnostics.problem == 0
    Status = "no_incumbent_unknown";
else
    Status = "solver_or_model_error";
end
% 即使已有可行解，也须保留数值、模型或许可证错误状态。
Known_Statuses = ["OPTIMAL", "INFEASIBLE", "INF_OR_UNBD", "TIME_LIMIT", "NODE_LIMIT", ...
    "ITERATION_LIMIT", "SOLUTION_LIMIT", "WORK_LIMIT", "MEM_LIMIT", ...
    "INTERRUPTED", "USER_OBJ_LIMIT", "SUBOPTIMAL"];
if any(Solver_Status == ["NUMERIC", "UNBOUNDED"]) || ...
        (~any(Diagnostics.problem == [0, 1, 3, 12, 16]) && ~any(Solver_Status == Known_Statuses))
    Status = "solver_or_model_error";
end
end

function Row = summarize_result(Row, Result, Result_File, Stage_Name, CONF)
%% 从已校验结果提取成本、GFM-ES配置与求解诊断。
[~, Candidate_Index] = ismember(CONF.GFM_Unit_Bus, CONF.GFM_Candidate_Buses);
Unit_Index = sub2ind(size(Result.u_GFM_Unit), Candidate_Index(:), CONF.GFM_Unit_Order(:));
Built_Units = round(Result.u_GFM_Unit(Unit_Index));
Units_Per_Bus = CONF.GFM_Candidate_Unit_Mat*Built_Units;
Row.Is_Feasible = true;
Row.Result_Validation_Passed = true;
Row.Final_Result_File = string(Result_File);
Row.Final_Stage = Stage_Name;
Row.Solver_Problem = Result.Diagnostics.problem;
Row.Solver_Status = string(Result.Diagnostics.solver_status);
Row.Solver_Info = string(Result.Diagnostics.info);
Row.Final_MIP_Gap = Result.Diagnostics.mip_gap;
Row.Objective_Best_Bound = Result.Diagnostics.best_bound;
Row.Total_Annual_Cost = Result.Cost.Total;
Row.GFM_ES_Fixed_Cost = Result.Cost.GFM_Fixed;
Row.SG_Generation_Cost = Result.Cost.GEN;
Row.SG_UC_Cost = Result.Cost.UC;
Row.Wind_Curtailment_Cost = Result.Cost.Curt;
Row.Cost_Sum_Residual = Result.Cost.Total-sum([Result.Cost.GFM_Fixed, Result.Cost.GEN, Result.Cost.UC, ...
    Result.Cost.Curt]);
Row.GFM_Unit_Count = sum(Built_Units);
Row.GFM_Power_MW = sum(Built_Units.*CONF.GFM_Unit_PN_MW(:));
Row.GFM_Energy_MWh = sum(Built_Units.*CONF.GFM_Unit_Energy_MWh(:));
Row.GFM_Installed_Buses = string(mat2str(CONF.GFM_Candidate_Buses(Units_Per_Bus>0)));
Row.GFM_Candidate_Buses = string(mat2str(CONF.GFM_Candidate_Buses(:).'));
Row.GFM_Units_Per_Bus = string(mat2str(Units_Per_Bus(:).'));
Row.GFM_Configuration = string(mat2str(Built_Units(:).'));
end

function [Cached, Reason] = read_checkpoint(Row, Point)
%% 读取续算记录，每个阶段文件只加载并校验一次。
CONF = Point.CONF;
Cached = [];
Reason = "无续算记录";
if ~isfile(Row.Point_File)
    return;
end
try
    Data = load(Row.Point_File, 'Record');
    Record = Data.Record;
    assert(isfield(Record, 'Schema_Version') && Record.Schema_Version == 2 && ...
        strcmp(Record.Parameter_SHA256, Point.Parameter_SHA256) && ...
        strcmp(Record.Manifest_File, Point.Manifest_File) && ...
        strcmp(Record.Manifest_SHA256, Point.Manifest_SHA256), ...
        'JointScan:CheckpointInputMismatch', '续算记录的参数或来源与当前扫描不一致。');
    assert(Record.Row.I_limit_kA == Row.I_limit_kA && Record.Row.CSCR == Row.CSCR);
    Stage_1_Result = [];
    Stage_2_Result = [];
    for Stage = 1:2
        Result_File = Record.Row.(sprintf('Stage_%d_Result_File', Stage));
        if strlength(Result_File) == 0
            continue;
        end
        assert(strcmp(calculate_joint_scan_file_hash(Result_File), Record.Stage_Result_SHA256(Stage)), ...
            'JointScan:ChangedResult', '已保存的阶段结果文件发生变化。');
        Data = load(Result_File, 'Result');
        validate_joint_sensitivity_result(Data.Result, CONF, Stage);
        if Stage == 1
            Stage_1_Result = Data.Result;
        else
            Stage_2_Result = Data.Result;
        end
    end
    assert(~isempty(Stage_1_Result), 'JointScan:MissingStage1', '缺少第一阶段结果文件。');
    if Record.Row.Is_Feasible
        if Record.Row.Final_Stage == "stage_1"
            Expected_File = Record.Row.Stage_1_Result_File;
        else
            Expected_File = Record.Row.Stage_2_Result_File;
        end
        assert(strlength(Expected_File)>0 && Record.Row.Final_Result_File == Expected_File, ...
            'JointScan:FinalArtifactMismatch', '最终结果文件与其记录的阶段不一致。');
        assert(any(Record.Row.Final_Stage == ["stage_1", "stage_2"]), ...
            'JointScan:FinalArtifactMismatch', '最终结果对应的阶段不符合要求。');
        if Record.Row.Final_Stage == "stage_1"
            Final_Result = Stage_1_Result;
        else
            Final_Result = Stage_2_Result;
        end
        Fresh = summarize_result(Row, Final_Result, Record.Row.Final_Result_File, ...
            Record.Row.Final_Stage, CONF);
        Fields = {'Total_Annual_Cost', 'GFM_Unit_Count', 'GFM_Configuration', ...
            'Final_MIP_Gap', 'GFM_Power_MW', 'GFM_Energy_MWh'};
        for f = Fields
            assert(isequaln(Fresh.(f{1}), Record.Row.(f{1})), ...
                'JointScan:CheckpointSummaryMismatch', '续算记录中的汇总值与阶段结果不一致。');
        end
    end
    if Record.Row.Status == "target_met"
        assert(Record.Row.Completed && Record.Row.Is_Feasible && ...
            Record.Row.Final_MIP_Gap <= Row.Target_MIP_Gap);
    elseif Record.Row.Status == "proven_infeasible"
        assert(Record.Row.Completed && ~Record.Row.Is_Feasible && ...
            classify_status(Stage_1_Result.Diagnostics, Row.Target_MIP_Gap) == "proven_infeasible");
    end
    Cached = struct('Row', Record.Row, ...
        'Stage_1_Result', Stage_1_Result, 'Stage_2_Result', Stage_2_Result);
    Reason = "续算记录已通过校验";
catch ME
    Reason = "续算记录未通过校验：" + string(ME.message);
    fprintf(2, '%s\n', Reason);
end
end

function Record = save_checkpoint(Row, Point)
%% 保存扫描点状态和文件校验值，公共输入不重复嵌入MAT。
% Parameter_SHA256对应Row.Parameter_File；运行清单集中存于Manifest_File。
Record = struct('Schema_Version', 2, 'Row', Row, ...
    'Parameter_SHA256', Point.Parameter_SHA256, ...
    'Manifest_File', Point.Manifest_File, 'Manifest_SHA256', Point.Manifest_SHA256);
Record.Stage_Result_SHA256 = strings(1, 2);
for Stage = 1:2
    File = Row.(sprintf('Stage_%d_Result_File', Stage));
    if strlength(File)>0 && isfile(File)
        Record.Stage_Result_SHA256(Stage) = string(calculate_joint_scan_file_hash(File));
    end
end
save_joint_scan_data(char(Row.Point_File), struct('Record', Record));
end

function Token = number_token(Number)
%% 使用可还原数值的JSON十进制表示生成文件名标记，避免取一位小数时重名。
Token = strrep(strrep(jsonencode(Number), '.', 'p'), '-', 'm');
end
