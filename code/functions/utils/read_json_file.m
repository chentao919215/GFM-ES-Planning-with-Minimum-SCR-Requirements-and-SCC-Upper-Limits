function data = read_json_file(file_path)
%READ_JSON_FILE 读取 JSON 参数文件并解码为 MATLAB 结构体。

if exist(file_path, 'file') ~= 2
    error('JSON file does not exist: %s', file_path);
end

data = jsondecode(fileread(file_path));

end
