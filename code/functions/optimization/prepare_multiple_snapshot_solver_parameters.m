function [Workflow, Backend] = prepare_multiple_snapshot_solver_parameters(params)
%% 将当前Solver参数整理为求解流程与求解器选项。
Workflow = params.Solver;
Backend.name = lower(char(Workflow.Name));
Backend.options.yalmip = Workflow.Options.YALMIP;
Backend.options.(Backend.name) = Workflow.Options.Gurobi;
Names = fieldnames(Workflow.One_Stage);
for k = 1:numel(Names)
    Backend.options.(Backend.name).(Names{k}) = Workflow.One_Stage.(Names{k});
end
if isfield(Workflow.Options, 'MIP_Start')
    Backend.options.mip_start.yalmip = Workflow.Options.MIP_Start.YALMIP;
end
% MIP_Gap保留最终目标间隙；各阶段仅保存名称与原生选项。
Workflow = rmfield(Workflow, {'Name', 'Options', 'One_Stage', 'Two_Stage_Enabled'});
Workflow.Two_Stage.Enabled = params.Solver.Two_Stage_Enabled;
for k = 1:2
    Field = sprintf('Stage_%d', k);
    Stage = params.Solver.Two_Stage.(Field);
    Workflow.Two_Stage.(Field) = struct('Name', Stage.Name, ...
        'Options', struct(Backend.name, rmfield(Stage, 'Name')));
end
end
