function Report = run_gfm_vi_port_plot(Options)
%% 读取当前数值验证归档并重新绘图，不启动Simulink。
if nargin < 1
    Options = struct();
end
Script_Directory = fileparts(mfilename('fullpath'));
Code_Directory = fileparts(fileparts(fileparts(fileparts(Script_Directory))));
addpath(fullfile(Code_Directory, 'functions', 'utils'));
Project_Root = find_project_root(Script_Directory);
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
Options = figure_options(Options, struct('Result_File', ...
    fullfile(Project_Root, 'results', 'equipment', 'GFM', ...
    'GFM_VI_Port_Characteristic_Validation_Result.mat'), ...
    'Output_Directory', fullfile(Project_Root, 'figs', 'equipment', 'GFM')));
Style = figure_style('review');
Style.Visible = Options.Visible;
Loaded = load(Options.Result_File, 'ValidationResult');
Figure_File = fullfile(Options.Output_Directory, 'GFM_VI_Port_Characteristic_Validation.fig');
fig = plot_gfm_vi_port_validation(Loaded.ValidationResult, Figure_File, Style);
if Options.Close_After_Save
    close(fig);
end
Report = struct('Result_File', Options.Result_File, 'Figure_File', Figure_File);
end
