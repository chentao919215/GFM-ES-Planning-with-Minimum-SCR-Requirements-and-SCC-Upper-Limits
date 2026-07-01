function Result = package_multiple_snapshot_result(SCC_0,SCC_1,P_Line,theta,P_G,P_GFL,P_GFM,...
    SCR,Z_SCC,Z_SCR,u_GFL,u_G,u_G_SCC,u_G_SCR,Cost_CON,Cost_GEN,Cost_Total,...
    solve_time,CONF,Diagnostics,u_GFM_Mod,P_GFM_Dis,P_GFM_Ch,E_GFM,u_GFM_Ch,...
    P_GFL_Curt,Cost_Curt)
%% 本函数功能是将多时刻求解输出整理为统一结果结构体。

Cost = struct();
Cost.Total = Cost_Total;
Cost.GEN   = Cost_GEN;
Cost.CON   = Cost_CON;
Cost.Curt  = Cost_Curt;
Cost.Unit  = 'annual';

Result = struct();
Result.SCC_0       = SCC_0;
Result.SCC_1       = SCC_1;
Result.P_Line      = P_Line;
Result.theta       = theta;
Result.P_G         = P_G;
Result.P_GFL       = P_GFL;
% GFL-WG弃风功率按[节点,典型日,时段]保存。
Result.P_GFL_Curt  = P_GFL_Curt;
Result.P_GFM       = P_GFM;
Result.SCR         = SCR;
Result.Z_SCC       = Z_SCC;
Result.Z_SCR       = Z_SCR;
Result.u_GFL       = u_GFL;
Result.u_G         = u_G;
Result.u_G_SCC     = u_G_SCC;
Result.u_G_SCR     = u_G_SCR;
Result.u_GFM_Mod   = u_GFM_Mod;
% 储能运行结果按[候选节点,典型日,时段]保存，P_GFM为全节点净注入功率。
Result.P_GFM_Dis   = P_GFM_Dis;
Result.P_GFM_Ch    = P_GFM_Ch;
Result.E_GFM       = E_GFM;
Result.u_GFM_Ch    = u_GFM_Ch;
Result.Cost        = Cost;
Result.solve_time  = solve_time;
Result.CONF        = CONF;
Result.Diagnostics = Diagnostics;

end
