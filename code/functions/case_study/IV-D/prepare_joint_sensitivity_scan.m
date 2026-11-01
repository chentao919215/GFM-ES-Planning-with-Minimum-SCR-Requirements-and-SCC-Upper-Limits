function [Scan, Rows] = prepare_joint_sensitivity_scan( ...
    Project_Root, I_Values, SCR_Values, Run_Directory)
%% 准备固定的Case 5基准、来源清单、归档核对及空网格记录。
% Scan集中保存本次扫描共用的输入与输出位置；Rows保留输入轴顺序。

%% 1. 创建或核验固定基准
Run_Directory = char(java.io.File(Run_Directory).getCanonicalPath());
ensure_directory(Run_Directory);
[~, Baseline_Params, mpc, CONF] = prepare_baseline(Project_Root, Run_Directory);
audit_case5_reference(Project_Root, CONF, Run_Directory);

Scan.Params = Baseline_Params;
Scan.mpc = mpc;
Scan.CONF = CONF;
Scan.Manifest_File = fullfile(Run_Directory, 'manifest.mat');
Scan.Manifest_SHA256 = calculate_joint_scan_file_hash(Scan.Manifest_File);
Scan.Case5_Audit_File = fullfile(Run_Directory, 'case5_reference_validation.mat');
Scan.Run_Directory = Run_Directory;
Scan.Summary_File = fullfile(Run_Directory, 'joint_summary.mat');

%% 2. 初始化全部网格坐标，供逐点更新和中途汇总使用
Rows = repmat(empty_row(), numel(I_Values)*numel(SCR_Values), 1);
for SCC_Column = 1:numel(I_Values)
    for SCR_Row = 1:numel(SCR_Values)
        Index = sub2ind([numel(SCR_Values), numel(I_Values)], SCR_Row, SCC_Column);
        Rows(Index).I_limit_kA = I_Values(SCC_Column);
        Rows(Index).CSCR = SCR_Values(SCR_Row);
        Rows(Index).SCR_Row = SCR_Row;
        Rows(Index).SCC_Column = SCC_Column;
    end
end
end

function [Manifest, Baseline_Params, mpc, CONF] = prepare_baseline(Project_Root, Run_Directory)
%% 创建或核验扫描来源清单，加载固定的Case 5基准。
Manifest_File = fullfile(Run_Directory, 'manifest.mat');
Sources = source_signatures(Project_Root);
if isfile(Manifest_File)
    Data = load(Manifest_File, 'Manifest');
    Manifest = Data.Manifest;
    assert(Manifest.Schema_Version == 1 && isequaln(Manifest.Sources, Sources), ...
        'JointScan:ChangedSources', ...
        '源代码或输入与本次扫描记录不一致，请使用新的Run_Directory。');
    assert(strcmp(calculate_joint_scan_file_hash(Manifest.Baseline_File), Manifest.Baseline_SHA256), ...
        'JointScan:ChangedBaseline', '固定的Case 5基准输入已发生变化。');
