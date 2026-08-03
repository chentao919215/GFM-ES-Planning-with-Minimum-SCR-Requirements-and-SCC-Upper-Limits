function Result_File = save_multiple_snapshot_result(Result, Results_Directory)
%% 本函数功能是保存多时刻规划结果。

ensure_directory(Results_Directory);

timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
Result_File = fullfile(Results_Directory, ['multiple_snapshot_planning_result_', timestamp, '.mat']);
save(Result_File, 'Result', '-v7.3');

end
