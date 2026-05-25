function data = read_json_file(file_path)
%% 本函数功能是读取JSON参数文件并解码为MATLAB结构体。

if exist(file_path, 'file') ~= 2
    error('JSON file does not exist: %s', file_path);
end

data = jsondecode(fileread(file_path));

end
