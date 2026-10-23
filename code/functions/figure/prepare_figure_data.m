function Data = prepare_figure_data(Result, params, Result_File, Parameter_File, Scenario_Index)
%% 检查并整理多时段结果，生成绘图所需的公共数据结构。

required = {'P_Line','P_G','P_GFL','P_GFL_Curt','P_GFM_Dis', ...
    'P_GFM_Ch','E_GFM','u_G','u_G_Start','u_G_Stop','u_GFM_Mod', ...
    'SCC_1','SCC_TimeResolved','SCR','SCR_TimeResolved','Z_SCC','Z_SCR', ...
    'Cost','CONF','SafetyNetwork','SCC_Definition','SCR_Definition', ...
    'SecurityValidation'};
missing = required(~isfield(Result, required));
if ~isempty(missing)
    error('Result is missing required fields: %s', strjoin(missing, ', '));
end

C = Result.CONF;
validate_parameter_compatibility(Result, params);
Data = struct();
Data.Full_Result = Result;
Data.CONF = C;
Data.Params = params;
Data.Result_File = Result_File;
Data.Parameter_File = Parameter_File;
Data.D = C.TypicalDayCount;
Data.K = C.WindScenarioCount;
Data.T = C.PeriodCount;
Data.N = C.Bn;
Data.G = C.Gn;
Data.L = C.Ln;
Data.Candidate_Buses = C.GFM_Module_Candidates(:);
Data.Candidate_Count = numel(Data.Candidate_Buses);
Data.Period_Hours = C.PeriodDurations_Hours(:).';
Data.Time_Edges = [0, cumsum(Data.Period_Hours)];
Data.Time_Centers = Data.Time_Edges(1:end-1) + Data.Period_Hours/2;

% 现有图形版式保持单场景展示。优先选择已标记的基准场景；
% 显式场景未定义基准时，绘图默认取列表第一项，完整结果仍保存在Data.Full_Result中。
if nargin < 5 || isempty(Scenario_Index)
    Default_Scenario_Index = C.WindScenarioBaseIndex;
    if ~isscalar(Default_Scenario_Index) || ~isfinite(Default_Scenario_Index) || ...
            Default_Scenario_Index ~= round(Default_Scenario_Index) || ...
            Default_Scenario_Index < 1 || Default_Scenario_Index > Data.K
        Default_Scenario_Index = 1;
    end
    Data.Selected_Scenario_Index = Default_Scenario_Index;
else
    Data.Selected_Scenario_Index = Scenario_Index;
end
Data.Scenario_Names = C.WindScenarioNames;
if ~isscalar(Data.Selected_Scenario_Index) || ...
        ~isfinite(Data.Selected_Scenario_Index) || ...
        Data.Selected_Scenario_Index ~= round(Data.Selected_Scenario_Index) || ...
        Data.Selected_Scenario_Index < 1 || Data.Selected_Scenario_Index > Data.K
    error('Selected wind-scenario index is outside the saved scenario range.');
end
Data.Selected_Scenario_Name = Data.Scenario_Names{Data.Selected_Scenario_Index};
Data.Result = select_wind_scenario(Result, Data.Selected_Scenario_Index);
Result = Data.Result;

assert_size(Result.P_G, [Data.G Data.D Data.T], 'P_G');
assert_size(Result.P_Line, [Data.L Data.D Data.T], 'P_Line');
assert_size(Result.P_GFL, [Data.N Data.D Data.T], 'P_GFL');
assert_size(Result.P_GFM_Dis, [Data.Candidate_Count Data.D Data.T], 'P_GFM_Dis');
assert_size(Result.E_GFM, [Data.Candidate_Count Data.D Data.T], 'E_GFM');
assert_size(Result.u_G_SCC, [Data.G Data.D], 'u_G_SCC');
assert_size(Result.u_G_SCR, [Data.G Data.D], 'u_G_SCR');
if ~(isfield(C,'ModelVersion') && strcmp(C.ModelVersion,'2026-10-23'))
    assert_size(Result.Z_SCC, [C.Safety_Node_Count C.Safety_Node_Count Data.D], ...
        'Z_SCC');
end
assert_size(Result.Z_SCR, [C.Safety_Node_Count C.Safety_GFL_Count Data.D], ...
    'Z_SCR');
assert_size(Result.SCC_1, [Data.N Data.D], 'SCC_1');
assert_size(Result.SCR, [Data.N Data.D], 'SCR');
assert_size(Result.SCC_TimeResolved, ...
    [Data.T Data.D numel(C.SCC_Constraint_Original_Nodes)], ...
    'SCC_TimeResolved');
assert_size(Result.SCR_TimeResolved, ...
    [Data.T Data.D numel(C.Safety_GFL_Original_Nodes)], ...
    'SCR_TimeResolved');

Data.Module_Built = module_build_vector(C, Result.u_GFM_Mod);
Data.Modules_Per_Candidate = full(C.GFM_Candidate_Module_Mat * Data.Module_Built);
Data.Installed_Power_MW = full(C.GFM_Candidate_Module_Mat * ...
    (C.GFM_Module_PN(:).*Data.Module_Built));
