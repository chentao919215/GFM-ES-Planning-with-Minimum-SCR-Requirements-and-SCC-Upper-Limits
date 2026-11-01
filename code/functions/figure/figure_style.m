function Style = figure_style(Profile)
%% 集中维护Manuscript配色及论文图、检查图的共用样式。
if nargin < 1
    Profile = 'review';
end
assert(any(strcmp(Profile, {'paper', 'review'})), 'FigureStyle:InvalidProfile', ...
    'Profile must be paper or review.');
Style.Profile = char(Profile);
Style.Font_Name = 'Times New Roman';
Style.Visible = false;
Style.Close_After_Save = true;
Style.Axis_Width = 0.8;
Style.Line_Width = 1.2;
Style.Grid_Alpha = 0.16;
if strcmp(Profile, 'paper')
    Style.Font_Size = 8.5; Style.Label_Size = 9;
    Style.Legend_Size = 7.5; Style.Title_Size = 9;
else
    Style.Font_Size = 10; Style.Label_Size = 11;
    Style.Legend_Size = 9.5; Style.Title_Size = 11;
end
C.SCC = [89 142 187]/255;
C.SCR = [108 170 196]/255;
C.Aggregated = [140 205 198]/255;
C.Periodwise = [148 142 193]/255;
C.Cases = [140 205 198;148 142 193;156 203 150;108 170 196;232 164 105]/255;
C.SG = C.SCC; C.GFL = C.Cases(3, :); C.GFM = C.Cases(5, :);
C.Offline = C.SCR; C.Online = C.SCC;
C.Reference = [0.30 0.30 0.30]; C.Text = [0.12 0.12 0.12];
C.Grid = [0.77 0.80 0.83]; C.Highlight = [196 123 67]/255;
Style.Colors = C;
Style.Sequential_Map = interp1([0 .5 1], ...
    [237 243 248;134 180 206;34 86 126]/255, linspace(0, 1, 256), 'linear');
end
