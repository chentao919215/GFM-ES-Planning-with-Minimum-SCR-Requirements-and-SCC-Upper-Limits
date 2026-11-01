function [SCC, SCR, SCC_Hourly, SCR_Hourly, Validation, X_SCR] = ...
    calculate_converter_security_metrics(NET, CONF, Unit_State, UC)
%% Manuscript附录定理1-2：分别复算并集、交集和真实逐时状态。

SEC = prepare_converter_security_network(NET, CONF);
D = CONF.TypicalDayCount;
T = CONF.PeriodCount;
SCC = nan(NET.N, D);
SCR = nan(NET.N, D);
X_SCR = nan(SEC.N, numel(SEC.GFL), D);
SCC_Hourly = nan(T, D, SEC.N);
SCR_Hourly = nan(T, D, numel(SEC.GFL));
Failures = {};
for d = 1:D
    Union = max(round(UC(:, d, :)), [], 3);
    Intersection = min(round(UC(:, d, :)), [], 3);
    try
        SCC(NET.Safety_Retained_Nodes, d) = ...
            calculate_converter_security_state(SEC, CONF, Union, Unit_State, true, false);
    catch Cause
        Failures{end+1} = sprintf('典型日%d并集状态复算失败：%s', d, Cause.message);
    end
    try
        [~, SCR_d, X] = calculate_converter_security_state( ...
            SEC, CONF, Intersection, Unit_State, false, true);
        SCR(NET.Safety_GFL_Original_Nodes, d) = SCR_d;
        X_SCR(:, :, d) = X(:, SEC.GFL);
    catch Cause
        Failures{end+1} = sprintf('典型日%d交集状态复算失败：%s', d, Cause.message);
    end
    for t = 1:T
        try
            SCC_Hourly(t, d, :) = calculate_converter_security_state( ...
                SEC, CONF, UC(:, d, t), Unit_State, true, false);
        catch Cause
            Failures{end+1} = sprintf('典型日%d时段%d的SCC复算失败：%s', d, t, Cause.message);
        end
        try
            [~, SCR_Hourly(t, d, :)] = calculate_converter_security_state( ...
                SEC, CONF, UC(:, d, t), Unit_State, false, true);
        catch Cause
            Failures{end+1} = sprintf('典型日%d时段%d的SCR复算失败：%s', d, t, Cause.message);
        end
    end
end
Validation.Conservatism = check_aggregated_security_conservatism( ...
    SCC, SCR, SCC_Hourly, SCR_Hourly, CONF);
Validation.Limits = check_converter_security_limits(SCC_Hourly, SCR_Hourly, CONF);
Validation.Failures = Failures;
end
