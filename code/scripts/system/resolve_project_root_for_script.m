function project_root = resolve_project_root_for_script()
%% 本函数功能是为不同MATLAB运行方式定位项目根目录。

script_file = mfilename('fullpath');
script_dir = fileparts(script_file);
utils_dir = fullfile(script_dir, '..', 'functions', 'utils');
if isfolder(utils_dir)
    addpath(utils_dir);
end

try
    project_root = find_project_root(script_dir);
catch ME
    explicit_root = getenv('PROJECT_2_ROOT');
    if isempty(explicit_root)
        rethrow(ME);
    end
    project_root = find_project_root(explicit_root);
end

project_root = char(java.io.File(project_root).getCanonicalPath());
end
