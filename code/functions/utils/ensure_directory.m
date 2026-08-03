function ensure_directory(Directory_Path)
%% 本函数功能是确保目标目录存在。

if ~exist(Directory_Path, 'dir')
    mkdir(Directory_Path);
end

end
