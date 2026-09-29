function CONF = apply_multiple_snapshot_solver_stage(CONF, Stage_Configuration)
%% Apply workflow metadata and the selected backend's native stage options.

if nargin < 2 || isempty(Stage_Configuration)
    return;
end

Stage_Fields = fieldnames(Stage_Configuration);
for k = 1:numel(Stage_Fields)
    Field_Name = Stage_Fields{k};
    if any(strcmp(Field_Name, {'Name','Options'}))
        continue;
    end
    CONF.Solver.(Field_Name) = Stage_Configuration.(Field_Name);
end

if isfield(CONF, 'solver') && isfield(Stage_Configuration, 'Options')
    Solver_Name = lower(char(CONF.solver.name));
    if isfield(Stage_Configuration.Options, Solver_Name)
        Native_Options = Stage_Configuration.Options.(Solver_Name);
        Native_Fields = fieldnames(Native_Options);
        for k = 1:numel(Native_Fields)
            Field_Name = Native_Fields{k};
            CONF.solver.options.(Solver_Name).(Field_Name) = ...
                Native_Options.(Field_Name);
        end
    end
end

CONF.Solver.Solve_Stage = char(Stage_Configuration.Name);

end