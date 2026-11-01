function fig = new_figure(Size_cm, Style)
%% 按厘米尺寸创建独立图窗，并记录该图窗使用的样式。
if nargin < 2
    Style = figure_style('review');
end
validateattributes(Size_cm, {'numeric'}, {'vector', 'numel', 2, 'finite', 'positive'});
Visibility = 'off';
if Style.Visible
    Visibility = 'on';
end
fig = figure('Color', 'w', 'Visible', Visibility, 'Units', 'centimeters', ...
    'Position', [2 2 Size_cm(:).'], 'PaperUnits', 'centimeters', ...
    'PaperPosition', [0 0 Size_cm(:).'], 'PaperSize', Size_cm(:).', ...
    'PaperPositionMode', 'auto', 'InvertHardcopy', 'off', ...
    'DefaultAxesFontName', Style.Font_Name, 'DefaultAxesFontSize', Style.Font_Size, ...
    'DefaultTextFontName', Style.Font_Name, 'DefaultAxesColorOrder', Style.Colors.Cases);
setappdata(fig, 'ProjectFigureStyle', Style);
end
