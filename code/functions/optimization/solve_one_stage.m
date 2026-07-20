function [Result, result_file] = solve_one_stage(mpc, CONF, paths)
%% 执行一次求解、归档结果并打印摘要。

tic;
[SCC_0,SCC_1,P_Line,theta,P_G,P_GFL,P_GFM,SCR,Z_SCC,Z_SCR, ...
    u_GFL,u_G,u_G_SCC,u_G_SCR,Cost_CON,Cost_GEN,Cost_Total,Diagnostics, ...
    u_GFM_Mod,P_GFM_Dis,P_GFM_Ch,E_GFM,u_GFM_Ch,P_GFL_Curt,Cost_Curt, ...
    u_G_Start,u_G_Stop,Cost_UC] = ...
    solve_multiple_snapshot_planning(mpc, CONF);
solve_time = toc;

Result = package_multiple_snapshot_result(SCC_0,SCC_1,P_Line,theta,P_G,P_GFL,P_GFM, ...
    SCR,Z_SCC,Z_SCR,u_GFL,u_G,u_G_SCC,u_G_SCR,Cost_CON,Cost_GEN,Cost_Total, ...
    solve_time,CONF,Diagnostics,u_GFM_Mod,P_GFM_Dis,P_GFM_Ch,E_GFM,u_GFM_Ch, ...
    P_GFL_Curt,Cost_Curt,u_G_Start,u_G_Stop,Cost_UC);

if isfield(CONF, 'SolveStage')
    Result.SolveStage = CONF.SolveStage;
else
    Result.SolveStage = 'single-stage';
end

result_file = save_multiple_snapshot_result(Result, paths.results_dir);
print_multiple_snapshot_summary(Result, result_file);

end
