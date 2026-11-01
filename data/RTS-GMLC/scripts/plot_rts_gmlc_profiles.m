%% 绘制ManuscriptD=4、K=4的负荷与风电场景合图。
% 默认读取固定输入；不按文件修改时间选择数据，不修改原始结果或参数。
% 归一化曲线按当前IEEE-30负荷和GFL-WG总额定容量映射为MW。
% 可在下方修改输入、参数与图件目录；Figure_File记录FIG文件位置。

Module_Root = fileparts(fileparts(which('plot_rts_gmlc_profiles')));
Project_Root = fileparts(fileparts(Module_Root));
Result_File = fullfile(Module_Root, 'processed', 'rts_gmlc_profiles.mat');
Parameter_File = fullfile(Project_Root, 'data', 'params', ...
    'multiple_snapshot_default_params.json');
Figure_Directory = fullfile(Module_Root, 'results');

%% 1. 提取固定典型日及场景
Loaded = load(Result_File, 'Result');
Result = Loaded.Result;
D = 4;
K = 4;
D_Index = find([Result.Typical_Day_Sets.D] == D, 1);
assert(~isempty(D_Index), '输入数据不包含D=4的典型日。');
Typical = Result.Typical_Day_Sets(D_Index);
Scenario_Row = Result.Wind_Scenario_Sets(D_Index, :);
K_Index = find([Scenario_Row.K] == K, 1);
assert(~isempty(K_Index), '输入数据不包含K=4的风电场景。');
Scenario = Scenario_Row(K_Index);
assert(Scenario.Available, 'D=4、K=4的风电场景不可用。');
T = Result.Dimensions.Period_Count;
assert(T == 24 && isequal(size(Typical.System_Load_Normalized), [D T]) && ...
    isequal(size(Scenario.Wind_Scenario_Normalized), [D K T]), ...
    '负荷与风电场景的维度不符合D=4、K=4、T=24。');

Parameters = jsondecode(fileread(Parameter_File));
Base_Load_MW = sum(Parameters.Network.mpc.bus(:, 3));
Wind_Ratings = Parameters.GFL_WG.PN_MW(:);
if isscalar(Wind_Ratings)
    Wind_Ratings = repmat(Wind_Ratings, numel(Parameters.GFL_WG.Built_Nodes), 1);
end
Wind_Rated_MW = sum(Wind_Ratings);
Load_MW = Typical.System_Load_Normalized.*Base_Load_MW;
Wind_MW = Scenario.Wind_Scenario_Normalized.*Wind_Rated_MW;
assert(all(isfinite(Load_MW), 'all') && all(Load_MW >= 0, 'all') && ...
    all(isfinite(Wind_MW), 'all') && all(Wind_MW >= 0, 'all') && ...
    all(Wind_MW <= Wind_Rated_MW+1e-6, 'all') && ...
    all(abs(sum(Scenario.Probability, 2)-1) < 1e-10), ...
    '负荷、风电曲线或场景概率无效。');

%% 2. 绘制单栏2x2合图，共用底部图例
Width = 3.5;
Height = 3.65;
Fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', ...
    'Position', [1 1 Width Height], 'PaperUnits', 'inches', ...
    'PaperSize', [Width Height], 'PaperPosition', [0 0 Width Height]);
Layout = tiledlayout(Fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'loose');
Load_Color = [89 142 187]/255;
Wind_Colors = [140 205 198;148 142 193;156 203 150;108 170 196]/255;
Styles = {'-', '--', '-.', ':'};
Labels = {'(a)', '(b)', '(c)', '(d)'};
Load_Max = max(20, ceil(max(Load_MW, [], 'all')/20)*20);
Hours = 1:T;
First_Axes = gobjects(1);
Legend_Handles = gobjects(1, K+1);
for d = 1:D
    Ax = nexttile(Layout, d);
    set(Ax, 'FontName', 'Times New Roman', 'FontSize', 8, 'LineWidth', 0.6, ...
        'Box', 'on', 'XGrid', 'on', 'YGrid', 'on', 'GridAlpha', 0.12, 'TickDir', 'out');
    yyaxis(Ax, 'left');
    Load_Handle = plot(Ax, Hours, Load_MW(d, :), '-', ...
        'Color', Load_Color, 'LineWidth', 1.2);
    ylim(Ax, [0 Load_Max]);
    yticks(Ax, [0 Load_Max/2 Load_Max]);
    if mod(d, 2) == 1
        ylabel(Ax, 'Load (MW)', 'FontSize', 8.5);
    end
    Ax.YAxis(1).Color = Load_Color;
    yyaxis(Ax, 'right');
    hold(Ax, 'on');
    Wind_Handles = gobjects(1, K);
    for k = 1:K
        Wind_Handles(k) = plot(Ax, Hours, reshape(Wind_MW(d, k, :), 1, T), ...
            'Color', Wind_Colors(k, :), 'LineStyle', Styles{k}, 'LineWidth', 1.05);
    end
    hold(Ax, 'off');
    ylim(Ax, [0 Wind_Rated_MW]);
    yticks(Ax, [0 Wind_Rated_MW/2 Wind_Rated_MW]);
    if mod(d, 2) == 0
        ylabel(Ax, 'Wind (MW)', 'FontSize', 8.5);
    end
    Ax.YAxis(2).Color = [0.25 0.25 0.25];
    xlim(Ax, [1 T]);
    xticks(Ax, [1 8 16 24]);
    if d > 2
        xlabel(Ax, 'Hour', 'FontSize', 8.5);
    else
        xticklabels(Ax, []);
    end
    Date = char(string(Typical.Medoid_Date(d), 'MM-dd'));
    title(Ax, sprintf('%s Day %d (%s)', Labels{d}, d, Date), ...
        'FontName', 'Times New Roman', 'FontSize', 9, 'FontWeight', 'normal');
    if d == 1
        First_Axes = Ax;
        Legend_Handles = [Load_Handle Wind_Handles];
    end
end
Shared_Legend = legend(First_Axes, Legend_Handles, {'Load', 'S1', 'S2', 'S3', 'S4'}, ...
    'Orientation', 'horizontal', 'NumColumns', K+1, 'FontName', 'Times New Roman', ...
    'FontSize', 8, 'Box', 'off', 'Interpreter', 'none');
Shared_Legend.Layout.Tile = 'south';
Shared_Legend.ItemTokenSize = [14 10];
drawnow;

%% 3. 保存可编辑的MATLAB图件
if ~isfolder(Figure_Directory)
    mkdir(Figure_Directory);
end
Figure_File = fullfile(Figure_Directory, 'rts_gmlc_D4_K4_profiles.fig');
Fig.Visible = 'on';
savefig(Fig, Figure_File);
close(Fig);
fprintf('RTS-GMLC曲线图：%s\n', Figure_File);
