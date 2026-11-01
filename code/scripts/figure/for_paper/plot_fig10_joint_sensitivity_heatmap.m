function Report = plot_fig10_joint_sensitivity_heatmap(Options)
%% Fig. 10：总年成本与GFM-ES配置的联合灵敏度。
% 仅读取IV-D的五个CSV归档，不修改输入文件。
if nargin < 1
    Options = struct();
end

Script_Directory = fileparts(mfilename('fullpath'));
addpath(fullfile(fileparts(fileparts(fileparts(Script_Directory))), ...
    'functions', 'utils'));
Project_Root = find_project_root(Script_Directory);
Input_Directory = fullfile(Project_Root, 'results_for_case', 'IV-D');
Output_Directory = fullfile(Project_Root, 'figs', 'for_paper');
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
Options = figure_options(Options, struct('Input_Directory', Input_Directory, 'Output_Directory', ...
    Output_Directory));
Style = figure_style('paper');
Style.Visible = Options.Visible;
Style.Close_After_Save = Options.Close_After_Save;
Input_Directory = Options.Input_Directory;
Output_Directory = Options.Output_Directory;

Cost_File = fullfile(Input_Directory, 'Cost_Matrix.csv');
Configuration_File = fullfile(Input_Directory, 'Configuration_Matrix.csv');
Unit_Count_File = fullfile(Input_Directory, 'Unit_Count_Matrix.csv');
Status_File = fullfile(Input_Directory, 'Status_Matrix.csv');
Summary_File = fullfile(Input_Directory, 'joint_summary.csv');
Input_Files = {Cost_File, Configuration_File, Unit_Count_File, ...
    Status_File, Summary_File};
for File_Index = 1:numel(Input_Files)
    if ~isfile(Input_Files{File_Index})
        error('Fig10:MissingCSV', 'Required IV-D CSV is missing: %s', ...
            Input_Files{File_Index});
    end
end

%% 1. 读取并核验全部CSV输入
Cost_Table = readtable(Cost_File, 'Delimiter', ',', 'TextType', 'string', ...
    'VariableNamingRule', 'preserve');
Configuration_Table = readtable(Configuration_File, 'Delimiter', ',', ...
    'TextType', 'string', ...
    'VariableNamingRule', 'preserve');
Unit_Count_Table = readtable(Unit_Count_File, 'Delimiter', ',', ...
    'TextType', 'string', ...
    'VariableNamingRule', 'preserve');
Status_Table = readtable(Status_File, 'Delimiter', ',', 'TextType', 'string', ...
    'VariableNamingRule', 'preserve');
Summary_Table = readtable(Summary_File, 'Delimiter', ',', 'TextType', 'string', ...
    'VariableNamingRule', 'preserve');

Expected_SCC_kA = [5.5 5.6 5.7 5.8 5.9 6.0];
Expected_CSCR = [2.3 2.6 2.7 2.8 2.9 3.0];
SCC_kA = parse_scc_headers(Cost_Table.Properties.VariableNames, Cost_File);
CSCR = Cost_Table{:, 1};
Cost_Dollars_per_Year = Cost_Table{:, 2:end};
assert_axes(CSCR, SCC_kA, Expected_CSCR, Expected_SCC_kA, Cost_File);
assert_matrix_table(Configuration_Table, CSCR, SCC_kA, Configuration_File);
assert_matrix_table(Unit_Count_Table, CSCR, SCC_kA, Unit_Count_File);
assert_matrix_table(Status_Table, CSCR, SCC_kA, Status_File);

Grid_Size = [numel(CSCR), numel(SCC_kA)];
assert(isequal(size(Cost_Dollars_per_Year), [6 6]) && ...
    all(isfinite(Cost_Dollars_per_Year), 'all') && ...
    all(Cost_Dollars_per_Year > 0, 'all'), ...
    'Fig10:InvalidCostMatrix', 'Cost_Matrix.csv must contain finite positive 6-by-6 data.');
assert(height(Summary_Table)==36, 'Fig10:IncompleteSummary', ...
    'joint_summary.csv must contain exactly 36 parameter combinations.');
Required_Summary_Fields = {'I_limit_kA', 'CSCR', 'SCR_Row', 'SCC_Column', ...
    'Status', 'Completed', 'Is_Feasible', 'Result_Validation_Passed', ...
    'Target_MIP_Gap', 'Final_MIP_Gap', 'Solver_Problem', 'Total_Annual_Cost', ...
    'GFM_Unit_Count', 'GFM_Installed_Buses', 'GFM_Candidate_Buses', ...
    'GFM_Units_Per_Bus', 'GFM_Configuration'};