Data.Installed_Energy_MWh = full(C.GFM_Candidate_Module_Mat * ...
    (C.GFM_Module_Rated_Energy(:).*Data.Module_Built));
Data.Built_Candidate_Mask = Data.Modules_Per_Candidate > 0.5;

Data.GFL_Buses = find(C.u_GFL(:) > 0.5);
Data.Generator_Buses = params.Network.mpc.gen(:,1);
Data.Branch_From = params.Network.mpc.branch(:,1);
Data.Branch_To = params.Network.mpc.branch(:,2);
Data.Line_Limit_MW = params.Network.mpc.branch(:,6);
if numel(Data.Line_Limit_MW) ~= Data.L
    error('Parameter/result line counts differ (%d versus %d).', ...
        numel(Data.Line_Limit_MW), Data.L);
end

Data.Load_MW = C.P_Load_Profile;
Data.GFL_Available_MW = reshape(C.P_GFL_Available_Scenarios( ...
    :, :, Data.Selected_Scenario_Index, :),Data.N,Data.D,Data.T) .* ...
    reshape(C.u_GFL(:), Data.N, 1, 1);
Data.Line_Loading_Pct = abs(Result.P_Line) ./ ...
    reshape(Data.Line_Limit_MW, Data.L, 1, 1) * 100;
Data.Line_Loading_Pct(~isfinite(Data.Line_Loading_Pct)) = NaN;

Data.Cost = calculate_cost_breakdown(Result);
Data.Security = calculate_security_posthoc(Data);
end

function Result = select_wind_scenario(Result, Scenario_Index)
%% 将四维场景运行结果投影为现有制图函数使用的三维数组。

Scenario_Fields = {'P_Line','theta','P_G','P_GFL','P_GFL_Curt', ...
    'P_GFM','P_GFM_Dis','P_GFM_Ch','E_GFM','u_GFM_Ch'};
for k = 1:numel(Scenario_Fields)
    name = Scenario_Fields{k};
    value = Result.(name);
    Result.(name) = reshape(value(:,:,Scenario_Index,:), ...
        size(value,1),size(value,2),size(value,4));
end

end

function Module_Built = module_build_vector(C, Module_Table)
Module_Bus = C.GFM_Module_Bus(:);
Module_Order = C.GFM_Module_Order(:);
[found, Candidate_Index] = ismember(Module_Bus, C.GFM_Module_Candidates(:));
if ~all(found)
    error('At least one module bus is not in GFM_Module_Candidates.');
end
Linear_Index = sub2ind(size(Module_Table), Candidate_Index, Module_Order);
Module_Built = reshape(round(Module_Table(Linear_Index)),[],1);
end

function Cost = calculate_cost_breakdown(Result)
C = Result.CONF;
startup = 0;
shutdown = 0;
for d = 1:C.TypicalDayCount
    for t = 1:C.PeriodCount
        startup = startup + C.TypicalDayWeights_Days(d) * ...
            C.Gen_Startup_Cost(:).' * Result.u_G_Start(:,d,t);
        shutdown = shutdown + C.TypicalDayWeights_Days(d) * ...
            C.Gen_Shutdown_Cost(:).' * Result.u_G_Stop(:,d,t);
    end
end
Cost.Names = ["Operating"; "GFM fixed cost"; "Curtailment"; "Startup"; "Shutdown"];
Cost.Values = [Result.Cost.GEN; Result.Cost.CON; Result.Cost.Curt; startup; shutdown];
Cost.Sum = sum(Cost.Values);
Cost.Reported_Total = Result.Cost.Total;
Cost.Solver_Objective = Result.Diagnostics.objective;
Cost.Percent = 100*Cost.Values/max(abs(Cost.Reported_Total), eps);
Cost.Decomposition_Error = Cost.Sum-Cost.Reported_Total;
Cost.Objective_Error = Cost.Sum-Cost.Solver_Objective;
Cost.Tolerance = max(1, 1e-6*max(abs([Cost.Sum; Cost.Reported_Total; ...
    Cost.Solver_Objective]), [], 'omitnan'));
end

function Security = calculate_security_posthoc(Data)
R = Data.Result;
C = Data.CONF;
Security.State_Description = ...
    'aggregate conservative states compared with actual hourly posterior states';
Security.SCC_Nodes = R.SafetyNetwork.SCCTimeResolvedOriginalNodes(:);
Security.SCC_Definition = R.SCC_Definition;
Security.SCC_1_All = R.SCC_1;
Security.SCC_1 = R.SCC_1(Security.SCC_Nodes,:);
Security.SCC_TimeResolved = R.SCC_TimeResolved;
Security.SCC_Hourly_Max = reshape(max(R.SCC_TimeResolved,[],1), ...
    Data.D,numel(Security.SCC_Nodes)).';
Security.SCC_Limit = repmat(C.I_limit_kA_Node(Security.SCC_Nodes),1,Data.D);
Security.SCC_1_Margin = Security.SCC_Limit-Security.SCC_1;
Security.SCC_Hourly_Margin = Security.SCC_Limit-Security.SCC_Hourly_Max;
Security.SCC_Conservatism_Margin = ...
    Security.SCC_1-Security.SCC_Hourly_Max;

