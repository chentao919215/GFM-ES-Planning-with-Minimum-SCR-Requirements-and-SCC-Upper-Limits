%% 分别生成SCC、经典SCR和安全裕度图及对应表格。
% 以下路径留空时，脚本自动使用最新结果、默认参数文件和默认输出目录。
if ~exist('Result_File', 'var'), Result_File = ''; end
if ~exist('Output_Directory', 'var'), Output_Directory = ''; end
if ~exist('Parameter_File', 'var'), Parameter_File = ''; end
if ~exist('Scenario_Index', 'var'), Scenario_Index = []; end
[Data, Output_Directory] = load_figure_data(Result_File, Output_Directory, ...
    Parameter_File, '04_security', Scenario_Index);

S = Data.Security;
D = Data.D;
if exist('Typical_Day_Index', 'var') && ~isempty(Typical_Day_Index)
    Day_Indices = Typical_Day_Index;
else
    Day_Indices = 1:D;
end
Max_SCC_Error = max(S.SCC_1_vs_SCC_2_Relative_Error_Pct(:), [], 'omitnan');
Max_SCR_Error = max(S.SCR_Relative_Error_Pct(:), [], 'omitnan');

% 矩阵按[安全节点,典型日]保存；导出与绘图时按典型日逐块展开。
SCC_Day = reshape(repelem(Day_Indices(:),numel(S.SCC_Nodes)), [], 1);
SCC_Bus = repmat(S.SCC_Nodes,numel(Day_Indices),1);
SCC_0 = S.SCC_0(:,Day_Indices); SCC_0 = SCC_0(:);
SCC_1 = S.SCC_1(:,Day_Indices); SCC_1 = SCC_1(:);
SCC_2 = S.SCC_2(:,Day_Indices); SCC_2 = SCC_2(:);
SCC_Limit = S.SCC_Limit(:,Day_Indices); SCC_Limit = SCC_Limit(:);
SCC_1_Margin = S.SCC_1_Margin(:,Day_Indices); SCC_1_Margin = SCC_1_Margin(:);
SCC_2_Margin = S.SCC_2_Margin(:,Day_Indices); SCC_2_Margin = SCC_2_Margin(:);
SCC_Error = S.SCC_1_vs_SCC_2_Relative_Error_Pct(:,Day_Indices);
SCC_Error = SCC_Error(:);
SCC_Labels = compose('D%d-B%d',SCC_Day,SCC_Bus);

SCR_Day = reshape(repelem(Day_Indices(:),numel(S.SCR_Nodes)), [], 1);
SCR_Bus = repmat(S.SCR_Nodes,numel(Day_Indices),1);
SCR_Optimization = S.SCR_Optimization(:,Day_Indices); SCR_Optimization = SCR_Optimization(:);
SCR_Exact = S.SCR_Exact(:,Day_Indices); SCR_Exact = SCR_Exact(:);
SCR_Limit = S.SCR_Limit(:,Day_Indices); SCR_Limit = SCR_Limit(:);
SCR_Margin = S.SCR_Margin(:,Day_Indices); SCR_Margin = SCR_Margin(:);
SCR_Error = S.SCR_Relative_Error_Pct(:,Day_Indices); SCR_Error = SCR_Error(:);
SCR_Labels = compose('D%d-B%d',SCR_Day,SCR_Bus);

fig = new_figure([9.0 5.0]); ax = axes(fig);
x = 1:numel(SCC_Bus);
b = bar(ax, x, [SCC_0 SCC_1 SCC_2], 0.78, ...
    'EdgeColor', 'k', 'LineWidth', 0.7);
b(1).FaceColor = [0.34 0.54 0.72];
b(2).FaceColor = [0.78 0.55 0.25];
b(3).FaceColor = [0.42 0.66 0.43];
hold(ax, 'on');
p = plot(ax, x, SCC_Limit, 'k-d', 'LineWidth', 1.2, ...
    'MarkerFaceColor', 'w', 'MarkerSize', 5);
