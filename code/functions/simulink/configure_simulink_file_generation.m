function [Cleanup_Obj, Paths] = configure_simulink_file_generation(Project_Root, Mode)
%CONFIGURE_SIMULINK_FILE_GENERATION 固定Simulink编译文件的生成目录。
%   slprj和.slxc等文件统一写入项目根目录下的simulink/artifacts，
%   避免因为当前工作目录不同而散落到各个文件夹。
%
%   默认temporary模式返回清理对象，调用方结束时恢复此前配置。
%   persistent模式供模型回调使用，配置持续生效，清理对象为空。

if nargin < 1 || isempty(Project_Root)
    error('必须提供项目根目录。');
end
if nargin < 2
    Mode = 'temporary';
end
Mode = validatestring(Mode, {'temporary', 'persistent'}, mfilename, 'Mode');

Project_Root = char(java.io.File(Project_Root).getCanonicalPath());
Artifact_Root = fullfile(Project_Root, 'simulink', 'artifacts');
Paths = struct();
Paths.Root = Artifact_Root;
Paths.Cache = fullfile(Artifact_Root, 'cache');
Paths.Codegen = fullfile(Artifact_Root, 'codegen');

if ~isfolder(Paths.Cache)
    mkdir(Paths.Cache);
end
if ~isfolder(Paths.Codegen)
    mkdir(Paths.Codegen);
end

if strcmp(Mode, 'temporary')
    Old_Configuration = Simulink.fileGenControl('getConfig');
end
Simulink.fileGenControl('set', ...
    'CacheFolder', Paths.Cache, ...
    'CodeGenFolder', Paths.Codegen, ...
    'createDir', true);

Cleanup_Obj = [];
if strcmp(Mode, 'temporary')
    Cleanup_Obj = onCleanup(@() restore_file_generation_config(Old_Configuration));
end
end

function restore_file_generation_config(Old_Configuration)
%% 恢复调用前的Simulink文件生成目录设置。
try
    Simulink.fileGenControl('setConfig', 'config', Old_Configuration);
catch ME
    warning('Project:SimulinkFileGenerationRestoreFailed', ...
        '恢复Simulink文件生成配置失败：%s', ME.message);
end
end
