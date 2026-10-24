%% IV-B SCC单因素灵敏度分析
% 保持CSCR=2.8，仅改变短路电流上限。运行本脚本才会启动规划求解。

Project_Root = resolve_project_root_for_script();
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));

I_Limit_Values_kA = [5.5, 5.6, 5.8, 5.9];
[Summary_Table, Summary_File] = run_multiple_snapshot_sensitivity_scan( ...
    Project_Root, 'scc', I_Limit_Values_kA, 2.8);
