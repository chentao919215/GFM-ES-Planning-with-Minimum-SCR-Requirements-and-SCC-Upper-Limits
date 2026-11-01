function write_json_file(File_Path, Data)
%% 以UTF-8编码保存带缩进的JSON，并在写入结束或报错时关闭文件。
fid = fopen(File_Path, 'w', 'n', 'UTF-8');
assert(fid >= 0, 'IO:JSONWriteFailed', '无法写入JSON文件：%s', File_Path);
Cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(Data, 'PrettyPrint', true));
end
