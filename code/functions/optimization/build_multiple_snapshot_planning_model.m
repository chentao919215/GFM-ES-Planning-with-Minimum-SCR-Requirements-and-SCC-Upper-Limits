function Model = build_multiple_snapshot_planning_model(mpc,CONF)
%% 构建新版论文MILP；运行约束沿用原有UC、DCOPF、储能和透视割。

CONF = normalize_multiple_snapshot_conf(CONF);
assert(strcmp(CONF.ModelVersion,'2026-10-23'), ...
    '新版构建器不接受legacy配置。');

%% 1. 整理输入参数
% u_GFL为已建GFL-WG节点状态，不作为优化变量。
u_GFL = CONF.u_GFL(:);
D     = CONF.TypicalDayCount;
K     = CONF.WindScenarioCount;
T     = CONF.PeriodCount;

%% 2. 构造网络数据
% 静态网络矩阵和逐时负荷、GFL-WG可用出力统一由network模块与CONF提供。
NET = build_multiple_snapshot_network(mpc, CONF);

N = NET.N;
G = NET.G;
L = NET.L;
N_GFM = CONF.GFM_Candidate_Count;
N_GFM_Module = CONF.GFM_MaxModulesPerCandidate;

% 候选节点检验与模块序号唯一性校验。
Module_Bus   = CONF.GFM_Module_Bus(:);
Module_Order = CONF.GFM_Module_Order(:);
[~, Candidate_Index] = ismember(Module_Bus, CONF.GFM_Module_Candidates(:));
Module_Linear_Index  = sub2ind([N_GFM, N_GFM_Module], Candidate_Index, Module_Order);
assert(numel(unique(Module_Linear_Index)) == CONF.GFM_Module_Count, ...
    '同一候选节点的模块序号必须唯一。');
Active_Module_Mask = false(N_GFM, N_GFM_Module);
Active_Module_Mask(Module_Linear_Index) = true;

% 元件-节点关联矩阵。
Generator_Location_Matrix  = NET.Generator_Location_Matrix;
GFM_Candidate_Location_Mat = CONF.GFM_Candidate_Loc_Mat;
GFM_Candidate_Module_Mat   = CONF.GFM_Candidate_Module_Mat;
Branch_From                = NET.Branch_From;
Branch_To                  = NET.Branch_To;
Branch_Matrix_From         = NET.Branch_Matrix_From;
Branch_Matrix_To           = NET.Branch_Matrix_To;

% 同步机发电成本与出力上下限参数。
Generator_Cost_Quadratic  = NET.Generator_Cost_Quadratic;
Generator_Cost_Linear   = NET.Generator_Cost_Linear;
Generator_Cost_Constant = NET.Generator_Cost_Constant;
Generator_P_Max = NET.Generator_P_Max;
Generator_P_Min = NET.Generator_P_Min;

% 同步机UC参数：正常爬坡速率、最小开停机时段数和单次启停成本。
Gen_Ramp_Up = CONF.Gen_Ramp_Up_MW_per_Hour(:);
Gen_Ramp_Down = CONF.Gen_Ramp_Down_MW_per_Hour(:);
Gen_Min_Up = CONF.Gen_Min_Up_Periods(:);
Gen_Min_Down = CONF.Gen_Min_Down_Periods(:);
Gen_Startup_Cost = CONF.Gen_Startup_Cost(:);
Gen_Shutdown_Cost = CONF.Gen_Shutdown_Cost(:);

% 线路、负荷与GFL-WG逐时参数。
Line_B_Series = NET.Line_B_Series;
Line_P_Max     = NET.Line_P_Max;
Line_Limited  = NET.Line_Limited;
P_Load        = NET.P_Load_Profile;
P_GFL_Available = NET.P_GFL_Available_Scenarios;
Scenario_Probability = NET.Wind_Scenario_Probabilities;

% GFM-ES模块参数。
GFM_Module_PN        = CONF.GFM_Module_PN(:);
GFM_Module_Energy    = CONF.GFM_Module_Rated_Energy(:);
GFM_Module_Cost_Conv = CONF.GFM_Module_Cost_Conv(:);

