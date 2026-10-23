function [SCC_0,SCC_1,SCC_2,Value_P_Line,Value_Theta,Value_P_G,Value_P_GFL,Value_P_GFM,...
    SCR,Z_SCC_Val,Z_SCR_Val,Value_u_GFL,Value_u_G,Value_u_G_SCC,Value_u_G_SCR,...
    Value_Cost_CON,Value_Cost_GEN,Value_Cost_Total,Diagnostics,...
    Value_u_GFM_Module,Value_P_GFM_Dis,Value_P_GFM_Ch,Value_E_GFM,...
    Value_u_GFM_Ch,Value_P_GFL_Curt,Value_Cost_Curt,...
    Value_u_G_Start,Value_u_G_Stop,Value_Cost_UC, ...
    SCC_TimeResolved,SCR_TimeResolved,SecurityValidation] = ...
    solve_multiple_snapshot_planning(mpc,CONF)
%% 构建并求解新版论文模型，旧版仅通过显式legacy入口运行。
CONF = normalize_multiple_snapshot_conf(CONF);
if strcmp(CONF.ModelVersion,'legacy')
    [SCC_0,SCC_1,SCC_2,Value_P_Line,Value_Theta,Value_P_G,Value_P_GFL,Value_P_GFM, ...
        SCR,Z_SCC_Val,Z_SCR_Val,Value_u_GFL,Value_u_G,Value_u_G_SCC,Value_u_G_SCR, ...
        Value_Cost_CON,Value_Cost_GEN,Value_Cost_Total,Diagnostics, ...
        Value_u_GFM_Module,Value_P_GFM_Dis,Value_P_GFM_Ch,Value_E_GFM, ...
        Value_u_GFM_Ch,Value_P_GFL_Curt,Value_Cost_Curt, ...
        Value_u_G_Start,Value_u_G_Stop,Value_Cost_UC, ...
        SCC_TimeResolved,SCR_TimeResolved,SecurityValidation] = ...
        solve_multiple_snapshot_planning_legacy(mpc,CONF);
    return;
end
Model = build_multiple_snapshot_planning_model(mpc,CONF);
CONF = Model.CONF;
NET = Model.NET;
C = Model.Constraints;
Objective = Model.Objective;
Enable_SCC = CONF.Enable_SCC;
Enable_SCR = CONF.Enable_SCR;
Security_Constraint_Assembly = build_multiple_snapshot_security_constraint_assembly(CONF);
Module_Linear_Index = Model.Module_Linear_Index;
u_GFL = CONF.u_GFL(:);
u_SG = Model.Variables.u_SG;
u_SG_Start = Model.Variables.u_SG_Start;
u_SG_Stop = Model.Variables.u_SG_Stop;
u_GFM_Module = Model.Variables.u_GFM_Module;
u_GFM_Ch = Model.Variables.u_GFM_Ch;
u_SG_SCC = Model.Variables.u_SG_SCC;
u_SG_SCR = Model.Variables.u_SG_SCR;
P_SG = Model.Variables.P_SG;
P_GFL = Model.Variables.P_GFL;
P_GFL_Curt = Model.Variables.P_GFL_Curt;
P_GFM_Dis = Model.Variables.P_GFM_Dis;
P_GFM_Ch = Model.Variables.P_GFM_Ch;
E_GFM = Model.Variables.E_GFM;
P_GFM = Model.Variables.P_GFM;
theta = Model.Variables.theta;
P_Line = Model.Variables.P_Line;
Cost_GEN = Model.Cost.Cost_GEN;
Cost_GFM_Fixed = Model.Cost.Cost_GFM_Fixed;
Cost_Curt = Model.Cost.Cost_Curt;
Cost_UC = Model.Cost.Cost_UC;
Cost_Total_Annual = Model.Cost.Cost_Total_Annual;

%% 6. 调用求解器
% Gurobi原生选项从CONF.solver读取。
ops = build_multiple_snapshot_solver_options( ...
    CONF.solver, isfield(CONF, 'MIPStart'));
if isfield(CONF, 'MIPStart')
    assign(u_SG, CONF.MIPStart.u_G);
    assign(u_SG_Start, CONF.MIPStart.u_G_Start);
    assign(u_SG_Stop, CONF.MIPStart.u_G_Stop);
    assign(u_SG_SCC, CONF.MIPStart.u_G_SCC);
    assign(u_SG_SCR, CONF.MIPStart.u_G_SCR);
    assign(u_GFM_Module, CONF.MIPStart.u_GFM_Mod);
    assign(u_GFM_Ch, CONF.MIPStart.u_GFM_Ch);

end
sol = optimize(C, Objective, ops);

%% 7. 提取优化结果
Diagnostics = build_multiple_snapshot_diagnostics(sol);
% 标量变量数包含二进制变量，二进制变量数为其子集；约束数按标量分量计。
Model_Variable_Ids = getvariables(allvariables(C,Objective));
Binary_Variables = [u_SG(:); u_SG_Start(:); u_SG_Stop(:); ...
    u_GFM_Module(:); u_GFM_Ch(:); u_SG_SCC(:); u_SG_SCR(:); ...
    Model.Security.Segment(:)];
