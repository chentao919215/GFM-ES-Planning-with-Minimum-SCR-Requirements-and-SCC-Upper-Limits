function CONF = apply_multiple_snapshot_solver_stage(CONF, stage_config)
%% 将两阶段配置中的覆盖项应用到当前Gurobi参数。

if nargin < 2 || isempty(stage_config)
    return;
end

% Name只用于结果标记，不应传递给Gurobi。
stage_fields = fieldnames(stage_config);
for k = 1:numel(stage_fields)
    field_name = stage_fields{k};
    if strcmp(field_name, 'Name')
        continue;
    end
    CONF.Solver.(field_name) = stage_config.(field_name);
end

if isfield(stage_config, 'Name')
    CONF.SolveStage = char(stage_config.Name);
else
    CONF.SolveStage = '';
end

end
