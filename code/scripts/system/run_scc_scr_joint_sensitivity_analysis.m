%% Section IV-D: Case 5 SCR-SCC joint sensitivity.
% Edit the two arrays to refine/extend the grid; retain (5.6 kA, 2.8).
% Execute_Full_Scan=true runs optimization; false only prepares inputs.
% Reuse Run_Directory to resume; use a new directory after input/code changes.
Project_Root = resolve_project_root_for_script();
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));

I_Limit_Values_kA = [5.5, 5.6, 5.7, 5.8, 5.9, 6.0];
CSCR_Values = [2.3, 2.6, 2.7, 2.8, 2.9, 3.0];
Execute_Full_Scan = true;
Run_Directory = fullfile(Project_Root, 'results', ...
    'multiple_snapshot_scc_scr_joint_sensitivity');
% By default retry feasible-above-gap, no-incumbent and error points.
% false accepts validated, completed feasible-above-gap points as checkpoints.
Retry_Unfinished = true;

[Summary_Table, Summary_File, Joint_Summary] = ...
    run_multiple_snapshot_joint_sensitivity_scan(Project_Root, ...
    I_Limit_Values_kA, CSCR_Values, struct( ...
    'Execute', Execute_Full_Scan, 'Run_Directory', Run_Directory, ...
    'Retry_Unfinished', Retry_Unfinished));
