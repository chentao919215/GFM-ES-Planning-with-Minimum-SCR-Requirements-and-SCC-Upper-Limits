function style_sci_axes(ax)
%% Apply the shared black-and-white-safe SCI axis style.
set(ax, 'FontName', 'Times New Roman', 'FontSize', 10, ...
    'LineWidth', 0.8, 'Box', 'on', 'Layer', 'top', ...
    'TickDir', 'out', 'Color', 'w');
grid(ax, 'on');
ax.GridAlpha = 0.16;
ax.MinorGridAlpha = 0.08;
end
