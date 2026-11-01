function Validation = check_aggregated_security_conservatism( ...
    SCC_Aggregated, SCR_Aggregated, SCC_TimeResolved, ...
    SCR_TimeResolved, CONF)
%% 比较典型日聚合界与逐时复算结果的极值。

T = CONF.PeriodCount;
D = CONF.TypicalDayCount;
SCC_Nodes = CONF.SCC_Constraint_Original_Nodes(:);
SCR_Nodes = CONF.Safety_GFL_Original_Nodes(:);
NSCC = numel(SCC_Nodes);
NGFL = numel(SCR_Nodes);

if ~isequal(size(SCC_Aggregated), [CONF.Bn D]) || ...
        ~isequal(size(SCR_Aggregated), [CONF.Bn D]) || ...
        ~size_matches(SCC_TimeResolved, [T D NSCC]) || ...
        ~size_matches(SCR_TimeResolved, [T D NGFL])
    error('SecurityConservatism:DimensionMismatch', ...
        '聚合或逐时安全指标结果的维度不符合要求。');
end

SCC_Hourly_Max = reshape(max(SCC_TimeResolved, [], 1, 'omitnan'), D, NSCC);
SCR_Hourly_Min = reshape(min(SCR_TimeResolved, [], 1, 'omitnan'), D, NGFL);
SCC_Aggregated_Selected = SCC_Aggregated(SCC_Nodes, :).';
SCR_Aggregated_Selected = SCR_Aggregated(SCR_Nodes, :).';

% 差值为正表示违反预期的保守性关系。
SCC_Difference = SCC_Hourly_Max-SCC_Aggregated_Selected;
SCR_Difference = SCR_Aggregated_Selected-SCR_Hourly_Min;
SCC_Tolerance_kA = max(1e-6, abs(CONF.ERR_TOL)*CONF.Base_kA);
SCR_Tolerance = max(1e-6, abs(CONF.ERR_TOL));

Validation = struct();
Validation.SCC = summarize_check(SCC_Difference, SCC_TimeResolved, ...
    SCC_Hourly_Max, SCC_Aggregated_Selected, SCC_Nodes, ...
    SCC_Tolerance_kA, true);
Validation.SCR = summarize_check(SCR_Difference, SCR_TimeResolved, ...
    SCR_Hourly_Min, SCR_Aggregated_Selected, SCR_Nodes, ...
    SCR_Tolerance, false);
Validation.Passed = Validation.SCC.Passed && Validation.SCR.Passed;

end

function Summary = summarize_check( ...
    Difference, TimeResolved, Hourly_Extreme, Aggregated, Nodes, ...
    Tolerance, Is_Maximum)
%% 记录最大原始差值及其对应的典型日、时段和节点。

Summary = struct();
Summary.Tolerance = Tolerance;
Available = isfinite(Difference) & isfinite(Hourly_Extreme) & isfinite(Aggregated);
Summary.Evaluable = all(Available, 'all') && all(isfinite(TimeResolved), 'all');
Summary.UnavailableCount = nnz(~Available);
if any(Available, 'all')
    Difference_For_Max = Difference;
    Difference_For_Max(~Available) = -Inf;
    [Raw_Maximum, Linear_Index] = max(Difference_For_Max(:));
    [Day_Index, Node_Index] = ind2sub(size(Difference), Linear_Index);
    Hourly_Series = TimeResolved(:, Day_Index, Node_Index);
    if Is_Maximum
        [~, Period_Index] = max(Hourly_Series, [], 'omitnan');
    else
        [~, Period_Index] = min(Hourly_Series, [], 'omitnan');
    end
    Summary.RawMaximumDifference = Raw_Maximum;
    Summary.MaximumViolation = max(0, Raw_Maximum);
    Summary.TypicalDay = Day_Index;
    Summary.Period = Period_Index;
    Summary.OriginalNode = Nodes(Node_Index);
    Summary.TimeResolvedExtreme = Hourly_Extreme(Day_Index, Node_Index);
    Summary.AggregatedValue = Aggregated(Day_Index, Node_Index);
else
    Summary.RawMaximumDifference = NaN;
    Summary.MaximumViolation = NaN;
    Summary.TypicalDay = NaN;
    Summary.Period = NaN;
    Summary.OriginalNode = NaN;
    Summary.TimeResolvedExtreme = NaN;
    Summary.AggregatedValue = NaN;
end
Summary.Passed = Summary.Evaluable && ...
    Summary.RawMaximumDifference <= Tolerance;

end

function Matches = size_matches(Value, Expected)
%% 比较约定维度，允许MATLAB省略末尾长度为1的维度。

Actual = size(Value);
Actual(end+1:numel(Expected)) = 1;
Matches = isequal(Actual(1:numel(Expected)), Expected);

end
