function [SCC_0,SCC_1,SCC_2,Value_P_Line,Value_Theta,Value_P_G,Value_P_GFL,Value_P_GFM,...
    SCR,Z_SCC_Val,Z_SCR_Val,Value_u_GFL,Value_u_G,Value_u_G_SCC,Value_u_G_SCR,...
    Value_Cost_CON,Value_Cost_GEN,Value_Cost_Total,Diagnostics,...
    Value_u_GFM_Module,Value_P_GFM_Dis,Value_P_GFM_Ch,Value_E_GFM,...
    Value_u_GFM_Ch,Value_P_GFL_Curt,Value_Cost_Curt,...
    Value_u_G_Start,Value_u_G_Stop,Value_Cost_UC, ...
    SCC_TimeResolved,SCR_TimeResolved,SecurityValidation] = ...
    solve_multiple_snapshot_planning(mpc,CONF)
%% 构建并求解场景随机多时段模块化GFM-ES配置优化模型
% GFM-ES投建和同步机组合状态跨风电场景共享，其余运行变量按场景补救。
% 安全状态仍仅在各典型日内跨时段聚合，安全网络与McCormick变量不带场景维。

CONF = normalize_multiple_snapshot_conf(CONF);

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
NS = NET.Safety_N;
NGFL = NET.Safety_GFL_Count;
M_GFM = CONF.GFM_Module_Count;
N_GFM = CONF.GFM_Candidate_Count;
N_GFM_Module = CONF.GFM_MaxModulesPerCandidate;
C_Configuration = CONF.GFM_Config_Count;
Safety_Nodes = NET.Safety_Retained_Nodes;
GFL_Original_Nodes = NET.Safety_GFL_Original_Nodes;
GFL_Reduced_Indices = NET.Safety_GFL_Reduced_Indices;

% 候选节点检验与模块序号唯一性校验。
Module_Bus   = CONF.GFM_Module_Bus(:);
Module_Order = CONF.GFM_Module_Order(:);
[~, Candidate_Index] = ismember(Module_Bus, CONF.GFM_Module_Candidates(:));
Module_Linear_Index  = sub2ind([N_GFM, N_GFM_Module], Candidate_Index, Module_Order);
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
Delta_Y_Abs_Module       = NET.Delta_Y_Abs_Module;

% 同一候选节点内各模块采用相同的充放电效率和SOC参数。
GFM_Charge_Efficiency    = CONF.GFM_Candidate_Charge_Efficiency(:);
GFM_Discharge_Efficiency = CONF.GFM_Candidate_Discharge_Efficiency(:);
GFM_SOC_Max              = CONF.GFM_Candidate_SOC_Max(:);
GFM_SOC_Initial          = CONF.GFM_Candidate_SOC_Initial(:);
GFM_SOC_Min              = CONF.GFM_Candidate_SOC_Min(:);

% Manuscript Section II-B：离线电抗元素上下界用于精确McCormick线性化。
Z_Bounds = calculate_impedance_bounds(NET, CONF);

%% 3. 定义优化变量
% 逐时二进制变量：同步机运行状态以及启动、停机动作。
u_SG = binvar(G,D,T,'full');
u_SG_Start = binvar(G,D,T,'full');
u_SG_Stop  = binvar(G,D,T,'full');

% 跨典型日和时段共享的GFM-ES模块投建状态。
u_GFM_Module       = binvar(N_GFM,N_GFM_Module,'full');
u_GFM_Module_Table = u_GFM_Module(Module_Linear_Index);
Lambda_Configuration   = binvar(C_Configuration,1,'full');

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

% 各典型日分别重构安全电抗所需列；SCC需要全部安全节点列，数值上形成
% 完整矩阵，SCR仅需要GFL-WG节点列。SCC逐典型日显式施加对称性。
Z_SCC_Real = sdpvar(NS,NS,D,'full');
Z_SCC_Imag = sdpvar(NS,NS,D,'full');
Z_SCR_Real = sdpvar(NS,NGFL,D,'full');
Z_SCR_Imag = sdpvar(NS,NGFL,D,'full');

