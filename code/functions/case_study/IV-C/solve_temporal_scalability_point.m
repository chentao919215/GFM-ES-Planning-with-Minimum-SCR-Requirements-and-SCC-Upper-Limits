function Row = solve_temporal_scalability_point(Row, Input, Stage_Settings)
%% 完成一个时间尺度与安全约束表示组合的两阶段求解及结果核验。
% 阶段结果分别归档；最终结果的选择顺序沿用现有时间尺度分析流程。

%% 1. 初始化本次求解的阶段状态
T = Row.Period_Count;
Formulation = Row.Formulation;
fprintf('\n时间尺度T=%d（每时段%g小时），安全约束表示：%s\n', ...
    T, Row.Period_Duration_Hours, Formulation);
Formulation_Tic = tic;
Current_Stage = "setup";
Formulation_Directory = fullfile(char(Row.T_Directory), char(Formulation));
Row.Formulation_Directory = string(Formulation_Directory);

try
    Stage_1_Directory = fullfile(Formulation_Directory, 'stage_1');
    Stage_2_Directory = fullfile(Formulation_Directory, 'stage_2');
    ensure_directory(Stage_1_Directory);
    ensure_directory(Stage_2_Directory);
    % 两种表示复制同一份配置，仅切换安全约束表示。
    CONF = Input.CONF;
    CONF.SecurityFormulation = char(Formulation);
    Row.Stage_1_TimeLimit_s = Stage_Settings.Limits(1);
    Row.Stage_2_TimeLimit_s = Stage_Settings.Limits(2);
    if ~isempty(Stage_Settings.Error)
        rethrow(Stage_Settings.Error);
    end

    %% 2. 执行第一阶段，并立即保留已返回的可行结果
    Current_Stage = "stage_1";
    [Result_Stage_1, File_Stage_1] = solve_temporal_stage( ...
        Input, CONF, 'Stage_1', Stage_1_Directory);
    Row.Stage_1_Result_File = string(File_Stage_1);
    Row.Stage_1_Solve_Time_s = Result_Stage_1.Diagnostics.walltime;
    if ~Result_Stage_1.Diagnostics.has_incumbent
        error('TemporalScalability:NoStage1Incumbent', ...
            '第一阶段未返回可行解。');
    end
    % 先记录阶段与文件，使指标提取抛错时仍保留已选结果的信息。
    Row.Is_Feasible = true;
    Row.Final_Stage = "stage_1";
    Row.Final_Result_File = string(File_Stage_1);
    Row = summarize_temporal_result(Row, Result_Stage_1, File_Stage_1, "stage_1");

    %% 3. 未达到最终目标时，仅使用本组合的第一阶段结果热启动
    Solver_Name = CONF.solver.name;
    if ~(Result_Stage_1.Diagnostics.mip_gap <= ...
            CONF.Solver.Two_Stage.Stage_2.Options.(Solver_Name).MIPGap)
        Current_Stage = "stage_2";
        [Result_Stage_2, File_Stage_2] = solve_temporal_stage( ...
            Input, CONF, 'Stage_2', Stage_2_Directory, Result_Stage_1, File_Stage_1);
        Row.Stage_2_Result_File = string(File_Stage_2);
        Row.Stage_2_Solve_Time_s = Result_Stage_2.Diagnostics.walltime;
        if ~Result_Stage_2.Diagnostics.has_incumbent
            error('TemporalScalability:NoStage2Incumbent', ...
                '第二阶段未返回可行解。');
        end
        Row.Is_Feasible = true;
        Row.Final_Stage = "stage_2";
        Row.Final_Result_File = string(File_Stage_2);
        Row = summarize_temporal_result(Row, Result_Stage_2, File_Stage_2, "stage_2");
    end

    %% 4. 核验最终结果并记录目标达成状态
    if ~Row.Security_Validation_Passed
        error('TemporalScalability:SecurityValidationFailed', ...
            '最终可行解未通过独立安全核验。');
    end
    if Row.Final_MIP_Gap <= Row.Target_MIP_Gap
        Row.Status = "target_met";
    else
        Row.Status = "feasible_target_not_met";
    end
