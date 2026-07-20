function configure_simulink_model_callbacks()
%CONFIGURE_SIMULINK_MODEL_CALLBACKS 为工程内模型写入自动生成目录回调。
%   回调写入模型的InitFcn。模型手动运行时会自动使用simulink/artifacts。

script_dir = fileparts(mfilename('fullpath'));
project_root = find_project_root_local(script_dir);
equipment_dir = fullfile(project_root, 'code', 'functions', 'equipment');
addpath(equipment_dir);

model_dir = fullfile(project_root, 'simulink', 'models');
model_files = dir(fullfile(model_dir, '*.slx'));
callback = [ ...
    'configure_simulink_file_generation_from_model(bdroot);'];

for k = 1:numel(model_files)
    model_file = fullfile(model_files(k).folder, model_files(k).name);
    model_name = erase(model_files(k).name, '.slx');
    load_system(model_file);
    set_param(model_name, 'InitFcn', callback);
    save_system(model_name, model_file);
    close_system(model_name, 0);
end

fprintf('已为%d个Simulink模型写入InitFcn生成目录回调。\n', numel(model_files));
fprintf('固定目录：%s\n', fullfile(project_root, 'simulink', 'artifacts'));
end

function project_root = find_project_root_local(start_dir)
candidate = char(java.io.File(start_dir).getCanonicalPath());
while true
    if isfolder(fullfile(candidate, 'code')) && ...
            isfolder(fullfile(candidate, 'simulink', 'models'))
        project_root = candidate;
        return;
    end
    parent = fileparts(candidate);
    if strcmp(parent, candidate)
        error('无法从目录%s找到项目根目录。', start_dir);
    end
    candidate = parent;
end
end