% Manuscript Section II-C同步机交集工况的残余电压与LVRT反馈变量。
V_F       = sdpvar(NS,NS,D,'full');
V_F_0     = sdpvar(NS,NGFL,D,'full');
V_F_Lin   = sdpvar(NS,NGFL,D,'full');
V_F_Sat   = sdpvar(NS,NGFL,D,'full');
Delta_F_0 = binvar(NS,NGFL,D,'full');
Delta_F_Lin = binvar(NS,NGFL,D,'full');
Delta_F_Sat = binvar(NS,NGFL,D,'full');
Delta_I_GFL = sdpvar(NS,NGFL,D,'full');
Zeta_SG_V = sdpvar(G,NS,NS,D,'full');
Zeta_GFM_V = sdpvar(M_GFM,NS,NS,D,'full');
Chi_GFL = sdpvar(C_Configuration,NS,NGFL,D,'full');

% 短路电流水平保守上界工况的阻抗重构与SCC辅助变量。
W_SGZ_X_SCC  = sdpvar(G,NS,D,'full');
W_SGZ_R_SCC  = sdpvar(G,NS,D,'full');
W_GFMZ_X_SCC = sdpvar(M_GFM,NS,D,'full');
W_GFMZ_R_SCC = sdpvar(M_GFM,NS,D,'full');
W_GFM_SCC    = sdpvar(M_GFM,D,'full');

% 电压支撑强度保守下界工况的阻抗重构辅助变量。
W_SGZ_X_SCR  = sdpvar(G,NGFL,D,'full');
W_SGZ_R_SCR  = sdpvar(G,NGFL,D,'full');
W_GFMZ_X_SCR = sdpvar(M_GFM,NGFL,D,'full');
W_GFMZ_R_SCR = sdpvar(M_GFM,NGFL,D,'full');

% 同步机逐场景逐时运行成本辅助变量。
Cost_SG = sdpvar(G,D,K,T,'full');

