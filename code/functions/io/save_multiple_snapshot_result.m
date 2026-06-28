function result_file = save_multiple_snapshot_result(Result, results_dir)
%% 本函数功能是保存多时刻规划结果。

ensure_directory(results_dir);

timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
result_file = fullfile(results_dir, ['multiple_snapshot_planning_result_', timestamp, '.mat']);
save(result_file, 'Result', '-v7.3');

end
