function project_root = find_project_root(start_path)
%% 本函数功能是从给定路径向上查找项目根目录。

if nargin < 1 || isempty(start_path)
    start_path = pwd;
end

if isfolder(start_path)
    current_dir = start_path;
else
    current_dir = fileparts(start_path);
end

while true
    if is_project_root(current_dir)
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

function tf = is_project_root(candidate)
% 该函数判断候选目录是否为本项目根目录。

tf = isfolder(fullfile(candidate, 'code', 'functions')) && ...
     isfolder(fullfile(candidate, 'data', 'params')) && ...
     isfile(fullfile(candidate, 'data', 'params', 'multiple_snapshot_default_params.json'));
end