% 同一候选节点内各模块采用相同的充放电效率和SOC参数。
GFM_Charge_Efficiency    = CONF.GFM_Candidate_Charge_Efficiency(:);
GFM_Discharge_Efficiency = CONF.GFM_Candidate_Discharge_Efficiency(:);
GFM_SOC_Max              = CONF.GFM_Candidate_SOC_Max(:);
GFM_SOC_Initial          = CONF.GFM_Candidate_SOC_Initial(:);
GFM_SOC_Min              = CONF.GFM_Candidate_SOC_Min(:);
for n = 1:N_GFM
    idx = Candidate_Index == n;
    Duration = GFM_Module_Energy(idx)./GFM_Module_PN(idx);
    assert(~isempty(Duration) && all(isfinite(Duration)) && ...
        all(abs(Duration-Duration(1)) < 1e-9), ...
        '新版Section III-C要求同节点模块的额定时长一致。');
end

%% 3. 定义优化变量
% 逐时二进制变量：同步机运行状态以及启动、停机动作。
u_SG = binvar(G,D,T,'full');
u_SG_Start = binvar(G,D,T,'full');
u_SG_Stop  = binvar(G,D,T,'full');

% 跨典型日和时段共享的GFM-ES模块投建状态。
u_GFM_Module       = binvar(N_GFM,N_GFM_Module,'full');
u_GFM_Module_Table = reshape(u_GFM_Module(Module_Linear_Index),[],1);

% 候选节点聚合GFM-ES的逐场景逐时充放电状态，1表示充电，0表示放电。
% 当充电功率和放电功率均为零时，该状态可取任一值。
u_GFM_Ch = binvar(N_GFM,D,K,T,'full');

% 每个典型日分别构造安全状态：SCC采用日内并集，SCR采用日内交集。
u_SG_SCC = binvar(G,D,'full');
u_SG_SCR = binvar(G,D,'full');
% 场景相关连续运行变量，统一采用[元件,典型日,场景,时段]索引。
P_SG       = sdpvar(G,D,K,T,'full');
P_GFL      = sdpvar(N,D,K,T,'full');
P_GFL_Curt = sdpvar(N,D,K,T,'full');
P_GFM_Dis  = sdpvar(N_GFM,D,K,T,'full');
P_GFM_Ch   = sdpvar(N_GFM,D,K,T,'full');
E_GFM      = sdpvar(N_GFM,D,K,T,'full');
P_GFM      = sdpvar(N,D,K,T,'full');
P_SG_Norm  = sdpvar(G,D,K,T,'full');
theta      = sdpvar(N,D,K,T,'full');
P_Line     = sdpvar(L,D,K,T,'full');

% 同步机逐场景逐时运行成本辅助变量。
Cost_SG = sdpvar(G,D,K,T,'full');

%% 4. 建立约束
%% 4.1 规划约束(Manuscript Section III-A，式(28))
% 新版式(28)：直接限制跨典型日、场景及运行时段共享的模块投建变量。
C_Plan = [];
C_Plan = [C_Plan, u_GFM_Module(~Active_Module_Mask) == 0];
C_Plan = [C_Plan, sum(u_GFM_Module_Table) <= CONF.N_GFM_Module_Max];
% Manuscript未单列：由式(28)所选模块状态聚合节点功率、能量与模块数。
P_GFM_Installed = GFM_Candidate_Module_Mat* ...
    (GFM_Module_PN.*u_GFM_Module_Table);
E_GFM_Installed = GFM_Candidate_Module_Mat* ...
    (GFM_Module_Energy.*u_GFM_Module_Table);
N_GFM_Installed = GFM_Candidate_Module_Mat*u_GFM_Module_Table;
P_GFM_Candidate_Upper = GFM_Candidate_Module_Mat*GFM_Module_PN;
E_GFM_Initial = GFM_SOC_Initial.*E_GFM_Installed;

%% 4.2 基础潮流约束(Manuscript Section III-B，式(31)-(32))
C_Power_Flow = [];
Ref_Bus_Index = (mpc.bus(:,2) == 3);
Generator_P_Range = Generator_P_Max - Generator_P_Min;
assert(all(Generator_P_Range >= 0), '同步机出力上限不得小于下限。');

