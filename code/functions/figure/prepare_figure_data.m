function Data = prepare_figure_data(Result, params, Result_File, Parameter_File, Scenario_Index)
%% 检查并整理多时段结果，生成绘图所需的公共数据结构。

required = {'P_Line','P_G','P_GFL','P_GFL_Curt','P_GFM_Dis', ...
    'P_GFM_Ch','E_GFM','u_G','u_G_Start','u_G_Stop','u_GFM_Mod', ...
    'SCC_0','SCC_1','SCC_2','SCR','Z_SCC','Z_SCR','Cost','CONF', ...
    'SafetyNetwork','SCC_Definition'};
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

% 现有图形版式保持单场景展示。随机模型结果默认选择基准场景，
% 完整四维结果仍保存在Data.Full_Result中供后续批量场景制图使用。
if nargin < 5 || isempty(Scenario_Index)
    Data.Selected_Scenario_Index = C.WindScenarioBaseIndex;
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
assert_size(Result.Z_SCC, [C.Safety_Node_Count C.Safety_Node_Count Data.D], ...
    'Z_SCC');
assert_size(Result.Z_SCR, [C.Safety_Node_Count C.Safety_GFL_Count Data.D], ...
    'Z_SCR');
assert_size(Result.SCC_0, [Data.N Data.D], 'SCC_0');
assert_size(Result.SCC_1, [Data.N Data.D], 'SCC_1');
assert_size(Result.SCC_2, [Data.N Data.D], 'SCC_2');
assert_size(Result.SCR, [Data.N Data.D], 'SCR');

Data.Module_Built = module_build_vector(C, Result.u_GFM_Mod);
Data.Modules_Per_Candidate = full(C.GFM_Candidate_Module_Mat * Data.Module_Built);
Data.Installed_Power_MW = full(C.GFM_Candidate_Module_Mat * ...
    (C.GFM_Module_PN(:).*Data.Module_Built));
Data.Installed_Energy_MWh = full(C.GFM_Candidate_Module_Mat * ...
    (C.GFM_Module_Rated_Energy(:).*Data.Module_Built));
Data.Built_Candidate_Mask = Data.Modules_Per_Candidate > 0.5;

Data.GFL_Buses = find(Result.u_GFL(:) > 0.5);
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
    reshape(Result.u_GFL(:), Data.N, 1, 1);
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
Module_Built = round(Module_Table(Linear_Index));
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
mpc = Data.Params.Network.mpc;
branch = mpc.branch;
branch(:,3) = Data.Params.Network.Branch_Scale.r*branch(:,3);
branch(:,4) = Data.Params.Network.Branch_Scale.x*branch(:,4);
branch(:,5) = Data.Params.Network.Branch_Scale.b*branch(:,5);

fb = branch(:,1); tb = branch(:,2);
y = 1./(branch(:,3)+1i*branch(:,4));
bsh = 1i*branch(:,5)/2;
Y0 = sparse(fb,fb,y+bsh,Data.N,Data.N) + ...
     sparse(tb,tb,y+bsh,Data.N,Data.N) + ...
     sparse(fb,tb,-y,Data.N,Data.N) + ...
     sparse(tb,fb,-y,Data.N,Data.N);
Gen_Location = sparse(Data.Generator_Buses,(1:Data.G).',1,Data.N,Data.G);
Module_Location = C.GFM_Module_Loc_Mat;
Ygfm = Module_Location*(Data.Module_Built.*(1./(1i*C.GFM_Module_X_Res(:))));

Security.State_Description = 'within-typical-day aggregated conservative states';
Security.SCC_Nodes = R.SafetyNetwork.RetainedOriginalNodes(:);
Security.SCC_Definition = R.SCC_Definition;
Security.SCC_0_All = R.SCC_0;
Security.SCC_1_All = R.SCC_1;
Security.SCC_2_All = R.SCC_2;
Security.SCC_0 = R.SCC_0(Security.SCC_Nodes,:);
Security.SCC_1 = R.SCC_1(Security.SCC_Nodes,:);
Security.SCC_2 = R.SCC_2(Security.SCC_Nodes,:);
Security.SCC_Limit = repmat(C.I_limit_kA_Node(Security.SCC_Nodes),1,Data.D);
Security.SCC_1_Margin = Security.SCC_Limit-Security.SCC_1;
Security.SCC_2_Margin = Security.SCC_Limit-Security.SCC_2;
Security.SCC_1_vs_SCC_2_Relative_Error_Pct = relative_error_pct( ...
    Security.SCC_1, Security.SCC_2);

Security.SCR_Nodes = R.SafetyNetwork.SCRColumnOriginalNodes(:);
pn = C.PN_GFL_pu_Node(Security.SCR_Nodes);
Security.SCR_Exact = zeros(numel(Security.SCR_Nodes),Data.D);
for d = 1:Data.D
    Y_SG_SCR = Gen_Location*(round(R.u_G_SCR(:,d)).* ...
        (1./(1i*C.Xd_Gen(:))));
    Z_SCR_Exact = full(Y0+spdiags(Y_SG_SCR+Ygfm,0,Data.N,Data.N))\eye(Data.N);
    x_Exact = imag(diag(Z_SCR_Exact));
    Security.SCR_Exact(:,d) = 1./max( ...
        pn.*x_Exact(Security.SCR_Nodes),eps);
end
Security.SCR_Optimization = R.SCR(Security.SCR_Nodes,:);
Security.SCR_Limit = repmat(C.SCR_min,numel(Security.SCR_Nodes),Data.D);
Security.SCR_Margin = Security.SCR_Exact-Security.SCR_Limit;
Security.SCR_Relative_Error_Pct = relative_error_pct(...
    Security.SCR_Optimization, Security.SCR_Exact);
end

function err = relative_error_pct(approximation, reference)
err = 100*abs(approximation-reference)./max(abs(reference), 1e-9);
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
checks = {
    size(params.Network.mpc.bus,1), C.Bn, 'bus count';
    size(params.Network.mpc.gen,1), C.Gn, 'generator count';
    size(params.Network.mpc.branch,1), C.Ln, 'line count';
    params.Multiple_Snapshot.Time.Typical_Day_Count, C.TypicalDayCount, 'typical-day count';
    params.Multiple_Snapshot.Time.Period_Count, C.PeriodCount, 'period count';
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

function assert_close(a, b, label)
if numel(a) ~= numel(b) || any(~isfinite(a(:))) || any(~isfinite(b(:))) || ...
        max(abs(a(:)-b(:)), [], 'omitnan') > 1e-8*max(1,max(abs(b(:))))
    error(['Parameter/result mismatch in %s. Use the parameter JSON that ', ...
        'created the selected MAT result.'], label);
end
end
