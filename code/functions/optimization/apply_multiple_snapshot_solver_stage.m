function CONF = apply_multiple_snapshot_solver_stage(CONF, Stage_Configuration)
%% 记录当前阶段名称，并覆盖该阶段的原生求解选项。

%% 1. 记录阶段名称并读取该阶段的原生选项
CONF.SolveStage = char(Stage_Configuration.Name);
Solver_Name = CONF.solver.name;
Native_Options = Stage_Configuration.Options.(Solver_Name);

%% 2. 逐字段覆盖阶段选项，保留其余公共设置
Native_Fields = fieldnames(Native_Options);
for k = 1:numel(Native_Fields)
    Field_Name = Native_Fields{k};
    CONF.solver.options.(Solver_Name).(Field_Name) = Native_Options.(Field_Name);
end
end
