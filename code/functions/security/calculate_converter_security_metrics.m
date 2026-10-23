function [SCC, SCR, Z_SCC, Z_SCR, SCC_Hourly, SCR_Hourly, Validation] = ...
    calculate_converter_security_metrics(NET,CONF,Module_State,UC)
%% 新版Appendix Theorems 1-2：分别复算并集、交集和真实逐时状态。

SEC = prepare_converter_security_network(NET,CONF);
D = CONF.TypicalDayCount;
T = CONF.PeriodCount;
SCC = nan(NET.N,D);
SCR = nan(NET.N,D);
Z_SCC = []; % 新版SCC不重构电抗矩阵；避免输出旧版含义的缓存。
Z_SCR = nan(SEC.N,numel(SEC.GFL),D);
SCC_Hourly = nan(T,D,SEC.N);
SCR_Hourly = nan(T,D,numel(SEC.GFL));
Status = struct('Failures',{{}},'ModelVersion','2026-10-23');
for d = 1:D
    Union = max(round(UC(:,d,:)),[],3);
    Intersection = min(round(UC(:,d,:)),[],3);
    try
        SCC(NET.Safety_Retained_Nodes,d) = ...
            calculate_converter_security_state(SEC,CONF,Union,Module_State,true,false);
    catch Cause
        Status.Failures{end+1} = sprintf('day %d union: %s',d,Cause.message);
    end
    try
        [~,SCR_d,Details] = calculate_converter_security_state( ...
            SEC,CONF,Intersection,Module_State,false,true);
        SCR(NET.Safety_GFL_Original_Nodes,d) = SCR_d;
        Z_SCR(:,:,d) = 1i*Details.X(:,SEC.GFL);
    catch Cause
        Status.Failures{end+1} = sprintf('day %d intersection: %s',d,Cause.message);
    end
    for t = 1:T
        try
            SCC_Hourly(t,d,:) = calculate_converter_security_state( ...
                SEC,CONF,UC(:,d,t),Module_State,true,false);
        catch Cause
            Status.Failures{end+1} = sprintf('day %d period %d SCC: %s',d,t,Cause.message);
        end
        try
            [~,SCR_Hourly(t,d,:)] = calculate_converter_security_state( ...
                SEC,CONF,UC(:,d,t),Module_State,false,true);
        catch Cause
            Status.Failures{end+1} = sprintf('day %d period %d SCR: %s',d,t,Cause.message);
        end
    end
end
Validation = check_aggregated_security_conservatism( ...
    SCC,SCR,SCC_Hourly,SCR_Hourly,CONF,Status,Status);
end
