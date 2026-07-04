function CONF_Deterministic = build_multiple_snapshot_deterministic_case(CONF)
%% 从场景随机算例中提取概率为1的基准场景，用于确定性退化验证。

base_index = CONF.WindScenarioBaseIndex;
if ~isscalar(base_index) || ~isfinite(base_index) || ...
        base_index ~= round(base_index) || base_index < 1 || ...
        base_index > CONF.WindScenarioCount
    error('无法唯一识别基准风电场景，请设置WindScenarios.Names中的base场景。');
end

CONF_Deterministic = CONF;
CONF_Deterministic.WindScenarioCount = 1;
CONF_Deterministic.WindScenarioNames = {'base'};
CONF_Deterministic.WindScenarioProbabilities = ...
    ones(CONF.TypicalDayCount,1);
CONF_Deterministic.WindScenarioScaleFactors = ...
    CONF.WindScenarioScaleFactors(:,base_index);
CONF_Deterministic.WindScenarioGenerationMode = 'deterministic_base';
CONF_Deterministic.WindScenarioBaseIndex = 1;
CONF_Deterministic.P_GFL_Available_Scenarios = ...
    CONF.P_GFL_Available_Scenarios(:,:,base_index,:);

% 基准场景必须与原确定性轨迹完全一致，否则不能作为退化算例。
CONF_Deterministic.DeterministicDegradation = ...
    check_multiple_snapshot_deterministic_degradation(CONF_Deterministic);

end
