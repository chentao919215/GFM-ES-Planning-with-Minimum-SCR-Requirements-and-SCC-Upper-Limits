function Hash = calculate_joint_scan_file_hash(Path)
%% 读取文件字节并计算SHA-256校验值。
fid = fopen(Path, 'rb');
assert(fid >= 0, 'JointScan:MissingSource', '无法读取来源文件：%s', Path);
Cleanup = onCleanup(@() fclose(fid));
Digest = java.security.MessageDigest.getInstance('SHA-256');
Digest.update(fread(fid, Inf, '*uint8'));
Hash = lower(reshape(dec2hex(typecast(Digest.digest(), 'uint8'), 2).', 1, []));
end