Security.SCR_Nodes = R.SafetyNetwork.SCRTimeResolvedOriginalNodes(:);
Security.SCR_Definition = R.SCR_Definition;
Security.SCR_Aggregated = R.SCR(Security.SCR_Nodes,:);
Security.SCR_TimeResolved = R.SCR_TimeResolved;
Security.SCR_Hourly_Min = reshape(min(R.SCR_TimeResolved,[],1), ...
    Data.D,numel(Security.SCR_Nodes)).';
if isscalar(C.SCR_min)
    Security.SCR_Limit = repmat(C.SCR_min,numel(Security.SCR_Nodes),Data.D);
else
    Security.SCR_Limit = repmat(C.SCR_min(Security.SCR_Nodes),1,Data.D);
end
Security.SCR_Aggregated_Margin = Security.SCR_Aggregated-Security.SCR_Limit;
Security.SCR_Hourly_Margin = Security.SCR_Hourly_Min-Security.SCR_Limit;
Security.SCR_Conservatism_Margin = ...
    Security.SCR_Hourly_Min-Security.SCR_Aggregated;
Security.Validation = R.SecurityValidation;
end

function assert_size(value, expected, Field_Name)
actual = size(value);
actual(end+1:numel(expected)) = 1;
if ~isequal(actual(1:numel(expected)), expected)
    error('%s has size %s; expected %s.', Field_Name, ...
        mat2str(size(value)), mat2str(expected));
end
end

function validate_parameter_compatibility(Result, params)
%% 防止将已保存结果与不同的当前JSON算例混用。
C = Result.CONF;
Parameter_Enable_SCC = optional_logical_switch( ...
    params.Security,'Enable_SCC',true);
Parameter_Enable_SCR = optional_logical_switch( ...
    params.Security,'Enable_SCR',true);
Result_Enable_SCC = optional_logical_switch(C,'Enable_SCC',true);
Result_Enable_SCR = optional_logical_switch(C,'Enable_SCR',true);
checks = {
    size(params.Network.mpc.bus,1), C.Bn, 'bus count';
    size(params.Network.mpc.gen,1), C.Gn, 'generator count';
    size(params.Network.mpc.branch,1), C.Ln, 'line count';
    params.Multiple_Snapshot.Time.Typical_Day_Count, C.TypicalDayCount, 'typical-day count';
    params.Multiple_Snapshot.Time.Period_Count, C.PeriodCount, 'period count';
    Parameter_Enable_SCC, Result_Enable_SCC, 'SCC constraint switch';
    Parameter_Enable_SCR, Result_Enable_SCR, 'SCR constraint switch';
    params.Security.SCR_min, C.SCR_min, 'classic SCR limit'};
for k = 1:size(checks,1)
    if ~isequaln(checks{k,1}, checks{k,2})
        error('Parameter/result mismatch in %s.', checks{k,3});
    end
end
assert_close(params.Multiple_Snapshot.Time.Period_Durations_Hours(:), ...
    C.PeriodDurations_Hours(:), 'period durations');
assert_close(params.Multiple_Snapshot.Time.Typical_Day_Weights_Days(:), ...
    C.TypicalDayWeights_Days(:), 'typical-day weights');
assert_close(params.GFM_Modules.Candidates.Bus(:), C.GFM_Module_Candidates(:), ...
    'GFM candidate buses');
assert_close(params.Multiple_Snapshot.Profiles.Load_P_MW(:), C.P_Load_Profile(:), ...
    'load profile');
assert_close(params.Multiple_Snapshot.Profiles.GFL_Available_P_MW(:), ...
    C.P_GFL_Available_Profile(:), 'GFL available-power profile');
scenarios = params.Multiple_Snapshot.Wind_Scenarios;
if scenarios.Count ~= C.WindScenarioCount
    error('Parameter/result mismatch in wind-scenario count.');
end
if isvector(scenarios.Probabilities) && ...
        numel(scenarios.Probabilities) == C.WindScenarioCount
    probabilities = repmat(reshape(scenarios.Probabilities,1,[]), ...
        C.TypicalDayCount,1);
else
    probabilities = reshape(scenarios.Probabilities, ...
        C.TypicalDayCount,C.WindScenarioCount);
end
assert_close(probabilities(:),C.WindScenarioProbabilities(:), ...
    'wind-scenario probabilities');
end

function Value = optional_logical_switch(Input,Field_Name,Default_Value)
if ~isfield(Input,Field_Name)
    Value = Default_Value;
else
    Value = Input.(Field_Name);
end
if ~islogical(Value) || ~isscalar(Value)
    error('%s must be a scalar logical value.',Field_Name);
end
end

function assert_close(a, b, label)
if numel(a) ~= numel(b) || any(~isfinite(a(:))) || any(~isfinite(b(:))) || ...
        max(abs(a(:)-b(:)), [], 'omitnan') > 1e-8*max(1,max(abs(b(:))))
    error(['Parameter/result mismatch in %s. Use the parameter JSON that ', ...
        'created the selected MAT result.'], label);
end
end
