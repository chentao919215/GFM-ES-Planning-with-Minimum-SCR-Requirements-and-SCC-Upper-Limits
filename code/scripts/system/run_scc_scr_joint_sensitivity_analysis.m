%% Manuscript第IV-D节：Case 5的SCC-SCR联合灵敏度分析
% 本脚本负责设置扫描网格、编排逐点求解和发送完成通知。
Enable_Completion_Notification = false; % 自行配置mailTome后可启用。

%% 1. 生成默认参数文件

% 定义项目根目录，用于定位参数文件。
Script_Directory = fileparts(mfilename('fullpath'));
Project_Root = fileparts(fileparts(fileparts(Script_Directory)));
% 生成最新参数文件。
run(fullfile(Project_Root, 'data', 'params', ...
    'generate_multiple_snapshot_default_params.m'));

%% 2. 设置扫描范围与续算选项
% 修改以下两个数组可调整扫描网格，须保留基准组合(5.6 kA, 2.8)。
I_Limit_Values_kA = 5.5:0.1:6.0;
CSCR_Values = [2.3, 2.6, 2.7, 2.8, 2.9, 3.0];
% true执行规划求解，false仅准备和核验输入、导出扫描网格。
Execute_Full_Scan = true;
% 复用相同目录可续算；修改输入或代码后，应使用新的输出目录。
Run_Directory = fullfile(Project_Root, 'results', ...
    'multiple_snapshot_scc_scr_joint_sensitivity');
% 默认重试有可行解但未达到目标间隙、无可行解及报错的扫描点。
% false允许复用已完成且通过校验、但尚未达到目标间隙的可行结果。
Retry_Unfinished = true;

%% 3. 执行扫描并保存汇总
[Summary_Table, Summary_File, Joint_Summary] = ...
    run_multiple_snapshot_joint_sensitivity_scan(Project_Root, ...
    I_Limit_Values_kA, CSCR_Values, struct( ...
    'Execute', Execute_Full_Scan, 'Run_Directory', Run_Directory, ...
    'Retry_Unfinished', Retry_Unfinished));

%% 4. 发送完成通知
Mail_Content = sprintf('联合灵敏度分析完成时间：%s。\n', ...
    char(datetime('now')));
if Enable_Completion_Notification
    mailTome('联合灵敏度分析完成', Mail_Content);
end