for d = 1:D
    for t = 1:T
        u_SG_d_t = u_SG(:,d,t);
        for k = 1:K
            P_SG_d_k_t = P_SG(:,d,k,t);
            P_GFL_d_k_t = P_GFL(:,d,k,t);
            P_GFL_Curt_d_k_t = P_GFL_Curt(:,d,k,t);
            P_GFM_Dis_d_k_t = P_GFM_Dis(:,d,k,t);
            P_GFM_Ch_d_k_t = P_GFM_Ch(:,d,k,t);
            P_GFM_d_k_t = P_GFM(:,d,k,t);
            P_SG_Norm_d_k_t = P_SG_Norm(:,d,k,t);
            Theta_d_k_t = theta(:,d,k,t);
            P_Line_d_k_t = P_Line(:,d,k,t);

            % Manuscript Section III-B，式(31)：节点有功功率平衡。
            P_SG_Node_d_k_t = Generator_Location_Matrix*P_SG_d_k_t;
            P_Inj_d_k_t = P_SG_Node_d_k_t + P_GFL_d_k_t + P_GFM_d_k_t - P_Load(:,d,t);
            C_Power_Flow = [C_Power_Flow, P_Inj_d_k_t == ...
                Branch_Matrix_From*P_Line_d_k_t - Branch_Matrix_To*P_Line_d_k_t];

            % Manuscript Section III-B，式(32)：同步机出力上下限。
            % 归一化关系供式(27)中的分段透视运行成本使用。
            C_Power_Flow = [C_Power_Flow, ...
                P_SG_d_k_t == Generator_P_Min.*u_SG_d_t + ...
                Generator_P_Range.*P_SG_Norm_d_k_t, ...
                P_SG_Norm_d_k_t >= 0, P_SG_Norm_d_k_t <= u_SG_d_t];

            % Manuscript Section III-B，式(32)：GFM-ES节点净注入。
            C_Power_Flow = [C_Power_Flow, ...
                P_GFM_d_k_t == GFM_Candidate_Location_Mat* ...
                (P_GFM_Dis_d_k_t-P_GFM_Ch_d_k_t)];

            % Manuscript Section III-B，式(32)：GFL-WG出力与弃风。
            P_GFL_Available_d_k_t = P_GFL_Available(:,d,k,t).*u_GFL;
            C_Power_Flow = [C_Power_Flow, ...
                P_GFL_d_k_t == P_GFL_Available_d_k_t-P_GFL_Curt_d_k_t, ...
                P_GFL_Curt_d_k_t >= 0, ...
                P_GFL_Curt_d_k_t <= P_GFL_Available_d_k_t];

            % Manuscript Section III-B：标准无损DC潮流、线路限额与参考相角。
            Delta_Theta_d_k_t = Theta_d_k_t(Branch_From) - Theta_d_k_t(Branch_To);
            C_Power_Flow = [C_Power_Flow, ...
                P_Line_d_k_t == Line_B_Series.*Delta_Theta_d_k_t];
            if any(Line_Limited)
                C_Power_Flow = [C_Power_Flow, ...
                    P_Line_d_k_t(Line_Limited) <= Line_P_Max(Line_Limited), ...
                    P_Line_d_k_t(Line_Limited) >= -Line_P_Max(Line_Limited)];
            end
            C_Power_Flow = [C_Power_Flow, Theta_d_k_t(Ref_Bus_Index) == 0];
        end
    end
end

%% 4.3 电源运行约束
%% 4.3.1 UC约束(Manuscript Section III-B，式(33)及标准UC约束)
% SG启停状态在同一典型日内跨风电场景共享。
C_UC = [];
for d = 1:D
    for t = 1:T
        u_SG_d_t = u_SG(:,d,t);
        Previous_t = mod(t-2,T)+1;
        u_SG_Previous = u_SG(:,d,Previous_t);
        u_SG_Start_d_t = u_SG_Start(:,d,t);
        u_SG_Stop_d_t = u_SG_Stop(:,d,t);
        Delta_t = CONF.PeriodDurations_Hours(t);
        Gen_Startup_Power = min(Generator_P_Max, Generator_P_Min+Gen_Ramp_Up*Delta_t);
        Gen_Shutdown_Power = min(Generator_P_Max, Generator_P_Min+Gen_Ramp_Down*Delta_t);

        % Manuscript Section III-B，式(33)：启停互斥与循环状态转换。
        C_UC = [C_UC, ...
            u_SG_Start_d_t+u_SG_Stop_d_t <= 1, ...
            u_SG_d_t-u_SG_Previous == u_SG_Start_d_t-u_SG_Stop_d_t];

        % 文档未单列公式：保留现有电压源在线约束，且不随风电场景复制。
        if CONF.Require_Source_Online
            C_UC = [C_UC, ...
                sum(u_SG_d_t) + sum(u_GFM_Module_Table) >= 1];
        end

        % Manuscript Section III-B引用的标准UC约束：逐场景同步机爬坡。
        for k = 1:K
            P_SG_d_k_t = P_SG(:,d,k,t);
            P_SG_Previous = P_SG(:,d,k,Previous_t);
            C_UC = [C_UC, ...
                P_SG_d_k_t-P_SG_Previous <= Gen_Ramp_Up*Delta_t.*u_SG_Previous + ...
                    Gen_Startup_Power.*u_SG_Start_d_t, ...
                P_SG_Previous-P_SG_d_k_t <= Gen_Ramp_Down*Delta_t.*u_SG_d_t + ...
                    Gen_Shutdown_Power.*u_SG_Stop_d_t];
        end
    end

    % Manuscript Section III-B引用的标准UC约束：循环最小开、停机时间。
    for g = 1:G
        for t = 1:T
            Up_Window = mod((t-Gen_Min_Up(g)+1:t)-1,T)+1;
            Down_Window = mod((t-Gen_Min_Down(g)+1:t)-1,T)+1;
            C_UC = [C_UC, ...
                sum(reshape(u_SG_Start(g,d,Up_Window),[],1)) <= u_SG(g,d,t), ...
                sum(reshape(u_SG_Stop(g,d,Down_Window),[],1)) <= 1-u_SG(g,d,t)]; %#ok<AGROW>
        end
    end
