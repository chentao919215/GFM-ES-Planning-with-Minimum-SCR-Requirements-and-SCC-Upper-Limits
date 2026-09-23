function CONF = apply_multiple_snapshot_solver_stage(CONF, Stage_Configuration)
%% 将两阶段配置中的覆盖项应用到当前COPT参数结构。

if nargin < 2 || isempty(Stage_Configuration)
    return;
end

% Name只用于结果标记，不作为COPT求解参数。
Stage_Fields = fieldnames(Stage_Configuration);
for k = 1:numel(Stage_Fields)
    Field_Name = Stage_Fields{k};
    if strcmp(Field_Name, 'Name')
        continue;
    end
    CONF.Solver.(Field_Name) = Stage_Configuration.(Field_Name);
end

CONF.Solver.Solve_Stage = char(Stage_Configuration.Name);

end
