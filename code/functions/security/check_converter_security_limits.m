function Validation = check_converter_security_limits(SCC, SCR, CONF)
%% 核验[时段或状态快照,典型日,安全节点]排列的指标，只要求已启用的限值满足。
% 关闭的约束仍记录实际越限量，其单项Passed表示物理限值是否满足。
SCC_Nodes = CONF.SCC_Constraint_Original_Nodes(:);
SCR_Nodes = CONF.Safety_GFL_Original_Nodes(:);
SCC_Limits = CONF.I_limit_kA_Node(SCC_Nodes);
SCR_Limits = CONF.SCR_min;
if isscalar(SCR_Limits)
    SCR_Limits = repmat(SCR_Limits, numel(SCR_Nodes), 1);
else
    SCR_Limits = SCR_Limits(SCR_Nodes);
end
Validation.SCC = summarize_limit(SCC, SCC_Limits, SCC_Nodes, ...
    max(1e-6, abs(CONF.ERR_TOL)*CONF.Base_kA), true);
Validation.SCR = summarize_limit(SCR, SCR_Limits, SCR_Nodes, ...
    max(1e-6, abs(CONF.ERR_TOL)), false);
Validation.Passed = (~CONF.Enable_SCC || Validation.SCC.Passed) && ...
    (~CONF.Enable_SCR || Validation.SCR.Passed);
end

function Summary = summarize_limit(Values, Limits, Nodes, Tolerance, Is_Upper)
%% 汇总指定安全指标的限值、最大越限量及通过状态。
Difference = Values-reshape(Limits, 1, 1, []);
if ~Is_Upper
    Difference = -Difference;
end
Available = isfinite(Difference);
Summary.Tolerance = Tolerance;
Summary.Evaluable = ~isempty(Values) && all(Available, 'all');
if any(Available, 'all')
    Difference(~Available) = -Inf;
    [Maximum, Index] = max(Difference(:));
    [Period, Day, Node] = ind2sub([size(Values, 1), size(Values, 2), numel(Nodes)], Index);
    Summary.MaximumViolation = max(0, Maximum);
    Summary.TypicalDay = Day;
    Summary.Period = Period;
    Summary.OriginalNode = Nodes(Node);
    Summary.Value = Values(Index);
    Summary.Limit = Limits(Node);
else
    Summary.MaximumViolation = NaN;
    Summary.TypicalDay = NaN;
    Summary.Period = NaN;
    Summary.OriginalNode = NaN;
    Summary.Value = NaN;
    Summary.Limit = NaN;
end
Summary.Passed = Summary.Evaluable && Summary.MaximumViolation <= Tolerance;
end
