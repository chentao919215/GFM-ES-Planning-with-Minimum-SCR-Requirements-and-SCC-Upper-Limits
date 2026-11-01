function ops = build_multiple_snapshot_solver_options(Solver_Configuration, Has_MIP_Start)
%% 根据项目配置构造YALMIP与Gurobi选项。
% 依次应用基础与热启动选项；同名字段由后应用的配置覆盖。

%% 1. 校验求解器名称与原生选项
if nargin < 2
    Has_MIP_Start = false;
end
if ~isstruct(Solver_Configuration) || ~isfield(Solver_Configuration, 'name') || ...
        ~isfield(Solver_Configuration, 'options')
    error('MultipleSnapshot:InvalidSolverConfiguration', ...
        '求解器配置必须包含name和options字段。');
end
Solver_Name = lower(char(Solver_Configuration.name));
if ~strcmp(Solver_Name, 'gurobi')
    error('MultipleSnapshot:InvalidSolverName', ...
        'MILP求解器仅支持Gurobi，当前配置为%s。', Solver_Name);
end
Options = Solver_Configuration.options;
if ~isfield(Options, Solver_Name) || ~isstruct(Options.(Solver_Name))
    error('MultipleSnapshot:MissingSolverOptions', ...
        '未为求解器%s配置原生选项。', Solver_Name);
end

%% 2. 应用基础YALMIP与Gurobi选项
ops = sdpsettings('solver', Solver_Name);
if isfield(Options, 'yalmip')
    ops = apply_option_values(ops, Options.yalmip);
end
ops.(Solver_Name) = apply_option_values(ops.(Solver_Name), Options.(Solver_Name));

%% 3. 存在整数热启动时，覆盖对应求解选项
if Has_MIP_Start && isfield(Options, 'mip_start')
    MIP_Start_Options = Options.mip_start;
    if isfield(MIP_Start_Options, 'yalmip')
        ops = apply_option_values(ops, MIP_Start_Options.yalmip);
    end
    if isfield(MIP_Start_Options, Solver_Name)
        ops.(Solver_Name) = apply_option_values( ...
            ops.(Solver_Name), MIP_Start_Options.(Solver_Name));
    end
end

%% 4. 解析显式配置中的日志路径并准备目录
if isfield(Options.(Solver_Name), 'LogFile') && ...
        ~isempty(Options.(Solver_Name).LogFile)
    Log_File = char(Options.(Solver_Name).LogFile);
    Is_Absolute = startsWith(Log_File, filesep) || ...
        (ispc && numel(Log_File) >= 2 && Log_File(2) == ':');
    if ~Is_Absolute
        Project_Root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
        Log_File = fullfile(Project_Root, Log_File);
    end
    Log_Directory = fileparts(Log_File);
    if ~isempty(Log_Directory) && ~isfolder(Log_Directory)
        mkdir(Log_Directory);
    end
    ops.(Solver_Name).LogFile = Log_File;
end
end

function Target = apply_option_values(Target, Values)
%% 逐字段覆盖选项，保留目标结构中未被覆盖的设置。
Fields = fieldnames(Values);
for k = 1:numel(Fields)
    Field = Fields{k};
    Target.(Field) = Values.(Field);
end
end
