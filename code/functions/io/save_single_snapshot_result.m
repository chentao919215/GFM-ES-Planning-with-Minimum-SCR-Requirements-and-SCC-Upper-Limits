function result_file = save_single_snapshot_result(Result, results_dir)
%SAVE_SINGLE_SNAPSHOT_RESULT 保存单时刻规划结果。

ensure_directory(results_dir);

timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
result_file = fullfile(results_dir, ['single_snapshot_planning_result_', timestamp, '.mat']);
save(result_file, 'Result');

end