%% 4. 建立约束
%% 4.1 规划约束(Manuscript Section III-A，式(25))
% 可行模块配置离线枚举；以下在线约束选择唯一配置并映射模块投建状态。
C_Plan = [];
C_Plan = [C_Plan, u_GFM_Module(~Active_Module_Mask) == 0];
C_Plan = [C_Plan, sum(u_GFM_Module_Table) <= CONF.N_GFM_Module_Max];
Configuration_Allowed = logical(Z_Bounds.Configuration_Allowed(:));
C_Plan = [C_Plan, sum(Lambda_Configuration) == 1, ...
    Lambda_Configuration(~Configuration_Allowed) == 0, ...
    u_GFM_Module_Table == CONF.GFM_Config_Module_Matrix.'*Lambda_Configuration];

% Manuscript未单列：由式(25)所选模块状态聚合节点功率、能量与模块数。
P_GFM_Installed = GFM_Candidate_Module_Mat* ...
    (GFM_Module_PN.*u_GFM_Module_Table);
E_GFM_Installed = GFM_Candidate_Module_Mat* ...
    (GFM_Module_Energy.*u_GFM_Module_Table);
N_GFM_Installed = GFM_Candidate_Module_Mat*u_GFM_Module_Table;
P_GFM_Candidate_Upper = GFM_Candidate_Module_Mat*GFM_Module_PN;
E_GFM_Initial = GFM_SOC_Initial.*E_GFM_Installed;

% 文档未单列公式：保留现有模块顺序约束以减少等价解。
if CONF.GFM_Module_Sequential
    Unique_Module_Bus = unique(Module_Bus, 'stable');
    for k_Bus = 1:numel(Unique_Module_Bus)
        idx = find(Module_Bus == Unique_Module_Bus(k_Bus));
        [~, Order_Index] = sort(Module_Order(idx));
        idx = idx(Order_Index);
        if numel(idx) > 1
            C_Plan = [C_Plan, ...
                u_GFM_Module_Table(idx(1:end-1)) >= u_GFM_Module_Table(idx(2:end))]; %#ok<AGROW>
        end
    end
end

%% 4.2 基础潮流约束(Manuscript Section III-B，式(26)-(27))
C_Power_Flow = [];
Ref_Bus_Index = (mpc.bus(:,2) == 3);
Generator_P_Range = Generator_P_Max - Generator_P_Min;
Gen_Prange_Inv = spdiags(1./Generator_P_Range,0,G,G);

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

            % Manuscript Section III-B，式(26)：节点有功功率平衡。
            P_SG_Node_d_k_t = Generator_Location_Matrix*P_SG_d_k_t;
            P_Inj_d_k_t = P_SG_Node_d_k_t + P_GFL_d_k_t + P_GFM_d_k_t - P_Load(:,d,t);
            C_Power_Flow = [C_Power_Flow, P_Inj_d_k_t == ...
                Branch_Matrix_From*P_Line_d_k_t - Branch_Matrix_To*P_Line_d_k_t];

            % Manuscript Section III-B，式(27)：同步机出力上下限。
            % 归一化关系供式(24)中的分段透视运行成本使用。
            C_Power_Flow = [C_Power_Flow, ...
                P_SG_Norm_d_k_t == Gen_Prange_Inv* ...
                (P_SG_d_k_t-Generator_P_Min.*u_SG_d_t), ...
                P_SG_Norm_d_k_t >= 0, P_SG_Norm_d_k_t <= u_SG_d_t];

            % Manuscript Section III-B，式(27)：GFM-ES节点净注入。
            C_Power_Flow = [C_Power_Flow, ...
                P_GFM_d_k_t == GFM_Candidate_Location_Mat* ...
                (P_GFM_Dis_d_k_t-P_GFM_Ch_d_k_t)];

            % Manuscript Section III-B，式(27)：GFL-WG出力与弃风。
            P_GFL_Available_d_k_t = P_GFL_Available(:,d,k,t).*u_GFL;
            C_Power_Flow = [C_Power_Flow, ...
                P_GFL_d_k_t == P_GFL_Available_d_k_t-P_GFL_Curt_d_k_t, ...
                P_GFL_Curt_d_k_t >= 0, ...
                P_GFL_Curt_d_k_t >= P_GFL_Available_d_k_t-CONF.PN_GFL_Node, ...
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
%% 4.3.1 UC约束(Manuscript Section III-B，式(28)及标准UC约束)
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

        % Manuscript Section III-B，式(28)：启停互斥与循环状态转换。
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

%% 4.3.2 GFM-ES约束(Manuscript Section III-C，式(29)-(30))
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

            % Manuscript Section III-C，式(29)：功率边界与充放电互斥。
            C_GFM_ES = [C_GFM_ES, ...
                u_GFM_Ch_d_k_t <= N_GFM_Installed, ...
                P_GFM_Ch_d_k_t >= 0, P_GFM_Ch_d_k_t <= P_GFM_Installed, ...
                P_GFM_Ch_d_k_t <= P_GFM_Candidate_Upper.*u_GFM_Ch_d_k_t, ...
                P_GFM_Dis_d_k_t >= 0, P_GFM_Dis_d_k_t <= P_GFM_Installed, ...
                P_GFM_Dis_d_k_t <= P_GFM_Candidate_Upper.*(1-u_GFM_Ch_d_k_t)];

            % Manuscript Section III-C，式(30)：能量递推与SOC边界。
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

    % Manuscript Section III-C，式(30)：典型日内首尾能量闭合。
    for k = 1:K
        C_GFM_ES = [C_GFM_ES, E_GFM(:,d,k,T) == E_GFM_Initial];
    end
end

%% 4.4 安全约束
%% 4.4.1 聚合安全状态约束(Manuscript Section II-A，式(1)-(2))
% 安全网络按Section II-B离线降阶；在线约束按典型日构造并集与交集状态。
C_Aggregate = [];
for d = 1:D
    u_SG_Sum_d     = zeros(G,1);
    u_SG_Off_Sum_d = zeros(G,1);
    for t = 1:T
        u_SG_d_t = u_SG(:,d,t);
        C_Aggregate = [C_Aggregate, u_SG_SCC(:,d) >= u_SG_d_t];
        C_Aggregate = [C_Aggregate, u_SG_SCR(:,d) <= u_SG_d_t];
        u_SG_Sum_d     = u_SG_Sum_d + u_SG_d_t;
        u_SG_Off_Sum_d = u_SG_Off_Sum_d + (1-u_SG_d_t);
    end

    % Manuscript式(1)：典型日同步机状态并集，用于SCC上界。
    C_Aggregate = [C_Aggregate, u_SG_SCC(:,d) <= u_SG_Sum_d];

    % Manuscript式(2)：典型日同步机状态交集，用于LVRT与SCR下界。
    C_Aggregate = [C_Aggregate, 1-u_SG_SCR(:,d) <= u_SG_Off_Sum_d];
end

%% 4.4.2 电抗列重构约束(Manuscript Section II-B，式(3)-(7))
C_Impedance_SCC = [];
C_Impedance_SCR = [];
C_McCormick_Impedance_SCC = [];
C_McCormick_Impedance_SCR = [];
for d = 1:D
    Z_SCC_Real_d = Z_SCC_Real(:,:,d);
    Z_SCC_Imag_d = Z_SCC_Imag(:,:,d);
    Z_SCR_Real_d = Z_SCR_Real(:,:,d);
    Z_SCR_Imag_d = Z_SCR_Imag(:,:,d);

    % Manuscript式(6)-(7)：重构SCC所需的全部安全节点电抗列。
    % 实现保留等价复数变量外壳，安全网络无损时其实部由约束固定为零。
    C_Impedance_SCC = [C_Impedance_SCC, ...
        Z_SCC_Real_d == Z_SCC_Real_d.', ...
        Z_SCC_Imag_d == Z_SCC_Imag_d.'];
    [C_Impedance_SCC_d, C_McCormick_Impedance_SCC_d] = ...
        add_impedance_reconstruction_constraints( ...
        NET, CONF, Z_Bounds.SCC, u_SG_SCC(:,d), u_GFM_Module_Table, ...
        Z_SCC_Real_d, Z_SCC_Imag_d, W_SGZ_X_SCC(:,:,d), ...
        W_SGZ_R_SCC(:,:,d), W_GFMZ_X_SCC(:,:,d), ...
        W_GFMZ_R_SCC(:,:,d), (1:NS).');
    C_Impedance_SCC = [C_Impedance_SCC, C_Impedance_SCC_d];
    C_McCormick_Impedance_SCC = [C_McCormick_Impedance_SCC, ...
        C_McCormick_Impedance_SCC_d];

    % Manuscript式(6)-(7)：仅重构SCR所需的GFL-WG节点电抗列。
    [C_Impedance_SCR_d, C_McCormick_Impedance_SCR_d] = ...
        add_impedance_reconstruction_constraints( ...
        NET, CONF, Z_Bounds.SCR, u_SG_SCR(:,d), u_GFM_Module_Table, ...
        Z_SCR_Real_d, Z_SCR_Imag_d, W_SGZ_X_SCR(:,:,d), ...
        W_SGZ_R_SCR(:,:,d), W_GFMZ_X_SCR(:,:,d), ...
        W_GFMZ_R_SCR(:,:,d), GFL_Reduced_Indices);
    C_Impedance_SCR = [C_Impedance_SCR, C_Impedance_SCR_d];
    C_McCormick_Impedance_SCR = [C_McCormick_Impedance_SCR, ...
        C_McCormick_Impedance_SCR_d];
end

%% 4.4.3 GFL-WG故障电压与LVRT增量电流约束(Manuscript Section II-C)
% 式(13)-(19)及Appendix-B：交集状态残余电压与三段式LVRT；阈值和
% 饱和增量电流上限在参数加载阶段校验。
[C_LVRT, C_McCormick_LVRT] = add_gfl_lvrt_residual_constraints( ...
    NET, CONF, u_SG_SCR, u_GFM_Module_Table, V_F, V_F_0, V_F_Lin, ...
    V_F_Sat, Delta_F_0, Delta_F_Lin, Delta_F_Sat, Delta_I_GFL, ...
    Zeta_SG_V, Zeta_GFM_V);

%% 4.4.4 SCC上界约束(Manuscript Section II-C，式(15)-(21))
C_SCC = [];
C_Fault_Transfer = [];
C_McCormick_SCC = [];
Phi_GFL = [];

% 式(17)对应离线并集-实际状态枚举；在线排除奇异配置-状态组合。
C_SCC = [C_SCC, add_forbidden_state_pair_constraints( ...
    Z_Bounds.Invalid_State_Pairs, ...
    Z_Bounds.State_Catalog.SynchronousStates, Lambda_Configuration, ...
    u_SG_SCC, u_SG)];

% Manuscript式(17)、(20)：配置选择与LVRT电流的精确分解辅助变量。
for d = 1:D
    for n = 1:NS
        for GFL_Index = 1:NGFL
            Delta_I_Upper = CONF.Delta_I_GFL_pu_Node( ...
                GFL_Original_Nodes(GFL_Index));
            Chi_Vec = Chi_GFL(:,n,GFL_Index,d);
            C_Fault_Transfer = [C_Fault_Transfer, ...
                Chi_Vec >= 0, ...
                Chi_Vec <= Delta_I_Upper*Lambda_Configuration, ...
                sum(Chi_Vec) == Delta_I_GFL(n,GFL_Index,d)]; %#ok<AGROW>
        end
    end
end

u_GFL_Safety = u_GFL(Safety_Nodes);
CONF_Safety = CONF;
CONF_Safety.GFM_Module_Loc_Mat = NET.Safety_GFM_Module_Location_Matrix;
CONF_Safety.I_limit = CONF.I_limit(Safety_Nodes);
CONF_Safety.Delta_I_GFL_pu_Node = CONF.Delta_I_GFL_pu_Node(Safety_Nodes);
X_Diag_L = diag(Z_Bounds.SCC.Imag_Min);
X_Diag_U = diag(Z_Bounds.SCC.Imag_Max);

for d = 1:D
    Z_SCC_Imag_d = Z_SCC_Imag(:,:,d);
    X_Diag_SCC_d = diag(Z_SCC_Imag_d);
    Phi_GFL_d = [];
    for n = 1:NS
        Phi_n = 0;
        for GFL_Index = 1:NGFL
            Phi_n = Phi_n + ...
                Z_Bounds.Tau_GFL_Scaled(:,n,GFL_Index).' * ...
                Chi_GFL(:,n,GFL_Index,d);
        end
        Phi_GFL_d = [Phi_GFL_d; Phi_n]; %#ok<AGROW>
    end
    Phi_GFL = [Phi_GFL, Phi_GFL_d]; %#ok<AGROW>

    % Manuscript式(20)-(21)及Appendix-C：聚合SCC保守上界。
    [C_SCC_d, C_McCormick_SCC_d] = add_short_circuit_current_constraints( ...
        CONF_Safety, u_GFL_Safety, u_GFM_Module_Table, W_GFM_SCC(:,d), ...
        X_Diag_SCC_d, Delta_Y_Abs_Module, X_Diag_L, X_Diag_U, Phi_GFL_d);
    C_SCC = [C_SCC, C_SCC_d];
    C_McCormick_SCC = [C_McCormick_SCC, C_McCormick_SCC_d];
end

%% 4.4.5 SCR下界约束(Manuscript Section II-D，式(23))
C_SCR = [];
X_Diag_SCR = [];

% 文档未单列在线公式：禁止离线预处理标记的无效配置-交集状态组合。
C_SCR = [C_SCR, add_forbidden_configuration_state_constraints( ...
    Z_Bounds.Invalid_SCR_States, ...
    Z_Bounds.State_Catalog.SynchronousStates, Lambda_Configuration, u_SG_SCR)];

SCR_Diagonal_Indices = sub2ind([NS,NGFL], ...
    GFL_Reduced_Indices,(1:NGFL).');
% 式(23)采用GFL-WG场站额定功率，不使用逐时可用出力或实际出力。
PN_GFL_Rated_PU_Node = CONF.PN_GFL_pu_Node;
PN_GFL_Rated_PU = PN_GFL_Rated_PU_Node(GFL_Original_Nodes);
for d = 1:D
    Z_SCR_Imag_d = Z_SCR_Imag(:,:,d);

    X_Diag_SCR_d = Z_SCR_Imag_d(SCR_Diagonal_Indices);
    X_Diag_SCR = [X_Diag_SCR, X_Diag_SCR_d]; %#ok<AGROW>

    % Manuscript式(23)及Appendix-A：典型日交集状态的经典SCR下界。
    C_SCR = [C_SCR, add_classic_scr_constraints( ...
        CONF, ones(NGFL,1), X_Diag_SCR_d, PN_GFL_Rated_PU)];

    % 文档未单列公式：保留现有安全网络电压源在线约束。
    if CONF.Require_Source_Online
        C_SCR = [C_SCR, sum(u_SG_SCR(:,d)) + sum(u_GFM_Module_Table) >= 1];
    end
end

%% 4.5 McCormick线性化约束(Manuscript Section II-B与II-C)
% 汇总式(7)、式(18)及式(21)实现中二元变量与有界连续变量的精确乘积。
C_McCormick = [C_McCormick_Impedance_SCC, ...
    C_McCormick_Impedance_SCR, C_McCormick_LVRT, C_McCormick_SCC];

%% 5. 构造目标函数(Manuscript Section III-A，式(24))
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
C = [C_Cost, C_Plan, C_Power_Flow, C_UC, C_GFM_ES, ...
    C_Aggregate, C_Impedance_SCC, C_Impedance_SCR, C_LVRT, ...
    C_Fault_Transfer, C_SCC, C_SCR, C_McCormick];

% 式(24)的GFM-ES年固定成本已包含年化投资和固定运维，各模块仅计一次。
Cost_GFM_Fixed = GFM_Module_Cost_Conv'*u_GFM_Module_Table;
Cost_Total_Annual = Cost_GEN + Cost_GFM_Fixed + Cost_Curt + Cost_UC;
Objective = Cost_Total_Annual/CONF.ObjectiveScale;

%% 6. 调用求解器
% 求解器参数由build_copt_options统一设置。
ops = build_copt_options(CONF.Solver);
if isfield(CONF, 'MIPStart')
    assign(u_SG, CONF.MIPStart.u_G);
    assign(u_SG_Start, CONF.MIPStart.u_G_Start);
    assign(u_SG_Stop, CONF.MIPStart.u_G_Stop);
    assign(u_SG_SCC, CONF.MIPStart.u_G_SCC);
    assign(u_SG_SCR, CONF.MIPStart.u_G_SCR);
    assign(u_GFM_Module, CONF.MIPStart.u_GFM_Mod);
    assign(u_GFM_Ch, CONF.MIPStart.u_GFM_Ch);
    ops.usex0 = 1;
    ops.warmstart = 1;
    % 当前MIP start仅初始化部分变量；COPT需要启用子MIP补全部分初始解。
    ops.copt.MipStartMode = 2;
end
sol = optimize(C, Objective, ops);
COPT_Log_Source = '';
Results_Directory = '';
if ops.verbose > 0
    % YALMIP的COPT适配器将日志写到当前目录下的copt.log。
    COPT_Log_Source = fullfile(pwd, 'copt.log');
    Project_Root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
    Results_Directory = fullfile(Project_Root, 'results');
    if ~isfolder(Results_Directory)
        mkdir(Results_Directory);
    end
end
if ~isempty(COPT_Log_Source) && isfile(COPT_Log_Source)
    % 为保持已有结果日志路径兼容，沿用原日志文件名。
    movefile(COPT_Log_Source, fullfile(Results_Directory, 'gurobi_run.log'), 'f');
end

%% 7. 提取优化结果
Diagnostics = build_multiple_snapshot_diagnostics(sol);
Diagnostics.objective_scale = CONF.ObjectiveScale;
Diagnostics.objective = Diagnostics.objective*CONF.ObjectiveScale;
Diagnostics.best_bound = Diagnostics.best_bound*CONF.ObjectiveScale;

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
Value_u_G_SCC = value(u_SG_SCC);
Value_u_G_SCR = value(u_SG_SCR);
Value_u_GFM_Module = value(u_GFM_Module);
Value_u_GFM_Ch = value(u_GFM_Ch);
Value_Lambda_Configuration = value(Lambda_Configuration);
Diagnostics.ConfigurationSelection = Value_Lambda_Configuration;
Diagnostics.ConfigurationAllowed = Z_Bounds.Configuration_Allowed;

% 阻抗矩阵在模型中经过CONF.KZ缩放，输出时还原到原始标幺尺度。
Z_SCC_Val = value(Z_SCC_Real)/CONF.KZ + 1i*value(Z_SCC_Imag)/CONF.KZ;
Z_SCR_Val = value(Z_SCR_Real)/CONF.KZ + 1i*value(Z_SCR_Imag)/CONF.KZ;

X_Diag_SCR_Val = value(X_Diag_SCR)/CONF.KZ;
SCR = zeros(N,D);
for d = 1:D
    SCR(GFL_Original_Nodes,d) = calculate_classic_scr( ...
        X_Diag_SCR_Val(:,d),ones(NGFL,1),PN_GFL_Rated_PU);
end

%% 8. 计算短路电流指标
% SCC_1为典型日SG并集工况的聚合保守上界。旧SCC_0/SCC_2接口保留，
% 但本结果路径不再计算或保存；实际逐时后验结果在下一段独立重构。
Value_u_GFM_Module_Table = Value_u_GFM_Module(Module_Linear_Index);
Value_Phi_GFL = value(Phi_GFL);
[SCC_0, SCC_1, SCC_2] = calculate_short_circuit_currents( ...
    NET, CONF, Value_u_GFM_Module_Table, u_GFL, Value_u_G_SCC, ...
    Z_SCC_Val, Value_Phi_GFL, false);

%% 9. 基于最终投建方案和实际逐时SG状态进行独立安全指标复算
% 本步骤不读取SCC/SCR约束辅助变量，因此与优化模型是否启用相应安全
% 约束无关。逐时数组顺序为[时段,典型日,安全节点]。
[SCC_TimeResolved, SCR_TimeResolved] = ...
    calculate_time_resolved_security_metrics( ...
    NET, CONF, Value_u_GFM_Module_Table, u_GFL, Value_u_G);
SecurityValidation = check_aggregated_security_conservatism( ...
    SCC_1, SCR, SCC_TimeResolved, SCR_TimeResolved, CONF);

end