else
    Baseline_File = fullfile(Run_Directory, 'case5_baseline_parameters.json');
    generate_case5(Project_Root, Baseline_File);
    Manifest = struct('Schema_Version', 1, 'Sources', Sources, ...
        'Baseline_File', Baseline_File, 'Baseline_SHA256', calculate_joint_scan_file_hash(Baseline_File), ...
        'Created', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    save_joint_scan_data(Manifest_File, struct('Manifest', Manifest));
end
Baseline_Params = jsondecode(fileread(Manifest.Baseline_File));
[Solver, Backend] = prepare_multiple_snapshot_solver_parameters(Baseline_Params);
assert(Baseline_Params.Security.Consider_Wind_Uncertainty == 1 && ...
    Baseline_Params.Security.Enable_SCC && Baseline_Params.Security.Enable_SCR && ...
    abs(Baseline_Params.Security.I_limit_kA-5.6)<1e-12 && abs(Baseline_Params.Security.SCR_min-2.8)<1e-12 && ...
    Baseline_Params.Multiple_Snapshot.Typical_Day_Count == 4 && ...
    Baseline_Params.Multiple_Snapshot.Wind.Count == 4 && ...
    Solver.Two_Stage.Enabled && ...
    abs(Solver.Two_Stage.Stage_2.Options.(Backend.name).MIPGap-Baseline_Params.Solver.MIP_Gap)<1e-12, ...
    'JointScan:NotCase5', '扫描基准须为D=4、K=4且采用两阶段求解的随机Case 5。');
[mpc, CONF] = prepare_multiple_snapshot_case(Manifest.Baseline_File);
validate_joint_scan_configuration(CONF, CONF, 5.6, 2.8);
end

function generate_case5(Project_Root, File)
%% 生成当前默认参数，再构造并保存扫描所需的Case 5副本。
run(fullfile(Project_Root, 'data', 'params', 'generate_multiple_snapshot_default_params.m'));
Parameter_File = fullfile(Project_Root, 'data', 'params', 'multiple_snapshot_default_params.json');
Wind_Source_File = fullfile(Project_Root, 'data', 'RTS-GMLC', 'processed', ...
    'rts_gmlc_profiles.mat');
Params = build_multiple_snapshot_case5_params(Parameter_File, Wind_Source_File);
write_json_file(File, Params);
end

function Audit = audit_case5_reference(Project_Root, CONF, Run_Directory)
%% 若ManuscriptCase 5归档存在，则只读核对其输入与当前扫描基准。
Stage = (1:2).';
Available = false(2, 1);
Matched = false(2, 1);
Reference_File = strings(2, 1);
Different_Fields = strings(2, 1);
for n = 1:2
    Reference_File(n) = string(fullfile(Project_Root, 'results_for_case', ...
        'IV-B', sprintf('Case_5_Stage_%d.mat', n)));
    Available(n) = isfile(Reference_File(n));
    if ~Available(n)
        Different_Fields(n) = "reference_unavailable";
        continue;
    end
    Data = load(Reference_File(n), 'Result');
    Actual_CONF = Data.Result.CONF;
    Expected_CONF = apply_multiple_snapshot_solver_stage( ...
        CONF, CONF.Solver.Two_Stage.(sprintf('Stage_%d', n)));
    Actual_CONF.solver.options.gurobi.LogFile = '';
    Expected_CONF.solver.options.gurobi.LogFile = '';
    % 按同一结果结构核对配置，不接受旧字段或缺失字段。
    Fields = fieldnames(Expected_CONF);
    Different = strings(0, 1);
    for k = 1:numel(Fields)
        f = Fields{k};
        if ~isfield(Actual_CONF, f) || ~isfield(Expected_CONF, f) || ~isequaln(Actual_CONF.(f), ...
                Expected_CONF.(f))
            Different(end+1, 1) = string(f); %#ok<AGROW>
        end
    end
    Extra = setdiff(fieldnames(Actual_CONF), Fields);
    Different = [Different; string(Extra)];
    Matched(n) = isempty(Different);
    if ~isempty(Different)
        Different_Fields(n) = join(Different, ', ');
    end
end
Audit = table(Stage, Available, Matched, Reference_File, Different_Fields);
save_joint_scan_data(fullfile(Run_Directory, 'case5_reference_validation.mat'), struct('Audit', Audit));
writetable(Audit, fullfile(Run_Directory, 'case5_reference_validation.csv'));
assert(all(Matched(Available)), 'JointScan:Case5Mismatch', ...
    '基准与ManuscriptCase 5归档不一致，请检查case5_reference_validation.csv。');
end

function Sources = source_signatures(Project_Root)
%% 记录源代码、参数生成脚本与固定时序输入的文件校验值。
Files = dir(fullfile(Project_Root, 'code', 'functions', '**', '*.m'));
Paths = arrayfun(@(x) fullfile(x.folder, x.name), Files, 'UniformOutput', false);
Paths{end+1} = fullfile(Project_Root, 'data', 'params', 'generate_multiple_snapshot_default_params.m');
Paths{end+1} = which('case30');
% 纳入搜索路径中实际解析到的阶段求解入口，区分不同来源的运行。
Paths{end+1} = which('solve_one_stage');
Paths{end+1} = fullfile(Project_Root, 'data', 'RTS-GMLC', 'processed', ...
    'rts_gmlc_profiles.mat');
Paths = unique(Paths);
Sources = struct('Path', Paths(:), 'SHA256', repmat({''}, numel(Paths), 1));
for n = 1:numel(Paths)
    Sources(n).SHA256 = calculate_joint_scan_file_hash(Paths{n});
end
end

function Row = empty_row()
%% 定义单个扫描点的空汇总记录，供结果更新与导出使用。
Row = struct('I_limit_kA', NaN, 'CSCR', NaN, 'SCR_Row', NaN, 'SCC_Column', NaN, ...
    'Status', "pending", 'Completed', false, 'Is_Feasible', false, ...
    'Result_Validation_Passed', false, 'Target_MIP_Gap', NaN, 'Final_MIP_Gap', NaN, ...
    'Solver_Problem', NaN, 'Solver_Status', "", 'Solver_Info', "", ...
    'Total_Annual_Cost', NaN, 'Objective_Best_Bound', NaN, ...
    'GFM_ES_Fixed_Cost', NaN, 'SG_Generation_Cost', NaN, 'SG_UC_Cost', NaN, ...
    'Wind_Curtailment_Cost', NaN, 'Cost_Sum_Residual', NaN, ...
    'GFM_Unit_Count', NaN, 'GFM_Power_MW', NaN, 'GFM_Energy_MWh', NaN, ...
    'GFM_Installed_Buses', "", 'GFM_Candidate_Buses', "", ...
    'GFM_Units_Per_Bus', "", 'GFM_Configuration', "", 'Runtime_s', NaN, ...
    'Stage_1_Solve_Time_s', NaN, 'Stage_2_Solve_Time_s', NaN, 'Total_Solve_Time_s', NaN, ...
    'Stage_1_Status', "", 'Stage_2_Status', "", 'Final_Stage', "", ...
    'Parameter_File', "", 'Point_File', "", 'Stage_1_Result_File', "", ...
    'Stage_2_Result_File', "", 'Final_Result_File', "", 'Attempt_Directory', "", ...
    'Resume_Note', "", 'Error_Identifier', "", 'Error_Message', "");
end
