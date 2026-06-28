function [CONF, Info] = attach_latest_multiple_snapshot_mip_start(CONF, results_dir)
%% 本函数功能是从最近一次兼容且含可行解的结果中读取整数MIP热启动。

Info = struct('used',false, 'result_file','', 'reason','disabled');
if ~isfield(CONF, 'UseLatestMIPStart') || ~CONF.UseLatestMIPStart
    return;
end

Info.reason = '未找到兼容且含可行解的结果';
files = dir(fullfile(results_dir, 'multiple_snapshot_planning_result_*.mat'));
if isempty(files)
    return;
end

[~, order] = sort([files.datenum], 'descend');
files = files(order);

for k = 1:numel(files)
    result_file = fullfile(files(k).folder, files(k).name);
    try
        loaded = load(result_file, 'Result');
    catch
        continue;
    end
    if ~isfield(loaded, 'Result') || ~is_compatible_result(loaded.Result, CONF)
        continue;
    end

    Result = loaded.Result;
    CONF.MIPStart = struct();
    CONF.MIPStart.u_G = reshape(round(Result.u_G), ...
        CONF.Gn, CONF.TypicalDayCount, CONF.PeriodCount);
    CONF.MIPStart.u_G_SCC = round(Result.u_G_SCC(:));
    CONF.MIPStart.u_G_SCR = round(Result.u_G_SCR(:));
    CONF.MIPStart.u_GFM_Mod = round(Result.u_GFM_Mod);
    CONF.MIPStart.SourceFile = result_file;

    Info.used = true;
    Info.result_file = result_file;
    Info.reason = '';
    return;
end

end

function tf = is_compatible_result(Result, CONF)
%% 本函数功能是校验历史结果与当前算例的整数变量索引是否一致。

has_valid_diagnostics = isfield(Result, 'Diagnostics') && ...
    isfield(Result.Diagnostics, 'problem') && ...
    (Result.Diagnostics.problem == 0 || ...
     (isfield(Result.Diagnostics, 'has_incumbent') && ...
      Result.Diagnostics.has_incumbent));

tf = has_valid_diagnostics && isfield(Result, 'CONF') && isfield(Result, 'u_G') && ...
     isfield(Result, 'u_G_SCC') && isfield(Result, 'u_G_SCR') && ...
     isfield(Result, 'u_GFM_Mod');
if ~tf
    return;
end

old_conf = Result.CONF;
required_fields = {'Gn','TypicalDayCount','PeriodCount', ...
    'GFM_Module_Bus','GFM_Module_Order','GFM_MaxModulesPerCandidate'};
if ~all(isfield(old_conf, required_fields))
    tf = false;
    return;
end

tf = old_conf.Gn == CONF.Gn && ...
     old_conf.TypicalDayCount == CONF.TypicalDayCount && ...
     old_conf.PeriodCount == CONF.PeriodCount && ...
     isequal(old_conf.GFM_Module_Bus(:), CONF.GFM_Module_Bus(:)) && ...
     isequal(old_conf.GFM_Module_Order(:), CONF.GFM_Module_Order(:)) && ...
     old_conf.GFM_MaxModulesPerCandidate == CONF.GFM_MaxModulesPerCandidate && ...
     numel(Result.u_G) == CONF.Gn*CONF.TypicalDayCount*CONF.PeriodCount && ...
     isequal(size(Result.u_GFM_Mod), ...
        [numel(CONF.GFM_Module_Candidates), CONF.GFM_MaxModulesPerCandidate]);

end