[Min_Margin, Min_Index] = min(SCC_1_Margin);
plot(ax, Min_Index, SCC_1(Min_Index), 'ko', 'MarkerSize', 9, 'LineWidth', 1.2);
text(ax, Min_Index, SCC_1(Min_Index), sprintf('  SCC_1 min margin %.3f kA', Min_Margin), ...
    'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'center', ...
    'FontName', 'Times New Roman', 'FontSize', 9);
hold(ax, 'off'); style_sci_axes(ax);
xticks(ax, x); xticklabels(ax, SCC_Labels);
xlabel(ax, 'Typical day - SCC-constrained bus'); ylabel(ax, 'Short-circuit current (kA)');
title(ax, sprintf(['SCC_0/SCC_1/SCC_2 comparison ', ...
    '(max SCC_1 vs SCC_2 error %.2e%%)'], Max_SCC_Error));
legend(ax, [b(:);p], {'SCC_0: all-SG baseline', ...
    'SCC_1: optimization-model result','SCC_2: post-hoc recalculation', ...
    'Upper limit'}, 'Location', 'southoutside', 'NumColumns', 2);
save_figure_file(fig, fullfile(Output_Directory, 'SCC_level_and_limit'));

fig = new_figure([7.5 4.8]); ax = axes(fig);
x = 1:numel(SCR_Bus);
b = bar(ax, x, [SCR_Optimization SCR_Exact], 0.68, ...
    'EdgeColor', 'k', 'LineWidth', 0.7);
b(1).FaceColor = [0.34 0.54 0.72];
b(2).FaceColor = [0.78 0.55 0.25];
hold(ax, 'on');
p = plot(ax, x, SCR_Limit, 'k-d', 'LineWidth', 1.2, ...
    'MarkerFaceColor', 'w', 'MarkerSize', 5);
[Min_Margin, Min_Index] = min(SCR_Margin);
plot(ax, Min_Index, SCR_Exact(Min_Index), 'ko', 'MarkerSize', 9, 'LineWidth', 1.2);
text(ax, Min_Index, SCR_Exact(Min_Index), sprintf('  min margin %.4g', Min_Margin), ...
    'VerticalAlignment', 'bottom', 'FontName', 'Times New Roman', 'FontSize', 9);
hold(ax, 'off'); style_sci_axes(ax);
xticks(ax, x); xticklabels(ax, SCR_Labels);
xlabel(ax, 'Typical day - classic-SCR-constrained GFL-WG bus');
ylabel(ax, 'Classic short-circuit ratio (p.u.)');
title(ax, sprintf(['Classic SCR in daily aggregated conservative states ', ...
    '(max post-hoc error %.2e%%)'], Max_SCR_Error));
legend(ax, [b(:);p], {'Optimization reconstruction','Post-hoc direct inversion', ...
    'Lower limit'}, 'Location', 'southoutside', 'NumColumns', 3);
save_figure_file(fig, fullfile(Output_Directory, 'classic_SCR_level_and_limit'));

fig = new_figure([9.0 6.2]);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = nexttile(tl);
[~,idx] = sort(SCC_1_Margin, 'ascend');
b = bar(ax, 1:numel(idx), [SCC_1_Margin(idx) SCC_2_Margin(idx)], ...
    0.72, 'EdgeColor', 'k');
b(1).FaceColor = [0.78 0.55 0.25];
b(2).FaceColor = [0.42 0.66 0.43];
style_sci_axes(ax); yline(ax, 0, 'k--');
xticks(ax, 1:numel(idx)); xticklabels(ax, SCC_Labels(idx));
xlabel(ax, 'Typical day - bus (tightest first)'); ylabel(ax, 'SCC margin (kA)');
title(ax, 'SCC upper-limit margins: limit - SCC result');
legend(ax, {'SCC_1 model margin','SCC_2 post-hoc margin'}, ...
    'Location', 'best', 'NumColumns', 2);
ax = nexttile(tl);
[v,idx] = sort(SCR_Margin, 'ascend');
bar(ax, 1:numel(v), v, 0.68, 'FaceColor', [0.76 0.53 0.24], 'EdgeColor', 'k');
style_sci_axes(ax); yline(ax, 0, 'k--');
xticks(ax, 1:numel(v)); xticklabels(ax, SCR_Labels(idx));
xlabel(ax, 'Typical day - bus (tightest first)'); ylabel(ax, 'Classic SCR margin (p.u.)');
title(ax, 'Classic SCR lower-limit margin: post-hoc value - limit');
title(tl, 'Security margins in daily aggregated conservative states', ...
    'FontName', 'Times New Roman', 'FontSize', 12);
