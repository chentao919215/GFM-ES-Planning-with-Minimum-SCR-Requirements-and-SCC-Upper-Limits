%% IV-B SCR单因素灵敏度分析
% 保持I_limit=5.6 kA，仅改变CSCR。运行本脚本才会启动规划求解。

Project_Root = resolve_project_root_for_script();
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));

CSCR_Values = [2.3, 2.6, 2.7, 2.9, 3.0];
[Summary_Table, Summary_File] = run_multiple_snapshot_sensitivity_scan( ...
    Project_Root, 'scr', CSCR_Values, 5.6);
