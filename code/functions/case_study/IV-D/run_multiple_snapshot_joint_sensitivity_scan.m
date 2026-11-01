function [Summary_Table, Summary_File, Joint] = ...
    run_multiple_snapshot_joint_sensitivity_scan(Project_Root, I_Values, SCR_Values, Options)
%% 编排Case 5的SCC-SCR联合扫描，复用现有规划模型与阶段求解函数。
% Execute=false时仅准备和核验输入、导出网格，不启动规划求解。
% 结果矩阵的行对应SCR_Values，列对应I_Values，均保留输入顺序。

%% 1. 整理扫描选项与网格
if nargin < 4
    Options = struct();
end
if ~isfield(Options, 'Execute')
    Options.Execute = false;
end
if ~isfield(Options, 'Retry_Unfinished')
    Options.Retry_Unfinished = true;
end
if ~isfield(Options, 'Run_Directory')
    Options.Run_Directory = fullfile(Project_Root, 'results', ...
        'multiple_snapshot_scc_scr_joint_sensitivity');
end
validateattributes(Options.Execute, {'logical'}, {'scalar'});
validateattributes(Options.Retry_Unfinished, {'logical'}, {'scalar'});
validateattributes(I_Values, {'numeric'}, {'vector', 'nonempty', 'real', 'finite', 'positive'});
validateattributes(SCR_Values, {'numeric'}, {'vector', 'nonempty', 'real', 'finite', 'positive'});
I_Values = I_Values(:).';
SCR_Values = SCR_Values(:);
assert(numel(unique(I_Values)) == numel(I_Values) && ...
    numel(unique(SCR_Values)) == numel(SCR_Values), 'JointScan:DuplicateGrid', ...
    'SCC上限与SCR下限的扫描取值均不能重复。');
assert(any(abs(I_Values-5.6)<1e-12) && any(abs(SCR_Values-2.8)<1e-12), ...
    'JointScan:MissingBaseline', '扫描网格须包含基准组合(5.6 kA, 2.8)。');

%% 2. 准备固定基准与网格记录
[Scan, Rows] = prepare_joint_sensitivity_scan( ...
    Project_Root, I_Values, SCR_Values, Options.Run_Directory);
Summary_File = Scan.Summary_File;

%% 3. 依次处理扫描点并更新全部汇总文件
for SCC_Column = 1:numel(I_Values)
    for SCR_Row = 1:numel(SCR_Values)
        Index = sub2ind([numel(SCR_Values), numel(I_Values)], SCR_Row, SCC_Column);
        Rows(Index) = solve_joint_sensitivity_point(Rows(Index), Scan, Options);
        [Summary_Table, Joint] = export_joint_sensitivity_summary( ...
            Rows, I_Values, SCR_Values, Scan, Options.Execute);
    end
end

%% 4. 输出扫描规模与汇总文件位置
fprintf('联合扫描组合数：%d，执行求解开关Execute=%d。\n汇总文件：%s\n', ...
    numel(Rows), Options.Execute, Summary_File);
end
