function Project_Root = find_project_root(Start_Path)
%% 本函数功能是从给定路径向上查找项目根目录。

if nargin < 1 || isempty(Start_Path)
    Start_Path = pwd;
end

if isfolder(Start_Path)
    Current_Directory = Start_Path;
else
    Current_Directory = fileparts(Start_Path);
end

while true
    if is_project_root(Current_Directory)
        Project_Root = Current_Directory;
        return;
    end

    Parent_Directory = fileparts(Current_Directory);
    if strcmp(Parent_Directory, Current_Directory)
        error('Project root was not found from path: %s', Start_Path);
    end
    Current_Directory = Parent_Directory;
end

end

function tf = is_project_root(candidate)
% 该函数判断候选目录是否为本项目根目录。

tf = isfolder(fullfile(candidate, 'code', 'functions')) && ...
    isfolder(fullfile(candidate, 'simulink', 'models'));
end
