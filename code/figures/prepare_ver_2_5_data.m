function Data = prepare_ver_2_5_data(Result, params, result_file, param_file)
%% Validate and normalize a ver_2.5 multiple-snapshot result structure.

required = {'P_Line','P_G','P_GFL','P_GFL_Curt','P_GFM_Dis', ...
    'P_GFM_Ch','E_GFM','u_G','u_G_Start','u_G_Stop','u_GFM_Mod', ...
    'SCC_1','SCR','Z_SCC','Z_SCR','Cost','CONF','SafetyNetwork'};
missing = required(~isfield(Result, required));
if ~isempty(missing)
    error('Result is missing required fields: %s', strjoin(missing, ', '));
end

C = Result.CONF;
validate_parameter_compatibility(Result, params);
Data = struct();
Data.FullResult = Result;
Data.CONF = C;
Data.Params = params;
Data.ResultFile = result_file;
Data.ParameterFile = param_file;
Data.CaseName = get_field(C, 'CaseName', 'multiple-snapshot case');
Data.D = C.TypicalDayCount;
Data.K = get_field(C, 'WindScenarioCount', 1);
Data.T = C.PeriodCount;
Data.N = C.Bn;
Data.G = C.Gn;
Data.L = C.Ln;
Data.CandidateBuses = C.GFM_Module_Candidates(:);
Data.CandidateCount = numel(Data.CandidateBuses);
Data.PeriodHours = C.PeriodDurations_Hours(:).';
Data.TimeEdges = [0, cumsum(Data.PeriodHours)];
Data.TimeCenters = Data.TimeEdges(1:end-1) + Data.PeriodHours/2;

% 现有ver_2_5图形版式保持单场景展示。随机模型结果默认选择基准场景，
% 完整四维结果仍保存在Data.FullResult中供后续批量场景制图使用。
Data.SelectedScenarioIndex = get_field(C, 'WindScenarioBaseIndex', 1);
if ~isfinite(Data.SelectedScenarioIndex)
    Data.SelectedScenarioIndex = 1;
end
Data.SelectedScenarioIndex = round(Data.SelectedScenarioIndex);
Data.ScenarioNames = get_field(C, 'WindScenarioNames', {'base'});
if Data.SelectedScenarioIndex < 1 || Data.SelectedScenarioIndex > Data.K
    error('Selected wind-scenario index is outside the saved scenario range.');
end
Data.SelectedScenarioName = Data.ScenarioNames{Data.SelectedScenarioIndex};
Data.Result = select_wind_scenario(Result, Data.SelectedScenarioIndex);
Result = Data.Result;

assert_size(Result.P_G, [Data.G Data.D Data.T], 'P_G');
assert_size(Result.P_Line, [Data.L Data.D Data.T], 'P_Line');
assert_size(Result.P_GFL, [Data.N Data.D Data.T], 'P_GFL');
assert_size(Result.P_GFM_Dis, [Data.CandidateCount Data.D Data.T], 'P_GFM_Dis');
assert_size(Result.E_GFM, [Data.CandidateCount Data.D Data.T], 'E_GFM');
assert_size(Result.u_G_SCC, [Data.G Data.D], 'u_G_SCC');
assert_size(Result.u_G_SCR, [Data.G Data.D], 'u_G_SCR');
assert_size(Result.Z_SCC, [C.Safety_Node_Count C.Safety_Node_Count Data.D], ...
    'Z_SCC');
assert_size(Result.Z_SCR, [C.Safety_Node_Count C.Safety_GFL_Count Data.D], ...
    'Z_SCR');
assert_size(Result.SCC_1, [Data.N Data.D], 'SCC_1');
assert_size(Result.SCR, [Data.N Data.D], 'SCR');

Data.ModuleBuilt = module_build_vector(C, Result.u_GFM_Mod);
Data.ModulesPerCandidate = full(C.GFM_Candidate_Module_Mat * Data.ModuleBuilt);
Data.InstalledPowerMW = full(C.GFM_Candidate_Module_Mat * ...
    (C.GFM_Module_PN(:).*Data.ModuleBuilt));
Data.InstalledEnergyMWh = full(C.GFM_Candidate_Module_Mat * ...
    (C.GFM_Module_Rated_Energy(:).*Data.ModuleBuilt));
Data.BuiltCandidateMask = Data.ModulesPerCandidate > 0.5;

Data.GFLBuses = find(Result.u_GFL(:) > 0.5);
Data.GeneratorBuses = params.mpc.gen(:,1);
Data.BranchFrom = params.mpc.branch(:,1);
Data.BranchTo = params.mpc.branch(:,2);
Data.LineLimitMW = params.mpc.branch(:,6);
if numel(Data.LineLimitMW) ~= Data.L
    error('Parameter/result line counts differ (%d versus %d).', ...
        numel(Data.LineLimitMW), Data.L);
