function [cleanup_obj, paths] = configure_simulink_file_generation(project_root)
%CONFIGURE_SIMULINK_FILE_GENERATION 固定Simulink编译文件的生成目录。
%   slprj和.slxc等文件统一写入项目根目录下的simulink/artifacts，
%   避免因为当前工作目录不同而散落到各个文件夹。
%
%   返回的cleanup_obj在调用方结束时恢复调用前的Simulink文件生成配置。

if nargin < 1 || isempty(project_root)
    error('必须提供项目根目录。');
end

project_root = char(java.io.File(project_root).getCanonicalPath());
artifact_root = fullfile(project_root, 'simulink', 'artifacts');
paths = struct();
paths.root = artifact_root;
paths.cache = fullfile(artifact_root, 'cache');
paths.codegen = fullfile(artifact_root, 'codegen');

if ~isfolder(paths.cache)
    mkdir(paths.cache);
end
if ~isfolder(paths.codegen)
    mkdir(paths.codegen);
end

old_config = Simulink.fileGenControl('getConfig');
Simulink.fileGenControl('set', ...
    'CacheFolder', paths.cache, ...
    'CodeGenFolder', paths.codegen, ...
    'createDir', true);

cleanup_obj = onCleanup(@() restore_file_generation_config(old_config));
end

function restore_file_generation_config(old_config)
try
    Simulink.fileGenControl('setConfig', 'config', old_config);
catch ME
    warning('Project:SimulinkFileGenerationRestoreFailed', ...
        '恢复Simulink文件生成配置失败：%s', ME.message);
end
end