catch ME
    % 保留异常发生前已选定的结果；第二阶段未返回可行解时仍为第一阶段。
    Row.Status = Current_Stage + "_failed";
    if Row.Is_Feasible
        Row.Status = Row.Status + "_with_incumbent";
    end
    Row.Error_Identifier = string(ME.identifier);
    Row.Error_Message = string(ME.message);
    fprintf(2, '时间尺度T=%d、安全约束表示%s的求解失败：%s\n', ...
        T, Formulation, ME.message);
end

%% 5. 记录本组合总耗时与各已返回阶段的求解耗时之和
Row.Runtime_s = toc(Formulation_Tic);
Stage_Times = [Row.Stage_1_Solve_Time_s, Row.Stage_2_Solve_Time_s];
if any(isfinite(Stage_Times))
    Row.Total_Solve_Time_s = sum(Stage_Times, 'omitnan');
end
end

function [Result, Result_File] = solve_temporal_stage( ...
    Input, CONF, Stage_Field, Stage_Directory, Previous_Result, Previous_File)
%% 应用阶段配置、设置可选热启动，并调用统一阶段求解与归档函数。
Stage = CONF.Solver.Two_Stage.(Stage_Field);
Labels = struct('Stage_1', '第一', 'Stage_2', '第二');
Options = Stage.Options.(CONF.solver.name);
fprintf('%s阶段时限：%g秒，目标相对间隙：%g。\n', ...
    Labels.(Stage_Field), Options.TimeLimit, Options.MIPGap);
CONF = apply_multiple_snapshot_solver_stage(CONF, Stage);
if nargin > 4
    CONF.MIPStart = build_multiple_snapshot_mip_start_from_result(Previous_Result, CONF);
    CONF.MIPStart.Source_File = Previous_File;
end
[Result, Result_File] = solve_one_stage(Input.mpc, CONF, Stage_Directory);
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
Row.GFM_ES_Fixed_Cost = Result.Cost.GFM_Fixed;
Row.SG_Generation_Cost = Result.Cost.GEN;
Row.SG_UC_Cost = Result.Cost.UC;
Row.Wind_Curtailment_Cost = Result.Cost.Curt;
Row.GFM_Unit_Configuration = string(mat2str(round(Result.u_GFM_Unit)));

SCC = Result.SCC_TimeResolved;
SCR = Result.SCR_TimeResolved;
SCC_Nodes = Result.CONF.SCC_Constraint_Original_Nodes(:);
SCR_Nodes = Result.CONF.Safety_GFL_Original_Nodes(:);
Expected_SCC_Size = [Result.CONF.PeriodCount, ...
    Result.CONF.TypicalDayCount, numel(SCC_Nodes)];
Expected_SCR_Size = [Result.CONF.PeriodCount, ...
    Result.CONF.TypicalDayCount, numel(SCR_Nodes)];
if ~isequal([size(SCC, 1), size(SCC, 2), size(SCC, 3)], ...
        Expected_SCC_Size) || ...
        ~isequal([size(SCR, 1), size(SCR, 2), size(SCR, 3)], ...
        Expected_SCR_Size) || ...
        any(~isfinite(SCC(:))) || any(~isfinite(SCR(:)))
    error('TemporalScalability:InvalidSecurityPosthoc', ...
        '可行结果中缺少尺寸正确且数值有限的逐时SCC/SCR数组。');
end
Row.Maximum_SCC_TimeResolved_kA = max(SCC(:));
Row.Minimum_SCR_TimeResolved = min(SCR(:));
SCC_Tolerance = Result.SecurityValidation.Limits.SCC.Tolerance;
SCR_Tolerance = Result.SecurityValidation.Limits.SCR.Tolerance;
Row.Security_Validation_Passed = Result.SecurityValidation.Limits.Passed;

if Row.Formulation == "aggregated"
    Row.Maximum_SCC_Aggregated_Bound_kA = ...
        max(Result.SCC_Aggregated(SCC_Nodes, :), [], 'all');
    Row.Minimum_SCR_Aggregated_Bound = ...
        min(Result.SCR_Aggregated(SCR_Nodes, :), [], 'all');
    Row.AG_Aggregated_Conservatism_Passed = ...
        logical(Result.SecurityValidation.Conservatism.Passed);
    Row.Security_Validation_Passed = Row.Security_Validation_Passed && ...
        Row.AG_Aggregated_Conservatism_Passed;
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