assert(all(ismember(Required_Summary_Fields, ...
    Summary_Table.Properties.VariableNames)), ...
    'Fig10:MissingSummaryFields', 'joint_summary.csv is missing required columns.');
assert(all(string(Summary_Table.Status)=="target_met") && ...
    all(logical_numeric(Summary_Table.Completed, 'Completed')) && ...
    all(logical_numeric(Summary_Table.Is_Feasible, 'Is_Feasible')) && ...
    all(logical_numeric(Summary_Table.Result_Validation_Passed, ...
    'Result_Validation_Passed')) && ...
    all(Summary_Table.Solver_Problem==0) && ...
    all(isfinite(Summary_Table.Final_MIP_Gap)) && ...
    all(Summary_Table.Final_MIP_Gap<=Summary_Table.Target_MIP_Gap), ...
    'Fig10:InvalidSolveStatus', ...
    'Every point must be a completed, validated target_met result.');

Matrix_Tables = {Configuration_Table, Unit_Count_Table, Status_Table};
for Table_Index = 1:numel(Matrix_Tables)
    Row_Axis = Matrix_Tables{Table_Index}{:, 1};
    if ~isequal(Row_Axis(:), CSCR(:))
        error('Fig10:AxisOrderMismatch', ...
            'The CSCR row order does not match Cost_Matrix.csv in %s.', ...
            Input_Files{Table_Index+1});
    end
end
Status_Values = strings(Grid_Size);
for Row_Index = 1:Grid_Size(1)
    for Column_Index = 1:Grid_Size(2)
        Status_Values(Row_Index, Column_Index) = strtrim(string( ...
            Status_Table{Row_Index, Column_Index+1}));
    end
end
assert(all(Status_Values=="target_met", 'all'), 'Fig10:InvalidStatusMatrix', ...
    'Status_Matrix.csv must mark all 36 points target_met.');

% 矩阵坐标和排列顺序以输入数组为准。
Cost_MUSD_per_Year = Cost_Dollars_per_Year/1e6;
Configuration_Text = strings(Grid_Size);
Seen_Grid = false(Grid_Size);
All_Labels = strings(height(Summary_Table), 1);
for Summary_Index = 1:height(Summary_Table)
    I = Summary_Table.I_limit_kA(Summary_Index);
    SCR = Summary_Table.CSCR(Summary_Index);
    Row_Index = unique_axis_index(CSCR, SCR, Summary_File);
    Column_Index = unique_axis_index(SCC_kA, I, Summary_File);
    if Row_Index~=Summary_Table.SCR_Row(Summary_Index) || ...
            Column_Index~=Summary_Table.SCC_Column(Summary_Index)
        error('Fig10:IndexMappingMismatch', ...
            'SCR_Row/SCC_Column disagrees with the thresholds at summary row %d.', ...
            Summary_Index);
    end
    if Seen_Grid(Row_Index, Column_Index)
        error('Fig10:DuplicateCombination', ...
            'Duplicate combination (%.12g kA, CSCR %.12g).', I, SCR);
    end
    Seen_Grid(Row_Index, Column_Index) = true;
    if string(Summary_Table.Status(Summary_Index)) ~= ...
            Status_Values(Row_Index, Column_Index)
        error('Fig10:StatusMappingMismatch', ...
            'Status_Matrix.csv disagrees with joint_summary.csv at (%.12g, %.12g).', I, SCR);
    end
    Tolerance = max(1e-6, 1e-10*abs(Cost_Dollars_per_Year(Row_Index, Column_Index)));
    if abs(Cost_Dollars_per_Year(Row_Index, Column_Index)- ...
            Summary_Table.Total_Annual_Cost(Summary_Index)) > Tolerance
        error('Fig10:CostMappingMismatch', ...
            'Cost_Matrix.csv disagrees with joint_summary.csv at (%.12g, %.12g).', I, SCR);
    end

    Config_Vector = parse_integer_vector( ...
        Configuration_Table{Row_Index, Column_Index+1}, 6, Configuration_File);
    Summary_Config = parse_integer_vector( ...
        Summary_Table.GFM_Configuration(Summary_Index), 6, Summary_File);
    if ~isequal(Config_Vector, Summary_Config) || ...
            any(~ismember(Config_Vector, [0 1]))
        error('Fig10:ConfigurationMappingMismatch', ...
            'Configuration_Matrix.csv and joint_summary.csv disagree at (%.12g, %.12g).', ...
            I, SCR);
    end

    Candidate_Buses = parse_integer_vector( ...
        Summary_Table.GFM_Candidate_Buses(Summary_Index), [], Summary_File);
    Units_Per_Bus = parse_integer_vector( ...
        Summary_Table.GFM_Units_Per_Bus(Summary_Index), [], Summary_File);
    Installed_Buses = parse_bus_list( ...
        Summary_Table.GFM_Installed_Buses(Summary_Index), Summary_File);
    if isempty(Candidate_Buses) || numel(Candidate_Buses)~=numel(Units_Per_Bus) || ...
            any(Candidate_Buses<=0) || any(diff(Candidate_Buses)<=0) || ...
            any(Units_Per_Bus<0) || ...
            Summary_Table.GFM_Unit_Count(Summary_Index)~=sum(Units_Per_Bus) || ...
            ~isequal(Installed_Buses, Candidate_Buses(Units_Per_Bus>0))
        error('Fig10:InvalidUnitSummary', ...
            'Installed buses/unit counts are inconsistent at (%.12g, %.12g).', I, SCR);
    end
    Unit_Count_Cell = str2double(string( ...
        Unit_Count_Table{Row_Index, Column_Index+1}));
    if ~isfinite(Unit_Count_Cell) || ...
            Unit_Count_Cell~=Summary_Table.GFM_Unit_Count(Summary_Index)
        error('Fig10:UnitCountMappingMismatch', ...
            'Unit_Count_Matrix.csv disagrees with joint_summary.csv at (%.12g, %.12g).', ...
            I, SCR);
    end

    Configuration_Text(Row_Index, Column_Index) = make_configuration_label( ...
        Candidate_Buses, Units_Per_Bus);
    All_Labels(Summary_Index) = Configuration_Text(Row_Index, Column_Index);
