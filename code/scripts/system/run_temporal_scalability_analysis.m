%% Manuscript第IV-C节：计算性能与时间尺度分析
% 本脚本负责设置时间尺度，并编排聚合模型与逐时模型的对比求解。
% 物理参数取当前默认JSON；修改参数源脚本后，应先重新生成该JSON。
Enable_Completion_Notification = false; % 自行配置mailTome后可启用。

%% 1. 生成默认参数文件

% 定义项目根目录，用于定位参数文件。
Script_Directory = fileparts(mfilename('fullpath'));
Project_Root = fileparts(fileparts(fileparts(Script_Directory)));
% 生成最新参数文件。
run(fullfile(Project_Root, 'data', 'params', ...
    'generate_multiple_snapshot_default_params.m'));

%% 2. 设置对比时间尺度与固定时序输入
% 两种模型均采用Manuscript方程与原始四场景，在同一24 h范围内比较。
Period_Counts = [3, 6, 12, 24];
Wind_Source_File = fullfile(Project_Root, 'data', 'RTS-GMLC', ...
    'processed', 'rts_gmlc_profiles.mat');

%% 3. 执行两阶段对比求解并保存汇总
[Summary_Table, Summary_File] = ...
    run_multiple_snapshot_temporal_scalability_scan( ...
    Project_Root, Period_Counts, Wind_Source_File);

%% 4. 发送完成通知
Mail_Content = sprintf('时间尺度分析完成时间：%s。\n', ...
    char(datetime('now')));
if Enable_Completion_Notification
    mailTome('时间尺度分析完成', Mail_Content);
end
