function export_sci_figure(fig, output_stem)
%% Export one white-background figure as vector PDF and 600 dpi PNG.

set(fig, 'Color', 'w', 'InvertHardcopy', 'off');
drawnow;
pdf_file = [output_stem, '.pdf'];
png_file = [output_stem, '.png'];

if exist('exportgraphics', 'file') ~= 0 || exist('exportgraphics', 'builtin') ~= 0
    exportgraphics(fig, pdf_file, 'ContentType', 'vector', ...
        'BackgroundColor', 'white');
    exportgraphics(fig, png_file, 'Resolution', 600, ...
        'BackgroundColor', 'white');
else
    warning('ver2_5:ExportCompatibility', ...
        'exportgraphics is unavailable; using print compatibility mode.');
    set(fig, 'PaperPositionMode', 'auto');
    print(fig, pdf_file, '-dpdf', '-painters', '-bestfit');
    print(fig, png_file, '-dpng', '-r600');
end
close(fig);
end