end

%% 4.3.2 GFM-ES约束(Manuscript Section III-C，式(34)-(35))
% 充放电状态与运行变量随风电场景变化，投建状态跨场景共享。
C_GFM_ES = [];
for d = 1:D
    for t = 1:T
        Delta_t = CONF.PeriodDurations_Hours(t);
        for k = 1:K
            P_GFM_Dis_d_k_t = P_GFM_Dis(:,d,k,t);
            P_GFM_Ch_d_k_t = P_GFM_Ch(:,d,k,t);
            E_GFM_d_k_t = E_GFM(:,d,k,t);
            u_GFM_Ch_d_k_t = u_GFM_Ch(:,d,k,t);

            % Manuscript Section III-C，式(34)：功率边界与充放电互斥。
            C_GFM_ES = [C_GFM_ES, ...
                u_GFM_Ch_d_k_t <= N_GFM_Installed, ...
                P_GFM_Ch_d_k_t >= 0, P_GFM_Ch_d_k_t <= P_GFM_Installed, ...
                P_GFM_Ch_d_k_t <= P_GFM_Candidate_Upper.*u_GFM_Ch_d_k_t, ...
                P_GFM_Dis_d_k_t >= 0, P_GFM_Dis_d_k_t <= P_GFM_Installed, ...
                P_GFM_Dis_d_k_t <= P_GFM_Candidate_Upper.*(1-u_GFM_Ch_d_k_t)];

            % Manuscript Section III-C，式(35)：能量递推与SOC边界。
            if t == 1
                E_GFM_Previous = E_GFM_Initial;
            else
                E_GFM_Previous = E_GFM(:,d,k,t-1);
            end
            C_GFM_ES = [C_GFM_ES, E_GFM_d_k_t == E_GFM_Previous + ...
                GFM_Charge_Efficiency.*P_GFM_Ch_d_k_t*Delta_t - ...
                P_GFM_Dis_d_k_t*Delta_t./GFM_Discharge_Efficiency, ...
                E_GFM_d_k_t >= GFM_SOC_Min.*E_GFM_Installed, ...
                E_GFM_d_k_t <= GFM_SOC_Max.*E_GFM_Installed];
        end
    end

    % Manuscript Section III-C，式(35)：典型日内首尾能量闭合。
    for k = 1:K
        C_GFM_ES = [C_GFM_ES, E_GFM(:,d,k,T) == E_GFM_Initial];
    end
end

%% 4.4 安全约束(新版Section II，式(18)-(26)及III-A，式(29)-(30))
% 并集残余电压直接给出SCC上界；交集仅重构GFL-WG节点电抗列。
[C_Security, Security] = add_converter_security_constraints( ...
    NET,CONF,u_SG,u_SG_SCC,u_SG_SCR,u_GFM_Module_Table);

%% 5. 构造目标函数(Manuscript Section III-A，式(27))
% 同步机单位时间运行成本采用归一化出力上的分段透视割近似。
Gen_Cost_Quad_Norm = Generator_Cost_Quadratic .* (Generator_P_Range.^2);
Gen_Cost_Lin_Norm = (2.*Generator_Cost_Quadratic.*Generator_P_Min + Generator_Cost_Linear) .* Generator_P_Range;
Gen_Cost_Const_Norm = Generator_Cost_Quadratic.*(Generator_P_Min.^2) + ...
    Generator_Cost_Linear.*Generator_P_Min + Generator_Cost_Constant;