end

Data.LoadMW = C.P_Load_Profile;
Data.GFLAvailableMW = reshape(C.P_GFL_Available_Scenarios( ...
    :, :, Data.SelectedScenarioIndex, :),Data.N,Data.D,Data.T) .* ...
    reshape(Result.u_GFL(:), Data.N, 1, 1);
Data.LineLoadingPct = abs(Result.P_Line) ./ ...
    reshape(Data.LineLimitMW, Data.L, 1, 1) * 100;
Data.LineLoadingPct(~isfinite(Data.LineLoadingPct)) = NaN;

Data.Cost = calculate_cost_breakdown(Result);
Data.Security = calculate_security_posthoc(Data);
end

function Result = select_wind_scenario(Result, scenario_index)
%% 将四维场景运行结果投影为现有制图函数使用的三维数组。

scenario_fields = {'P_Line','theta','P_G','P_GFL','P_GFL_Curt', ...
    'P_GFM','P_GFM_Dis','P_GFM_Ch','E_GFM','u_GFM_Ch'};
for k = 1:numel(scenario_fields)
    name = scenario_fields{k};
    value = Result.(name);
    if ndims(value) >= 4
        Result.(name) = reshape(value(:,:,scenario_index,:), ...
            size(value,1),size(value,2),size(value,4));
    end
end

end

function module_built = module_build_vector(C, module_table)
module_bus = C.GFM_Module_Bus(:);
module_order = C.GFM_Module_Order(:);
[found, candidate_idx] = ismember(module_bus, C.GFM_Module_Candidates(:));
if ~all(found)
    error('At least one module bus is not in GFM_Module_Candidates.');
end
linear_idx = sub2ind(size(module_table), candidate_idx, module_order);
module_built = round(module_table(linear_idx));
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
Cost.Names = ["Operating"; "Investment"; "Curtailment"; "Startup"; "Shutdown"];
Cost.Values = [Result.Cost.GEN; Result.Cost.CON; Result.Cost.Curt; startup; shutdown];
Cost.Sum = sum(Cost.Values);
Cost.ReportedTotal = Result.Cost.Total;
Cost.SolverObjective = get_field(Result.Diagnostics, 'objective', NaN);
Cost.Percent = 100*Cost.Values/max(abs(Cost.ReportedTotal), eps);
Cost.DecompositionError = Cost.Sum-Cost.ReportedTotal;
Cost.ObjectiveError = Cost.Sum-Cost.SolverObjective;
Cost.Tolerance = max(1, 1e-6*max(abs([Cost.Sum; Cost.ReportedTotal; ...
    Cost.SolverObjective]), [], 'omitnan'));
end

function Security = calculate_security_posthoc(Data)
R = Data.Result;
C = Data.CONF;
mpc = Data.Params.mpc;
branch = mpc.branch;
branch(:,3) = Data.Params.BranchScale.r*branch(:,3);
branch(:,4) = Data.Params.BranchScale.x*branch(:,4);
branch(:,5) = Data.Params.BranchScale.b*branch(:,5);

fb = branch(:,1); tb = branch(:,2);
y = 1./(branch(:,3)+1i*branch(:,4));
bsh = 1i*branch(:,5)/2;
Y0 = sparse(fb,fb,y+bsh,Data.N,Data.N) + ...
     sparse(tb,tb,y+bsh,Data.N,Data.N) + ...
     sparse(fb,tb,-y,Data.N,Data.N) + ...
     sparse(tb,fb,-y,Data.N,Data.N);
