function Paths = configure_simulink_file_generation_from_model(Model_Name)
%CONFIGURE_SIMULINK_FILE_GENERATION_FROM_MODEL 为当前Simulink模型固定生成目录。
%   该函数供模型InitFcn回调调用，不恢复原配置，因此适合手动点击
%   Simulink模型的“运行”按钮。生成文件统一写入simulink/artifacts。

if nargin < 1 || isempty(Model_Name)
    Model_Name = bdroot;
end

Model_File = get_param(Model_Name, 'FileName');
if isempty(Model_File)
    error('当前模型尚未保存，无法确定项目根目录。');
end

candidate = char(java.io.File(fileparts(Model_File)).getCanonicalPath());
while true
    if isfolder(fullfile(candidate, 'code')) && ...
            isfolder(fullfile(candidate, 'simulink', 'models'))
        Project_Root = candidate;
        break;
    end

    parent = fileparts(candidate);
    if strcmp(parent, candidate)
        error('无法从模型目录%s找到项目根目录。', fileparts(Model_File));
    end
    candidate = parent;
end

Equipment_Directory = fullfile(Project_Root, 'code', 'functions', 'equipment');
if isempty(which('configure_simulink_file_generation'))
    addpath(Equipment_Directory);
end

% 此处只取路径，不保留onCleanup对象；模型回调需要让配置持续有效，
% 直到用户或其他工程显式修改Simulink.fileGenControl配置。
[~, Paths] = configure_simulink_file_generation(Project_Root);
Simulink.fileGenControl('set', ...
    'CacheFolder', Paths.Cache, ...
    'CodeGenFolder', Paths.Codegen, ...
    'createDir', true);
end
