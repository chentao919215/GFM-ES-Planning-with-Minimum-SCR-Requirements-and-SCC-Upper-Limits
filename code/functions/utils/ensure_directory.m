function ensure_directory(dir_path)
%% 本函数功能是确保目标目录存在。

if ~exist(dir_path, 'dir')
    mkdir(dir_path);
end

end
