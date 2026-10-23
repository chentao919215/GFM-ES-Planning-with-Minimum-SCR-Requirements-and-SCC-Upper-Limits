function Assembly = build_multiple_snapshot_security_constraint_assembly(CONF)
%% Define the security-constraint groups actually assembled for one solve.

CONF = normalize_multiple_snapshot_conf(CONF);
Enable_SCC = CONF.Enable_SCC;
Enable_SCR = CONF.Enable_SCR;
Need_Intersection_State = Enable_SCC || Enable_SCR;

Assembly = struct();
Assembly.Enable_SCC = Enable_SCC;
Assembly.Enable_SCR = Enable_SCR;
Assembly.Aggregate_SCC_Union = Enable_SCC;
Assembly.Aggregate_Intersection = Need_Intersection_State;
Assembly.Impedance_SCC = Enable_SCC;
Assembly.Impedance_SCR = Enable_SCR;
Assembly.LVRT = Enable_SCC;
Assembly.Fault_Transfer = Enable_SCC;
Assembly.SCC_Limit = Enable_SCC;
Assembly.SCR_Limit = Enable_SCR;
Assembly.Invalid_SCC_State_Pairs = Enable_SCC;
Assembly.Invalid_Intersection_States = Need_Intersection_State;
Assembly.Hourly_Source_Online_Base = CONF.Require_Source_Online;

if strcmp(CONF.ModelVersion,'2026-10-23')
    Assembly.Impedance_SCC = false;
    Assembly.Fault_Transfer = false;
    Assembly.Invalid_SCC_State_Pairs = false;
    Assembly.Invalid_Intersection_States = false;
    Assembly.Union_Residual_Voltage = Enable_SCC;
    Assembly.Intersection_Source_Support = Enable_SCC || Enable_SCR;
    Assembly.Hourly_Postfault_Component_Support = Enable_SCC;
end

end
