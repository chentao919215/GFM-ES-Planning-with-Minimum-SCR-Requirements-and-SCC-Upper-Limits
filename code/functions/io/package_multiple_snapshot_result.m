function Result = package_multiple_snapshot_result(SCC_0,SCC_1,SCC_2,P_Line,theta,P_G,P_GFL,P_GFM,...
    SCR,Z_SCC,Z_SCR,u_GFL,u_G,u_G_SCC,u_G_SCR,Cost_CON,Cost_GEN,Cost_Total,...
    Solve_Time,CONF,Diagnostics,u_GFM_Module,P_GFM_Dis,P_GFM_Ch,E_GFM,u_GFM_Ch,...
    P_GFL_Curt,Cost_Curt,u_G_Start,u_G_Stop,Cost_UC)
%% 本函数功能是将多时段求解输出整理为统一结果结构体。

Cost = struct();
Cost.Total = Cost_Total;
Cost.GEN   = Cost_GEN;
Cost.CON   = Cost_CON;
Cost.Curt  = Cost_Curt;
Cost.UC    = Cost_UC;
Cost.Unit  = 'annual';

Result = struct();
Result.SCC_0       = SCC_0;
Result.SCC_1       = SCC_1;
Result.SCC_2       = SCC_2;
Result.P_Line      = P_Line;
Result.theta       = theta;
Result.P_G         = P_G;
Result.P_GFL       = P_GFL;
% GFL-WG场景可用出力、实际出力和弃风功率严格分开保存。
Result.P_GFL_Available = CONF.P_GFL_Available_Scenarios;
Result.P_GFL_Curt  = P_GFL_Curt;
Result.P_GFM       = P_GFM;
Result.SCR         = SCR;
% SCC、SCR和两类阻抗均以典型日为末维；Z_SCR的列仅对应已建GFL-WG节点。
Result.Z_SCC       = Z_SCC;
Result.Z_SCR       = Z_SCR;
Result.u_GFL       = u_GFL;
Result.u_G         = u_G;
% 同步机状态及启停动作按[机组,典型日,时段]保存并跨场景共享。
Result.u_G_Start   = u_G_Start;
Result.u_G_Stop    = u_G_Stop;
Result.u_G_SCC     = u_G_SCC;
Result.u_G_SCR     = u_G_SCR;
Result.u_GFM_Mod   = u_GFM_Module;
Result.lambda_c = Diagnostics.ConfigurationSelection;
Result.GFM_Config_Module_Status = Diagnostics.ConfigurationModuleStatus;
Result.GFM_Config_Allowed = Diagnostics.ConfigurationAllowed;
Result.GFM_Config_Candidate_Status = Diagnostics.ConfigurationCandidateStatus;
% 场景相关储能运行结果按[候选节点,典型日,场景,时段]保存，
% P_GFM为[节点,典型日,场景,时段]全节点净注入功率。
Result.P_GFM_Dis   = P_GFM_Dis;
Result.P_GFM_Ch    = P_GFM_Ch;
Result.E_GFM       = E_GFM;
Result.u_GFM_Ch    = u_GFM_Ch;
Result.Cost        = Cost;
Result.solve_time  = Solve_Time;
Result.CONF        = CONF;
Result.Diagnostics = Diagnostics;

% 保存场景轴含义和概率，避免下游输出将场景维误认为时段维。
Wind_Scenarios = struct();
Wind_Scenarios.Count = CONF.WindScenarioCount;
Wind_Scenarios.Names = CONF.WindScenarioNames;
Wind_Scenarios.Probabilities = CONF.WindScenarioProbabilities;
Wind_Scenarios.ScaleFactors = CONF.WindScenarioScaleFactors;
Wind_Scenarios.GenerationMode = CONF.WindScenarioGenerationMode;
Wind_Scenarios.BaseScenarioIndex = CONF.WindScenarioBaseIndex;
Wind_Scenarios.AvailablePowerDimensions = ...
    {'node','typical_day','wind_scenario','period'};
Result.WindScenarios = Wind_Scenarios;

Dimensions = struct();
Dimensions.SharedUC = {'generator','typical_day','period'};
Dimensions.ScenarioGeneratorDispatch = ...
    {'generator','typical_day','wind_scenario','period'};
Dimensions.ScenarioNodeOperation = ...
    {'node','typical_day','wind_scenario','period'};
Dimensions.ScenarioGFMOperation = ...
    {'gfm_candidate','typical_day','wind_scenario','period'};
Dimensions.SafetyState = {'generator','typical_day'};
Dimensions.SCC = {'node','typical_day'};
Result.Dimensions = Dimensions;

% 三组SCC采用相同的原始节点顺序、基准值和kA单位。
SCC_Definition = struct();
SCC_Definition.SCC_0 = '全同步机基准结果';
SCC_Definition.SCC_1 = '优化模型计算结果';
SCC_Definition.SCC_2 = '后验复算结果';
SCC_Definition.Node_Order = 'MATPOWER原始节点顺序';
SCC_Definition.Dimension_Order = {'node','typical_day'};
SCC_Definition.Unit = 'kA';
SCC_Definition.Base_Current_kA = CONF.Base_kA;
SCC_Definition.SCC_1_Non_Safety_Node_Value = 0;
Result.SCC_Definition = SCC_Definition;

% 显式保存原节点与降阶节点映射，便于解释两类阻抗结果的行、列索引。
Safety_Network = struct();
Safety_Network.RetainedOriginalNodes = CONF.Safety_Retained_Nodes(:);
Safety_Network.OriginalToReduced = CONF.Safety_Original_To_Reduced(:);
Safety_Network.SCCColumnOriginalNodes = CONF.Safety_Retained_Nodes(:);
Safety_Network.SCCConstraintOriginalNodes = ...
    CONF.SCC_Constraint_Original_Nodes(:);
Safety_Network.SCRColumnOriginalNodes = CONF.Safety_GFL_Original_Nodes(:);
Safety_Network.SCRColumnReducedIndices = ...
    CONF.Safety_GFL_Reduced_Indices(:);
Safety_Network.TypicalDayCount = CONF.TypicalDayCount;
Safety_Network.AggregationScope = 'within_each_typical_day';
Safety_Network.SCCStateDimensions = {'generator','typical_day'};
Safety_Network.SCRStateDimensions = {'generator','typical_day'};
Safety_Network.SCCImpedanceDimensions = ...
    {'retained_node','retained_node','typical_day'};
Safety_Network.SCRImpedanceDimensions = ...
    {'retained_node','gfl_column','typical_day'};
Result.SafetyNetwork = Safety_Network;

end
