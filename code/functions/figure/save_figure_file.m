function Figure_File = save_figure_file(fig, Output_Base)
%% 仅保存可编辑FIG，完整写入临时文件后再替换目标文件。
Style = getappdata(fig, 'ProjectFigureStyle');
if isempty(Style)
    Style = figure_style('review');
end
for ax = findall(fig, 'Type', 'axes').'
    set(ax, 'FontName', Style.Font_Name, 'FontSize', Style.Font_Size, ...
        'LineWidth', Style.Axis_Width, 'Color', 'w', 'XMinorGrid', 'off', 'YMinorGrid', 'off');
    set([ax.XLabel ax.YLabel], 'FontName', Style.Font_Name, 'FontSize', Style.Label_Size);
    for Ruler = ax.YAxis(:).'
        set(Ruler.Label, 'FontName', Style.Font_Name, 'FontSize', Style.Label_Size);
    end
    set(ax.Title, 'FontName', Style.Font_Name, 'FontSize', Style.Title_Size, 'FontWeight', 'normal');
    if ~isempty(findall(ax, 'Type', 'image')) || ~isempty(findall(ax, 'Type', 'surface'))
        set(ax, 'XGrid', 'off', 'YGrid', 'off', 'Box', 'on');
    end
end
set(findall(fig, 'Type', 'text'), 'FontName', Style.Font_Name);
set(findall(fig, 'Type', 'legend'), 'FontName', Style.Font_Name, ...
    'FontSize', Style.Legend_Size, 'Box', 'off');
for Bar = findall(fig, 'Type', 'colorbar').'
    set(Bar, 'FontName', Style.Font_Name, 'FontSize', Style.Font_Size);
    set(Bar.Label, 'FontName', Style.Font_Name, 'FontSize', Style.Label_Size);
end
for Line = findall(fig, 'Type', 'line').'
    if numel(Line.XData)>2 && ~strcmp(Line.LineStyle, 'none')
        Line.LineWidth = Style.Line_Width;
    elseif Line.LineWidth>1.5
        Line.LineWidth = 1.5;
    end
end
Figure_File = char(Output_Base);
if ~endsWith(Figure_File, '.fig', 'IgnoreCase', true)
    Figure_File = [Figure_File '.fig'];
end
Directory = fileparts(Figure_File);
if isempty(Directory)
    Directory = pwd;
end
ensure_directory(Directory);
Temporary = [tempname(Directory) '.fig'];
Cleanup = onCleanup(@() delete_temporary(Temporary)); %#ok<NASGU>
Previous_Visibility = fig.Visible;
Restore = onCleanup(@() restore_visibility(fig, Previous_Visibility)); %#ok<NASGU>
% 保存为可见状态，确保在MATLAB中打开FIG时正常显示。
fig.Visible = 'on'; drawnow;
savefig(fig, Temporary);
[Success, Message] = movefile(Temporary, Figure_File, 'f');
assert(Success, 'FigureExport:ReplaceFailed', 'Cannot save %s: %s', Figure_File, Message);
if Style.Close_After_Save
    close(fig);
end
end

function delete_temporary(File)
%% 删除尚未替换到目标位置的临时文件。
if isfile(File)
    delete(File);
end
end

function restore_visibility(fig, Visibility)
%% 图窗仍存在时恢复调用前的可见状态。
if isgraphics(fig)
    fig.Visible = Visibility;
end
end