gen_loc = sparse(Data.GeneratorBuses,(1:Data.G).',1,Data.N,Data.G);
module_loc = C.GFM_Module_Loc_Mat;
Ygfm = module_loc*(Data.ModuleBuilt.*(1./(1i*C.GFM_Module_X_res(:))));

Security.StateDescription = 'within-typical-day aggregated conservative states';
Security.SCCNodes = R.SafetyNetwork.RetainedOriginalNodes(:);
Security.SCCExactAll = zeros(Data.N,Data.D);
Security.SCCExact = zeros(numel(Security.SCCNodes),Data.D);
Security.SCCOptimization = zeros(numel(Security.SCCNodes),Data.D);
for d = 1:Data.D
    YsgSCC = (gen_loc*round(R.u_G_SCC(:,d)))*(1/(1i*C.Xd_Gen));
    ZSCCExact = full(Y0+spdiags(YsgSCC+Ygfm,0,Data.N,Data.N))\eye(Data.N);
    Security.SCCExactAll(:,d) = scc_from_impedance( ...
        diag(ZSCCExact),(1:Data.N).',Data);
    Security.SCCExact(:,d) = Security.SCCExactAll(Security.SCCNodes,d);
    Security.SCCOptimization(:,d) = scc_from_impedance( ...
        diag(R.Z_SCC(:,:,d)),Security.SCCNodes,Data);
end
Security.SCCLimit = repmat(C.I_limit_kA_Node(Security.SCCNodes),1,Data.D);
Security.SCCMargin = Security.SCCLimit-Security.SCCExact;
Security.SCCRelativeErrorPct = relative_error_pct(...
    Security.SCCOptimization, Security.SCCExact);

Security.SCRNodes = R.SafetyNetwork.SCRColumnOriginalNodes(:);
pn = C.PN_GFL_pu_Node(Security.SCRNodes);
Security.SCRExact = zeros(numel(Security.SCRNodes),Data.D);
for d = 1:Data.D
    YsgSCR = (gen_loc*round(R.u_G_SCR(:,d)))*(1/(1i*C.Xd_Gen));
    ZSCRExact = full(Y0+spdiags(YsgSCR+Ygfm,0,Data.N,Data.N))\eye(Data.N);
    xExact = imag(diag(ZSCRExact));
    Security.SCRExact(:,d) = 1./max( ...
        pn.*xExact(Security.SCRNodes),eps);
end
Security.SCROptimization = R.SCR(Security.SCRNodes,:);
Security.SCRLimit = repmat(C.SCR_min,numel(Security.SCRNodes),Data.D);
Security.SCRMargin = Security.SCRExact-Security.SCRLimit;
Security.SCRRelativeErrorPct = relative_error_pct(...
    Security.SCROptimization, Security.SCRExact);
end

function scc = scc_from_impedance(zdiag, original_nodes, Data)
C = Data.CONF;
xdiag = imag(zdiag(:));
gfm_delta_all = C.GFM_Module_Loc_Mat * ...
    (C.GFM_Module_DeltaY_abs(:).*Data.ModuleBuilt);
gfl_current_all = (C.I_post_GFL_Node(:)+C.PN_GFL_pu_Node(:)) .* ...
    Data.Result.u_GFL(:);
scc = (1./(xdiag+1e-12) - gfm_delta_all(original_nodes) + ...
    gfl_current_all(original_nodes))*C.Base_kA;
end

function err = relative_error_pct(approximation, reference)
err = 100*abs(approximation-reference)./max(abs(reference), 1e-9);
end

function assert_size(value, expected, field_name)
actual = size(value);
actual(end+1:numel(expected)) = 1;
if ~isequal(actual(1:numel(expected)), expected)
    error('%s has size %s; expected %s.', field_name, ...
        mat2str(size(value)), mat2str(expected));
end
end

function value = get_field(input, name, default)
if isfield(input, name) && ~isempty(input.(name))
    value = input.(name);
else
    value = default;
end
end

function validate_parameter_compatibility(Result, params)
%% Prevent silent mixing of a saved result with a different current JSON case.
C = Result.CONF;
checks = {
    size(params.mpc.bus,1), C.Bn, 'bus count';
    size(params.mpc.gen,1), C.Gn, 'generator count';
    size(params.mpc.branch,1), C.Ln, 'line count';
    params.MultipleSnapshot.TypicalDayCount, C.TypicalDayCount, 'typical-day count';
    params.MultipleSnapshot.PeriodCount, C.PeriodCount, 'period count';
    params.SCR_min, C.SCR_min, 'classic SCR limit'};
for k = 1:size(checks,1)
    if ~isequaln(checks{k,1}, checks{k,2})
        error('Parameter/result mismatch in %s.', checks{k,3});
    end
end
assert_close(params.MultipleSnapshot.PeriodDurations_Hours(:), ...
    C.PeriodDurations_Hours(:), 'period durations');
assert_close(params.MultipleSnapshot.TypicalDayWeights_Days(:), ...
    C.TypicalDayWeights_Days(:), 'typical-day weights');
assert_close(params.GFM_Candidates(:), C.GFM_Module_Candidates(:), ...
    'GFM candidate buses');
assert_close(params.MultipleSnapshot.Load_P_MW(:), C.P_Load_Profile(:), ...
    'load profile');
assert_close(params.MultipleSnapshot.GFL_Available_P_MW(:), ...
    C.P_GFL_Available_Profile(:), 'GFL available-power profile');
if isfield(params.MultipleSnapshot, 'WindScenarios')
    scenarios = params.MultipleSnapshot.WindScenarios;
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
end

function assert_close(a, b, label)
if numel(a) ~= numel(b) || any(~isfinite(a(:))) || any(~isfinite(b(:))) || ...
        max(abs(a(:)-b(:)), [], 'omitnan') > 1e-8*max(1,max(abs(b(:))))
    error(['Parameter/result mismatch in %s. Use the parameter JSON that ', ...
        'created the selected MAT result.'], label);
end
end
