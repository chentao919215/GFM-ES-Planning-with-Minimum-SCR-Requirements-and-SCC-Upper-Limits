function export_sci_figure(fig, Output_Stem)
%% Export one white-background figure as vector PDF and 600 dpi PNG.

set(fig, 'Color', 'w', 'InvertHardcopy', 'off');
drawnow;
PDF_File = [Output_Stem, '.pdf'];
PNG_File = [Output_Stem, '.png'];

exportgraphics(fig, PDF_File, 'ContentType', 'vector', ...
    'BackgroundColor', 'white');
exportgraphics(fig, PNG_File, 'Resolution', 600, ...
    'BackgroundColor', 'white');
close(fig);
end