Diagnostics.Scalar_Variable_Count = numel(Model_Variable_Ids);
Diagnostics.Binary_Variable_Count = numel(intersect( ...
    Model_Variable_Ids,getvariables(Binary_Variables)));
Constraint_Model = struct(C);
Constraint_Clauses = Constraint_Model.clauses{1};
Diagnostics.Scalar_Constraint_Count = 0;
for Constraint_Index = 1:numel(Constraint_Clauses)
    Diagnostics.Scalar_Constraint_Count = ...
        Diagnostics.Scalar_Constraint_Count + ...
        numel(Constraint_Clauses{Constraint_Index}.data);
end
Diagnostics.objective_scale = CONF.ObjectiveScale;
% 部分YALMIP后端不返回目标值字段；有可行解时从已求解模型补齐。
if Diagnostics.has_incumbent && ~isfinite(Diagnostics.objective)
    Objective_Value = value(Objective);
    if isscalar(Objective_Value) && isfinite(Objective_Value)
        Diagnostics.objective = Objective_Value;
    end
end

Diagnostics.objective = Diagnostics.objective*CONF.ObjectiveScale;
Diagnostics.best_bound = Diagnostics.best_bound*CONF.ObjectiveScale;
% 求解器未返回MIP gap时，根据incumbent和best bound计算相对gap。
if Diagnostics.has_incumbent && ~isfinite(Diagnostics.mip_gap) && ...
        isfinite(Diagnostics.objective) && isfinite(Diagnostics.best_bound)
    Gap_Scale = max(abs(Diagnostics.objective), abs(Diagnostics.best_bound));
    if Gap_Scale > 0
        Diagnostics.mip_gap = abs(Diagnostics.objective - ...
            Diagnostics.best_bound)/Gap_Scale;
    elseif Diagnostics.objective == Diagnostics.best_bound
        Diagnostics.mip_gap = 0;
    else
        Diagnostics.mip_gap = Inf;
    end
end

Diagnostics.SecurityConstraintAssembly = Security_Constraint_Assembly;

if sol.problem == 0
    disp('Solver converged successfully.');
elseif Diagnostics.has_incumbent
    disp(['Solver stopped with code ' num2str(sol.problem), ...
        '; the best incumbent will be saved.']);
else
    error('Solver stopped with code %d without a feasible incumbent.', sol.problem);
end

Value_Cost_Total = value(Cost_Total_Annual);
Value_Cost_GEN = value(Cost_GEN);
Value_Cost_CON = value(Cost_GFM_Fixed);
Value_Cost_Curt = value(Cost_Curt);
Value_Cost_UC = value(Cost_UC);

% 场景相关结果保持[元件,典型日,场景,时段]四维索引结构。
Value_P_GFL = value(P_GFL);
Value_P_GFL_Curt = value(P_GFL_Curt);
Value_P_GFM_Dis = value(P_GFM_Dis);
Value_P_GFM_Ch = value(P_GFM_Ch);
Value_E_GFM = value(E_GFM);
Value_P_GFM = value(P_GFM);
Value_P_G = value(P_SG);
Value_Theta = value(theta);
Value_P_Line = value(P_Line);
Value_u_G = value(u_SG);
Value_u_G_Start = value(u_SG_Start);
Value_u_G_Stop = value(u_SG_Stop);

Value_u_GFL = u_GFL;
% 聚合状态统一由最终逐时SG状态复算；关闭约束时不读取未装配辅助变量。
Value_u_G_SCC = max(round(Value_u_G),[],3);
Value_u_G_SCR = min(round(Value_u_G),[],3);
Value_u_GFM_Module = value(u_GFM_Module);
Value_u_GFM_Ch = value(u_GFM_Ch);
Diagnostics.ModelVersion = '2026-10-23';

%% 8. 以新版方程独立复算聚合与逐时安全指标
Value_u_GFM_Module_Table = reshape(Value_u_GFM_Module(Module_Linear_Index),[],1);
[SCC_1,SCR,Z_SCC_Val,Z_SCR_Val,SCC_TimeResolved,SCR_TimeResolved, ...
    SecurityValidation] = calculate_converter_security_metrics( ...
    NET,CONF,Value_u_GFM_Module_Table,Value_u_G);
SecurityValidation.ConstraintAssembly = Security_Constraint_Assembly;
Diagnostics.SecurityPosthocRegression = struct();
if Enable_SCC
    Diagnostics.SecurityPosthocRegression.SCC_MaxAbsDifference_kA = ...
        finite_max_abs_difference(SCC_1(NET.Safety_Retained_Nodes,:), ...
        value(Model.Security.SCC)*CONF.Base_kA);
end
if Enable_SCR
    Diagnostics.SecurityPosthocRegression.Z_SCR_MaxAbsDifference_pu = ...
        finite_max_abs_difference(imag(Z_SCR_Val),value(Model.Security.X_SCR));
end
SCC_0 = [];
SCC_2 = [];
end

function Maximum = finite_max_abs_difference(A,B)
Difference = abs(A-B);
Difference = Difference(isfinite(Difference));
if isempty(Difference)
    Maximum = NaN;
else
    Maximum = max(Difference);
end
end
