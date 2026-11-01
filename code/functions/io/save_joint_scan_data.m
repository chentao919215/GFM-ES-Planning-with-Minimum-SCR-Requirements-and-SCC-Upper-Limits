function save_joint_scan_data(File, Payload)
%% 先保存临时MAT文件，再替换目标文件，避免留下未写完的记录。
Temporary = [tempname(fileparts(File)), '.mat'];
Cleanup = onCleanup(@() delete_temporary(Temporary)); %#ok<NASGU>
save(Temporary, '-struct', 'Payload', '-v7.3');
movefile(Temporary, File, 'f');
end

function delete_temporary(File)
%% 删除尚未替换到目标位置的临时文件。
if isfile(File)
    delete(File);
end
end