end
assert(all(Seen_Grid, 'all'), 'Fig10:MissingCombination', ...
    'joint_summary.csv does not cover every matrix coordinate.');

Baseline_Column = unique_axis_index(SCC_kA, 5.6, Summary_File);
Baseline_Row = unique_axis_index(CSCR, 2.8, Summary_File);
if isempty(Baseline_Row) || isempty(Baseline_Column)
    error('Fig10:MissingBaseline', 'Baseline (5.6 kA, CSCR 2.8) is missing.');
end
Unique_Labels = unique(All_Labels, 'stable');

%% 2. 绘制等间距离散热图
if ~isfolder(Output_Directory)
    mkdir(Output_Directory);
end
Figure_Width = 3.50;
Figure_Height = 3.10;
fig = new_figure(2.54*[Figure_Width Figure_Height], Style);
Figure_Cleanup = onCleanup(@() close_if_open(fig)); %#ok<NASGU>
layout = tiledlayout(fig, 1, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
ax = nexttile(layout);
style_sci_axes(ax);
imagesc(ax, 1:numel(SCC_kA), 1:numel(CSCR), Cost_MUSD_per_Year);
set(ax, 'YDir', 'normal', 'XLim', [0.5 numel(SCC_kA)+0.5], ...
    'YLim', [0.5 numel(CSCR)+0.5], 'XTick', 1:numel(SCC_kA), ...
    'YTick', 1:numel(CSCR), 'XTickLabel', compose('%.1f', SCC_kA), ...
    'YTickLabel', compose('%.1f', CSCR), 'TickLength', [0 0], ...
    'FontName', 'Times New Roman', 'FontSize', 7.1, 'Layer', 'top');
grid(ax, 'off');
Color_Map = Style.Sequential_Map;
colormap(ax, Color_Map);
Color_Limits = [min(Cost_MUSD_per_Year, [], 'all'), ...
    max(Cost_MUSD_per_Year, [], 'all')];
if Color_Limits(1)==Color_Limits(2)
    Color_Limits = Color_Limits + [-0.5 0.5];
end
clim(ax, Color_Limits);
xlabel(ax, 'SCC upper limit (kA)', 'FontName', 'Times New Roman', 'FontSize', 8.0);
ylabel(ax, 'Minimum SCR requirement', 'FontName', 'Times New Roman', 'FontSize', 8.0);

% 用细白线分隔各离散组合，颜色不作插值。
hold(ax, 'on');
for Boundary = 0.5+(1:numel(SCC_kA)-1)
    xline(ax, Boundary, '-', 'Color', [0.97 0.97 0.97], ...
        'LineWidth', 0.55, 'HandleVisibility', 'off');
end
for Boundary = 0.5+(1:numel(CSCR)-1)
    yline(ax, Boundary, '-', 'Color', [0.97 0.97 0.97], ...
        'LineWidth', 0.55, 'HandleVisibility', 'off');
end

for Row_Index = 1:numel(CSCR)
    for Column_Index = 1:numel(SCC_kA)
        Fraction = (Cost_MUSD_per_Year(Row_Index, Column_Index)- ...
            Color_Limits(1))/diff(Color_Limits);
        Color_Index = max(1, min(size(Color_Map, 1), ...
            1+round(Fraction*(size(Color_Map, 1)-1))));
        RGB = Color_Map(Color_Index, :);
        Linear_RGB = RGB;
        Linear_Mask = RGB<=0.04045;
        Linear_RGB(Linear_Mask) = RGB(Linear_Mask)/12.92;
        Linear_RGB(~Linear_Mask) = ...
            ((RGB(~Linear_Mask)+0.055)/1.055).^2.4;
        Luminance = dot(Linear_RGB, [0.2126 0.7152 0.0722]);
        Dark_Contrast = (Luminance+0.05)/0.05;
        White_Contrast = 1.05/(Luminance+0.05);
        if Dark_Contrast>=White_Contrast
            Text_Color = [0.12 0.12 0.12];
        else
            Text_Color = [1 1 1];
        end
        Text_Weight = 'normal';
        if Row_Index==Baseline_Row && Column_Index==Baseline_Column
            Text_Weight = 'bold';
        end
        text(ax, Column_Index, Row_Index, Configuration_Text(Row_Index, Column_Index), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
            'FontName', 'Times New Roman', 'FontSize', 6.2, ...
            'FontWeight', Text_Weight, 'Color', Text_Color, ...
            'Interpreter', 'none', 'Clipping', 'on');
    end
end
rectangle(ax, 'Position', [Baseline_Column-0.5, Baseline_Row-0.5, 1, 1], ...
    'FaceColor', 'none', 'EdgeColor', Style.Colors.Highlight, ...
    'LineWidth', 1.25, 'Clipping', 'on', 'HandleVisibility', 'off');
hold(ax, 'off');
Color_Bar = colorbar(ax, 'eastoutside');
Color_Bar.Label.String = 'Total annual cost (M$/yr)';
Color_Bar.Label.FontName = 'Times New Roman';
Color_Bar.Label.FontSize = 7.5;
Color_Bar.FontName = 'Times New Roman';
Color_Bar.FontSize = 7.0;
box(ax, 'on');

Output_Base = fullfile(Output_Directory, 'Fig_10_Joint_Sensitivity_Heatmap');
save_figure_file(fig, Output_Base);
close_if_open(fig);

Fig10_Data = table(repmat(CSCR(:), numel(SCC_kA), 1), ...
    kron(SCC_kA(:), ones(numel(CSCR), 1)), Cost_MUSD_per_Year(:), ...
    Configuration_Text(:), Status_Values(:), ...
    'VariableNames', {'CSCR', 'SCCLimit_kA', 'TotalAnnualCost_MUSD_per_yr', ...
    'GFMConfiguration', 'Status'});

%% 3. 输出数据来源与配置标签映射
fprintf('Fig. 10 CSV inputs:\n');
for File_Index = 1:numel(Input_Files)
    fprintf('  %s\n', Input_Files{File_Index});
end
fprintf('Cost matrix: %d-by-%d\n', size(Cost_Dollars_per_Year, 1), ...
    size(Cost_Dollars_per_Year, 2));
fprintf('SCC axis (kA): %s\n', mat2str(SCC_kA));
fprintf('CSCR axis: %s\n', mat2str(CSCR.'));
fprintf('GFM-ES configuration labels: %s\n', ...
    strjoin(cellstr(Unique_Labels.'), ', '));
fprintf('Baseline cell (SCC=5.6 kA, CSCR=2.8): row %d, column %d\n', ...
    Baseline_Row, Baseline_Column);
fprintf('Single-column layout: %.2f x %.2f in; baseline highlighted by an orange outline.\n', ...
    Figure_Width, Figure_Height);
fprintf('Fig. 10 exported to %s.fig\n', Output_Base);

Report = struct('Data', Fig10_Data, 'Figure_File', [Output_Base '.fig']);
end

function SCC = parse_scc_headers(Variable_Names, File_Path)
%% 从CSV列名解析SCC上限，并核验其为有限数值。
if numel(Variable_Names)~=7 || ~strcmp(Variable_Names{1}, 'CSCR')
    error('Fig10:InvalidMatrixHeader', 'Unexpected 6-by-6 CSV header in %s.', File_Path);
end
SCC = zeros(1, 6);
for Column_Index = 1:6
    Tokens = regexp(Variable_Names{Column_Index+1}, ...
        '^SCC_([0-9]+(?:\.[0-9]+)?)_kA$', 'tokens', 'once');
    if isempty(Tokens)
        error('Fig10:InvalidSCCHeader', 'Cannot read SCC axis from %s.', File_Path);
    end
    SCC(Column_Index) = str2double(Tokens{1});
end
end

function assert_axes(CSCR, SCC, Expected_CSCR, Expected_SCC, File_Path)
%% 核验矩阵的SCC、SCR坐标与汇总表一致。
if ~isnumeric(CSCR) || ~isnumeric(SCC) || ...
        ~isequal(CSCR(:).', Expected_CSCR) || ~isequal(SCC(:), Expected_SCC(:))
    error('Fig10:UnexpectedAxes', ...
        'CSV axes/order in %s must match the requested six SCR and SCC values.', File_Path);
end
end

function assert_matrix_table(T, CSCR, SCC, File_Path)
%% 核验矩阵表的行列规模及坐标列。
if height(T)~=numel(CSCR) || width(T)~=numel(SCC)+1 || ...
        ~strcmp(T.Properties.VariableNames{1}, 'CSCR')
    error('Fig10:InvalidMatrixShape', 'Expected a 6-by-6 matrix CSV: %s', File_Path);
end
Columns = parse_scc_headers(T.Properties.VariableNames, File_Path);
if ~isequal(T{:, 1}, CSCR) || ~isequal(Columns(:), SCC(:))
    error('Fig10:AxisOrderMismatch', 'Matrix axes/order mismatch in %s.', File_Path);
end
end

function Index = unique_axis_index(Axis, Value, File_Path)
%% 在给定容差内定位唯一的坐标索引。
Matches = find(abs(Axis-Value)<=1e-10);
if numel(Matches)~=1
    error('Fig10:MissingOrDuplicateAxisValue', ...
        'Parameter %.12g has %d matches in %s.', Value, numel(Matches), File_Path);
end
Index = Matches;
end

function Vector = parse_integer_vector(Value, Expected_Length, File_Path)
%% 将归档文本解析为指定长度的整数向量。
Text = strtrim(char(string(Value)));
if numel(Text)<2 || Text(1)~='[' || Text(end)~=']'
    error('Fig10:InvalidVector', 'Expected a bracketed vector in %s: %s', File_Path, Text);
end
Interior = strtrim(Text(2:end-1));
if isempty(Interior)
    Vector = zeros(1, 0);
else
    Vector = sscanf(Interior, '%f').';
end
if any(~isfinite(Vector)) || any(Vector~=round(Vector)) || ...
        (~isempty(Expected_Length) && numel(Vector)~=Expected_Length)
    error('Fig10:InvalidVector', 'Invalid integer vector in %s: %s', File_Path, Text);
end
end

function Buses = parse_bus_list(Value, File_Path)
%% 解析已安装设备的节点列表，并拒绝含义不明确的文本。
Text = strtrim(char(string(Value)));
if strcmp(Text, 'zeros(1,0)') || strcmp(Text, '[]')
    Buses = zeros(1, 0);
elseif isempty(Text)
    error('Fig10:InvalidInstalledBuses', 'Installed-bus list is blank in %s.', File_Path);
elseif Text(1)=='[' && Text(end)==']'
    Buses = parse_integer_vector(Text, [], File_Path);
else
    Buses = sscanf(Text, '%f').';
    if ~isscalar(Buses) || any(~isfinite(Buses)) || ...
            any(Buses~=round(Buses))
        error('Fig10:InvalidInstalledBuses', ...
            'Cannot uniquely parse installed buses in %s: %s', File_Path, Text);
    end
end
end

function Text = make_configuration_label(Buses, Counts)
%% 将节点及设备数转换为热图中的配置标签。
Active = Counts>0;
if ~any(Active)
    Text = "0";
    return;
end
Parts = strings(1, nnz(Active));
Active_Indices = find(Active);
for Index = 1:numel(Active_Indices)
    k = Active_Indices(Index);
    Parts(Index) = sprintf('Bus %d(%d)', Buses(k), Counts(k));
end
Text = strjoin(Parts, '+');
end

function Values = logical_numeric(Input, Field_Name)
%% 核验逻辑值或0/1数值，并转换为逻辑数组。
if islogical(Input)
    Values = Input;
elseif isnumeric(Input) && all(ismember(Input(:), [0 1]))
    Values = logical(Input);
else
    error('Fig10:InvalidBoolean', '%s must contain only Boolean values.', Field_Name);
end
end

function close_if_open(fig)
%% 图窗仍存在时关闭图窗。
if isgraphics(fig)
    close(fig);
end
end
