function configure_simulink_model_callbacks()
%CONFIGURE_SIMULINK_MODEL_CALLBACKS 为工程内模型写入自动生成目录回调。
%   回调写入模型的InitFcn。模型手动运行时会自动使用simulink/artifacts。

Script_Directory = fileparts(mfilename('fullpath'));
Project_Root = find_project_root_local(Script_Directory);
Equipment_Directory = fullfile(Project_Root, 'code', 'functions', 'equipment');
addpath(Equipment_Directory);

Model_Directory = fullfile(Project_Root, 'simulink', 'models');
Model_Files = dir(fullfile(Model_Directory, '*.slx'));
callback = [ ...
    'configure_simulink_file_generation_from_model(bdroot);'];

for k = 1:numel(Model_Files)
    Model_File = fullfile(Model_Files(k).folder, Model_Files(k).name);
    Model_Name = erase(Model_Files(k).name, '.slx');
    load_system(Model_File);
    set_param(Model_Name, 'InitFcn', callback);
    save_system(Model_Name, Model_File);
    close_system(Model_Name, 0);
end

fprintf('已为%d个Simulink模型写入InitFcn生成目录回调。\n', numel(Model_Files));
fprintf('固定目录：%s\n', fullfile(Project_Root, 'simulink', 'artifacts'));
end

function Project_Root = find_project_root_local(Start_Directory)
candidate = char(java.io.File(Start_Directory).getCanonicalPath());
while true
    if isfolder(fullfile(candidate, 'code')) && ...
            isfolder(fullfile(candidate, 'simulink', 'models'))
        Project_Root = candidate;
        return;
    end
    parent = fileparts(candidate);
    if strcmp(parent, candidate)
        error('无法从目录%s找到项目根目录。', Start_Directory);
    end
    candidate = parent;
end
end
