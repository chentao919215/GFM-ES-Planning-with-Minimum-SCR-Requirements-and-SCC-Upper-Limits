function Project_Root = resolve_project_root_for_script()
%% 本函数功能是为不同MATLAB运行方式定位项目根目录。

Script_File = mfilename('fullpath');
Script_Directory = fileparts(Script_File);
Utils_Directory = fullfile(Script_Directory, '..', 'functions', 'utils');
if isfolder(Utils_Directory)
    addpath(Utils_Directory);
end

try
    Project_Root = find_project_root(Script_Directory);
catch ME
    Explicit_Root = getenv('PROJECT_2_ROOT');
    if isempty(Explicit_Root)
        rethrow(ME);
    end
    Project_Root = find_project_root(Explicit_Root);
end

Project_Root = char(java.io.File(Project_Root).getCanonicalPath());
end