save_figure_file(fig, fullfile(Output_Directory, 'security_margin_ranking'));

SCC_Table = table(SCC_Day,SCC_Bus,SCC_0,SCC_1,SCC_2,SCC_Limit, ...
    SCC_1_Margin,SCC_2_Margin,SCC_Error,'VariableNames', ...
    {'TypicalDay','Bus','SCC_0_AllSGBaseline_kA', ...
    'SCC_1_OptimizationModel_kA','SCC_2_PostHoc_kA','UpperLimit_kA', ...
    'SCC_1_Margin_kA','SCC_2_Margin_kA', ...
    'SCC_1_vs_SCC_2_RelativeError_pct'});
SCR_Table = table(SCR_Day,SCR_Bus,SCR_Optimization,SCR_Exact,SCR_Limit, ...
    SCR_Margin,SCR_Error,'VariableNames', ...
    {'TypicalDay','Bus','OptimizationClassicSCR','PostHocClassicSCR','LowerLimit', ...
    'Margin','RelativeError_pct'});
Report = struct();
Report.SCC_Definition = S.SCC_Definition;
Report.SCC = SCC_Table;
Report.ClassicSCR = SCR_Table;
Report.Validation = [validation_row('SCC_1_vs_SCC_2_max_relative_error', ...
    Max_SCC_Error, 0.1, 'percent'); ...
    validation_row('classic_SCR_max_posthoc_relative_error', ...
    Max_SCR_Error, 0.1, 'percent'); ...
    validation_row('minimum_SCC_1_security_margin', min(SCC_1_Margin), ...
    0, 'kA', all(SCC_1_Margin >= -1e-6)); ...
    validation_row('minimum_SCC_2_security_margin', min(SCC_2_Margin), ...
    0, 'kA', all(SCC_2_Margin >= -1e-6)); ...
    validation_row('minimum_classic_SCR_security_margin', min(SCR_Margin), ...
        0, 'p.u.', all(SCR_Margin >= -1e-6))];

function fig = new_figure(Size_Inches)
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', ...
    'Position', [1 1 Size_Inches]);
end

function save_figure_file(fig, File_Path)
set(fig, 'Color', 'w', 'InvertHardcopy', 'off');
drawnow;
if ~endsWith(File_Path, '.fig', 'IgnoreCase', true)
    File_Path = [File_Path '.fig'];
end
set(fig, 'Visible', 'on');
Png_Path = strrep(File_Path, '.fig', '.png');
Output_Directory = fileparts(File_Path);
Temp_Fig_Path = [tempname(Output_Directory) '.fig'];
Temp_Png_Path = [tempname(Output_Directory) '.png'];
Cleanup_Temp_Files = onCleanup(@() delete_temp_files( ...
    {Temp_Fig_Path, Temp_Png_Path})); %#ok<NASGU>

% 先写临时文件，再替换目标文件，避免旧FIG文件状态影响savefig。
savefig(fig, Temp_Fig_Path);
exportgraphics(fig, Temp_Png_Path, 'Resolution', 600, ...
    'BackgroundColor', 'white');
replace_file(Temp_Fig_Path, File_Path);
replace_file(Temp_Png_Path, Png_Path);
set(fig, 'Visible', 'off');
close(fig);
end

function replace_file(Source_Path, Target_Path)
[Success, Message] = movefile(Source_Path, Target_Path, 'f');
if ~Success
    error('无法替换图件文件%s：%s', Target_Path, Message);
end
end

function delete_temp_files(File_Paths)
for k = 1:numel(File_Paths)
    if isfile(File_Paths{k})
        delete(File_Paths{k});
    end
end
end

function row = validation_row(name, value, tolerance, unit, passed)
if nargin < 5
    passed = abs(value) <= tolerance;
end
row = table(string(name), value, abs(value), tolerance, string(unit), ...
    logical(passed), 'VariableNames', ...
    {'Check','Value','AbsoluteValue','Tolerance','Unit','Passed'});
end
