function Result = package_single_snapshot_result(SCC_0,SCC_1,P_Line,theta,P_G,P_GFL,P_GFM,...
    SCR,Z_val,u_GFL,u_G,Cost_CON,Cost_GEN,Cost_Total,solve_time,CONF,Diagnostics,...
    u_GFM_Mod,P_GFM_Mod)
%% 本函数功能是将求解输出整理为统一结果结构体。

if nargin < 18
    u_GFM_Mod = [];
end

if nargin < 19
    P_GFM_Mod = [];
end

Cost = struct();
Cost.Total = Cost_Total;
Cost.GEN   = Cost_GEN;
Cost.CON   = Cost_CON;
Cost.Unit  = 'annual';

Result = struct();
Result.SCC_0      = SCC_0;
Result.SCC_1      = SCC_1;
Result.P_Line     = P_Line;
Result.theta      = theta;
Result.P_G        = P_G;
Result.P_GFL      = P_GFL;
Result.P_GFM      = P_GFM;
Result.SCR        = SCR;
Result.Z_val      = Z_val;
Result.u_GFL      = u_GFL;
Result.u_GFM_Mod  = u_GFM_Mod;
Result.P_GFM_Mod  = P_GFM_Mod;
Result.u_G        = u_G;
Result.Cost       = Cost;
Result.solve_time = solve_time;
Result.CONF       = CONF;
Result.Diagnostics = Diagnostics;

end
