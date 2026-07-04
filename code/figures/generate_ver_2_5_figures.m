function Report = generate_ver_2_5_figures(result_file, output_root, param_file)
%% Generate SCI-ready figures and reusable CSV exports for ver_2.5 results.
% Report = generate_ver_2_5_figures()
% Report = generate_ver_2_5_figures(result_file, output_root, param_file)
%
% The default input is the newest multiple_snapshot_planning_result_*.mat
% in results/. Figures are written to figs/ver_2_5 using English labels,
% vector PDF and 600 dpi PNG. All validation quantities are also exported.

module_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(fileparts(module_dir));

if nargin < 1 || isempty(result_file)
    result_file = find_latest_result(fullfile(project_root, 'results'));
end
if nargin < 2 || isempty(output_root)
    output_root = fullfile(project_root, 'figs', 'ver_2_5');
end
if nargin < 3 || isempty(param_file)
    param_file = fullfile(project_root, 'data', 'params', ...
        'multiple_snapshot_default_params.json');
end

validateattributes(result_file, {'char','string'}, {'scalartext'});
validateattributes(output_root, {'char','string'}, {'scalartext'});
validateattributes(param_file, {'char','string'}, {'scalartext'});
result_file = char(result_file);
output_root = char(output_root);
param_file = char(param_file);

if ~isfile(result_file)
    error('Result file does not exist: %s', result_file);
end
if ~isfile(param_file)
    error('Parameter file does not exist: %s', param_file);
end

folders = struct(...
    'planning',  fullfile(output_root, '01_planning'), ...
    'operation', fullfile(output_root, '02_operation'), ...
    'network',   fullfile(output_root, '03_network'), ...
    'security',  fullfile(output_root, '04_security'));
ensure_folders([{output_root}, struct2cell(folders).']);

loaded = load(result_file, 'Result');
if ~isfield(loaded, 'Result') || ~isstruct(loaded.Result)
    error('The MAT file must contain a Result structure: %s', result_file);
end
params = jsondecode(fileread(param_file));
Data = prepare_ver_2_5_data(loaded.Result, params, result_file, param_file);

fprintf('\nGenerating ver_2.5 SCI figures from:\n  %s\n', result_file);
PlanningReport = plot_ver_2_5_planning(Data, folders.planning);
OperationReport = plot_ver_2_5_operation(Data, folders.operation);
NetworkReport = plot_ver_2_5_network(Data, folders.network);
SecurityReport = plot_ver_2_5_security(Data, folders.security);

Validation = [PlanningReport.Validation; OperationReport.Validation; ...
    NetworkReport.Validation; SecurityReport.Validation];
writetable(Validation, fullfile(output_root, 'validation_summary.csv'));

Report = struct();
Report.Version = 'ver_2.5';
Report.GeneratedAt = datetime('now');
Report.ResultFile = result_file;
Report.ParameterFile = param_file;
Report.OutputRoot = output_root;
Report.Planning = PlanningReport;
Report.Operation = OperationReport;
Report.Network = NetworkReport;
Report.Security = SecurityReport;
Report.Validation = Validation;
save(fullfile(output_root, 'ver_2_5_figure_report.mat'), 'Report');
write_manifest(Report, Data);

fprintf('Completed. Figures and tables were written to:\n  %s\n', output_root);
end

function result_file = find_latest_result(results_dir)
files = dir(fullfile(results_dir, 'multiple_snapshot_planning_result_*.mat'));
if isempty(files)
    error('No multiple-snapshot result file was found in %s.', results_dir);
end
[~, idx] = max([files.datenum]);
result_file = fullfile(files(idx).folder, files(idx).name);
end

function ensure_folders(folders)
for k = 1:numel(folders)
    if ~isfolder(folders{k})
        mkdir(folders{k});
    end
end
end

function write_manifest(Report, Data)
path_out = fullfile(Report.OutputRoot, 'run_manifest.txt');
fid = fopen(path_out, 'w', 'n', 'UTF-8');
if fid < 0
    warning('ver2_5:ManifestWriteFailed', 'Cannot write %s.', path_out);
    return;
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Version: %s\n', Report.Version);
fprintf(fid, 'Generated: %s\n', char(Report.GeneratedAt));
fprintf(fid, 'Result file: %s\n', Report.ResultFile);
fprintf(fid, 'Parameter file: %s\n', Report.ParameterFile);
fprintf(fid, 'Case: %s\n', Data.CaseName);
fprintf(fid, 'Typical days: %d\nPeriods per day: %d\n', Data.D, Data.T);
fprintf(fid, 'Wind scenarios: %d\n', Data.K);
fprintf(fid, 'Displayed wind scenario: %s (index %d)\n', ...
    Data.SelectedScenarioName, Data.SelectedScenarioIndex);
fprintf(fid, 'Wind-scenario probabilities by typical day: %s\n', ...
    mat2str(Data.CONF.WindScenarioProbabilities));
fprintf(fid, 'Time interval hours: %s\n', mat2str(Data.PeriodHours));
fprintf(fid, ['Security states: aggregated separately within each typical day; ', ...
    'SCC uses the daily union of online synchronous generators, classic SCR ', ...
    'uses the daily intersection.\n']);
fprintf(fid, ['Topology plot: not generated because the project result and ', ...
    'parameter file contain no verified IEEE-30 bus coordinates.\n']);
fprintf(fid, 'Figure formats: vector PDF and 600 dpi PNG.\n');
fprintf(fid, 'Validation summary: %s\n', ...
    fullfile(Report.OutputRoot, 'validation_summary.csv'));
clear cleanup;
end
