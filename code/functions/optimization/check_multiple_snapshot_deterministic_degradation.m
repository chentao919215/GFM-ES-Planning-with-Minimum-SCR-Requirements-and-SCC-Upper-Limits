function Report = check_multiple_snapshot_deterministic_degradation(CONF, tolerance)
%% 检查单基准场景输入是否与原确定性多时段输入严格等价。

if nargin < 2 || isempty(tolerance)
    tolerance = 1e-10;
end

expected_size = [CONF.Bn, CONF.TypicalDayCount, 1, CONF.PeriodCount];
actual_size = [size(CONF.P_GFL_Available_Scenarios,1), ...
    size(CONF.P_GFL_Available_Scenarios,2), ...
    size(CONF.P_GFL_Available_Scenarios,3), ...
    size(CONF.P_GFL_Available_Scenarios,4)];
probability_error = max(abs(CONF.WindScenarioProbabilities(:)-1));
profile_error = max(abs(CONF.P_GFL_Available_Scenarios(:)- ...
    CONF.P_GFL_Available_Profile(:)));
expected_operating_weights = CONF.TypicalDayWeights_Days(:)* ...
    CONF.PeriodDurations_Hours(:).';
weight_error = max(abs(CONF.OperatingWeights_Hours(:)- ...
    expected_operating_weights(:)));

Report = struct();
Report.ScenarioCount = CONF.WindScenarioCount;
Report.ScenarioProbabilityError = probability_error;
Report.AvailablePowerProfileError_MW = profile_error;
Report.OperatingWeightError_Hours = weight_error;
Report.ExpectedAvailablePowerSize = expected_size;
Report.ActualAvailablePowerSize = actual_size;
Report.InputEquivalent = CONF.WindScenarioCount == 1 && ...
    isequal(actual_size,expected_size) && probability_error <= tolerance && ...
    profile_error <= tolerance && weight_error <= tolerance;

if ~Report.InputEquivalent
    error(['确定性退化输入检查失败：场景数=%d，概率误差=%.3g，', ...
        '轨迹误差=%.3g MW，运行权重误差=%.3g h。'], ...
        CONF.WindScenarioCount,probability_error,profile_error,weight_error);
end

end
