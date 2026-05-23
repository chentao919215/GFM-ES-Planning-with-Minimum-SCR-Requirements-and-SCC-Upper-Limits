function project_root = find_project_root(start_path)
%FIND_PROJECT_ROOT 从给定路径向上查找项目根目录。

if nargin < 1 || isempty(start_path)
    start_path = pwd;
end

if isfolder(start_path)
    current_dir = start_path;
else
    current_dir = fileparts(start_path);
end

while true
    has_functions = isfolder(fullfile(current_dir, 'code', 'functions'));
    has_params = isfile(fullfile(current_dir, 'data', 'params', 'single_snapshot_default_params.json'));
    if has_functions && has_params
        project_root = current_dir;
        return;
    end

    parent_dir = fileparts(current_dir);
    if strcmp(parent_dir, current_dir)
        error('Project root was not found from path: %s', start_path);
    end
    current_dir = parent_dir;
end

end