C_Cost = [];
Cost_GEN = 0;
Cost_Curt = 0;
Cost_UC = 0;
for d = 1:D
    for t = 1:T
        % 启停动作跨场景共享，按典型日权重计费一次。
        Cost_UC = Cost_UC + CONF.TypicalDayWeights_Days(d)*( ...
            Gen_Startup_Cost'*u_SG_Start(:,d,t) + ...
            Gen_Shutdown_Cost'*u_SG_Stop(:,d,t));
        for k = 1:K
            C_Cost = [C_Cost, Cost_SG(:,d,k,t) >= 0];
            P_SG_Norm_d_k_t = P_SG_Norm(:,d,k,t);
            for xi = CONF.GenCostBreakpoints(:)'
                Tangent_Slope = 2.*Gen_Cost_Quad_Norm.*xi + Gen_Cost_Lin_Norm;
                Tangent_Intercept = Gen_Cost_Const_Norm - Gen_Cost_Quad_Norm.*(xi^2);
                C_Cost = [C_Cost, Cost_SG(:,d,k,t) >= ...
                    Tangent_Slope.*P_SG_Norm_d_k_t + ...
                    Tangent_Intercept.*u_SG(:,d,t)];
            end

            % 期望运行成本同时乘典型日权重、场景概率和时段持续时间。
            Expected_Weight = CONF.OperatingWeights_Hours(d,t)* ...
                Scenario_Probability(d,k);
            Cost_GEN = Cost_GEN + Expected_Weight*sum(Cost_SG(:,d,k,t));
            Cost_Curt = Cost_Curt + Expected_Weight* ...
                CONF.GFL_Curtailment_Cost_per_MWh*sum(P_GFL_Curt(:,d,k,t));
        end
    end
end

% 目标函数辅助约束先行，随后按Section III运行约束与Section II安全约束装配。
C = [C_Cost, C_Plan, C_Power_Flow, C_UC, C_GFM_ES, C_Security];

% 式(27)的GFM-ES年固定成本已包含年化投资和固定运维，各模块仅计一次。
Cost_GFM_Fixed = GFM_Module_Cost_Conv'*u_GFM_Module_Table;
Cost_Total_Annual = Cost_GEN + Cost_GFM_Fixed + Cost_Curt + Cost_UC;
Objective = Cost_Total_Annual/CONF.ObjectiveScale;


%% 6. 返回可独立检查的MILP模型，不调用求解器
Model = struct();
Model.Constraints = C;
Model.Objective = Objective;
Model.CONF = CONF;
Model.NET = NET;
Model.Security = Security;
Model.Module_Linear_Index = Module_Linear_Index;
Model.Variables.u_SG = u_SG;
Model.Variables.u_SG_Start = u_SG_Start;
Model.Variables.u_SG_Stop = u_SG_Stop;
Model.Variables.u_GFM_Module = u_GFM_Module;
Model.Variables.u_GFM_Module_Table = u_GFM_Module_Table;
Model.Variables.u_GFM_Ch = u_GFM_Ch;
Model.Variables.u_SG_SCC = u_SG_SCC;
Model.Variables.u_SG_SCR = u_SG_SCR;
Model.Variables.P_SG = P_SG;
Model.Variables.P_GFL = P_GFL;
Model.Variables.P_GFL_Curt = P_GFL_Curt;
Model.Variables.P_GFM_Dis = P_GFM_Dis;
Model.Variables.P_GFM_Ch = P_GFM_Ch;
Model.Variables.E_GFM = E_GFM;
Model.Variables.P_GFM = P_GFM;
Model.Variables.P_SG_Norm = P_SG_Norm;
Model.Variables.theta = theta;
Model.Variables.P_Line = P_Line;
Model.Variables.Cost_SG = Cost_SG;
Model.Cost.Cost_GEN = Cost_GEN;
Model.Cost.Cost_GFM_Fixed = Cost_GFM_Fixed;
Model.Cost.Cost_Curt = Cost_Curt;
Model.Cost.Cost_UC = Cost_UC;
Model.Cost.Cost_Total_Annual = Cost_Total_Annual;
end
