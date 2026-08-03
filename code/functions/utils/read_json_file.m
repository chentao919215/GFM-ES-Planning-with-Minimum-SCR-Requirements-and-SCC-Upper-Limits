function data = read_json_file(File_Path)
%% 本函数功能是读取JSON参数文件并解码为MATLAB结构体。

if exist(File_Path, 'file') ~= 2
    error('JSON file does not exist: %s', File_Path);
end

data = jsondecode(fileread(File_Path));

end
