function Options = figure_options(Options, Defaults)
%% 合并显式绘图选项，并拒绝未定义的字段。
if isempty(Options)
    Options = struct();
end
validateattributes(Options, {'struct'}, {'scalar'});
Defaults.Visible = false;
Defaults.Close_After_Save = true;
Unknown = setdiff(fieldnames(Options), fieldnames(Defaults));
assert(isempty(Unknown), 'FigureOptions:UnknownField', ...
    'Unknown figure option: %s', strjoin(Unknown, ', '));
Names = fieldnames(Defaults);
for k = 1:numel(Names)
    Name = Names{k};
    if ~isfield(Options, Name)
        Options.(Name) = Defaults.(Name);
    end
end
validateattributes(Options.Visible, {'logical'}, {'scalar'});
validateattributes(Options.Close_After_Save, {'logical'}, {'scalar'});
end
