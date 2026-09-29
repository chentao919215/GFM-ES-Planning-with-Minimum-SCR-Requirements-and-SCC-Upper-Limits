function [SCC_Aggregated, SCR_Aggregated, Z_SCC, Z_SCR, Status] = ...
    calculate_aggregated_security_metrics( ...
    NET, CONF, Module_State, u_GFL, TimeResolved_SG_State, ...
    SCC_Bounds, SCC_Bounds_Failure)
%% Recalculate typical-day aggregate SCC/SCR from the final discrete plan.
% This posterior calculation is outside the optimization model. SCC uses
% the SG-union impedance, SG-intersection LVRT current, and the same
% configuration/union-state-specific transfer bound as the online model. SCR
% uses the SG-intersection impedance and the classic rated-capacity formula.

CONF = normalize_multiple_snapshot_conf(CONF);
Consider_Remote_GFM_Limiting = false; % Manuscript aggregate bound is local-only.
if Consider_Remote_GFM_Limiting
    error('AggregatedSecurity:IncompatibleRemoteLimiting', ...
        ['The aggregate SCC transfer bound uses the manuscript local-only ', ...
        'fault network. Remote limiting can be enabled for fixed/hourly ', ...
        'ex-post SCC, but not for this aggregate without a matching ', ...
        'transfer-bound preprocessing model.']);
end
if nargin < 6
    SCC_Bounds = [];
end
if nargin < 7
    SCC_Bounds_Failure = '';
end

N = NET.N;
G = NET.G;
D = CONF.TypicalDayCount;
T = CONF.PeriodCount;
NS = NET.Safety_N;
NGFL = NET.Safety_GFL_Count;
SCC_Nodes = CONF.SCC_Constraint_Original_Nodes(:);
GFL_Nodes = CONF.Safety_GFL_Original_Nodes(:);
Safety_Nodes = NET.Safety_Retained_Nodes(:);

if ~isequal(size(TimeResolved_SG_State),[G D T])
    error('AggregatedSecurity:SGStateDimensionMismatch', ...
        'Hourly SG state must have dimensions [generator, typical_day, period] = %s.', ...
        mat2str([G D T]));
end

Module_State = validate_binary_result(Module_State(:),'GFM-ES module build state');
u_GFL = validate_binary_result(u_GFL(:),'GFL-WG node state');
TimeResolved_SG_State = validate_binary_result( ...
    TimeResolved_SG_State,'hourly SG state');

SCC_Aggregated = zeros(N,D);
SCC_Aggregated(SCC_Nodes,:) = NaN;
SCR_Aggregated = zeros(N,D);
SCR_Aggregated(GFL_Nodes,:) = NaN;
Z_SCC = complex(nan(NS,NS,D),nan(NS,NS,D));
Z_SCR = complex(nan(NS,NGFL,D),nan(NS,NGFL,D));

Status = struct();
Status.SCC = initialize_metric_status(D, ...
    'SG-union impedance with SG-intersection LVRT and selected-union transfer bound');
Status.SCR = initialize_metric_status(D, ...
    'classic SCR from the SG-intersection fixed-state network');
Status.Issues = struct('Metric',{},'TypicalDay',{}, ...
    'Identifier',{},'Message',{});

[Configuration_Index, Configuration_Issue] = ...
    identify_configuration(CONF,Module_State);
if isempty(SCC_Bounds) && isempty(SCC_Bounds_Failure)
    SCC_Bounds_Failure = 'SCC transfer-bound preprocessing did not return data.';
end

for d = 1:D
    Union_State = max(TimeResolved_SG_State(:,d,:),[],3);
    Intersection_State = min(TimeResolved_SG_State(:,d,:),[],3);
    Union_Network = [];
    Intersection_Network = [];

    try
        Union_Network = build_fixed_state_safety_network( ...
            NET, CONF, Module_State, Union_State, ...
            sprintf('typical day %d SG-union aggregate',d));
        X_Union_Safety = Union_Network.X_Fault(Safety_Nodes,Safety_Nodes);
        Z_SCC(:,:,d) = 1i*X_Union_Safety;
    catch Cause
        Status = record_issue(Status,'SCC',d,Cause);
    end

    try
        Intersection_Network = build_fixed_state_safety_network( ...
            NET, CONF, Module_State, Intersection_State, ...
            sprintf('typical day %d SG-intersection aggregate',d));
        X_Intersection = Intersection_Network.X_Fault;
        Z_SCR(:,:,d) = 1i*X_Intersection(Safety_Nodes,GFL_Nodes);
        SCR_Day = calculate_fixed_state_scr( ...
            NET, CONF, Module_State, u_GFL, Intersection_State, ...
            GFL_Nodes, sprintf('typical day %d aggregate SCR',d), ...
            Intersection_Network);
        SCR_Aggregated(GFL_Nodes,d) = SCR_Day;
        Status.SCR.AvailableByTypicalDay(d) = true;
    catch Cause
        Status = record_issue(Status,'SCR',d,Cause);
        if isempty(Intersection_Network)
            Status = record_issue(Status,'SCC',d,Cause);
        end
    end

    if isempty(Union_Network) || isempty(Intersection_Network)
        continue;
    end
    if ~isempty(Configuration_Issue)
        Status = record_text_issue(Status,'SCC',d, ...
            'AggregatedSecurity:UnknownConfiguration',Configuration_Issue);
        continue;
    end
    if isempty(SCC_Bounds)
        Status = record_text_issue(Status,'SCC',d, ...
            'AggregatedSecurity:MissingSCCBounds',SCC_Bounds_Failure);
        continue;
    end

    try
        Union_Index = validate_scc_catalog_state(SCC_Bounds,Configuration_Index, ...
            Union_State,reshape(TimeResolved_SG_State(:,d,:),G,T),d);
        [~, Intersection_Details] = calculate_fixed_state_scc( ...
            NET, CONF, Module_State, u_GFL, Intersection_State, ...
            SCC_Nodes, sprintf('typical day %d aggregate SCC LVRT',d), ...
            Intersection_Network, Consider_Remote_GFM_Limiting);

        Tau = reshape(SCC_Bounds.Tau_GFL_Scaled( ...
            Configuration_Index,Union_Index,:,:),NS,NGFL);
        Delta_I = Intersection_Details.LVRTIncrementCurrent( ...
            GFL_Nodes,:).';
        Phi_Scaled = sum(Tau.*Delta_I,2);
        X_Self = diag(Union_Network.X_Fault);
        X_Self = X_Self(SCC_Nodes);
        GFM_Delta = CONF.GFM_Module_Loc_Mat * ...
            (CONF.GFM_Module_DeltaY_abs(:).*Module_State);
        GFL_Fault_Increment = CONF.Delta_I_GFL_pu_Node(:).*u_GFL;
        SCC_Day = ((1+Phi_Scaled/CONF.KZ)./X_Self - ...
            GFM_Delta(SCC_Nodes) + GFL_Fault_Increment(SCC_Nodes)) * ...
            CONF.Base_kA;
        if any(~isfinite(SCC_Day)) || any(SCC_Day < 0)
            error('AggregatedSecurity:InvalidSCC', ...
                'Typical day %d aggregate SCC contains invalid values.',d);
        end
        SCC_Aggregated(SCC_Nodes,d) = SCC_Day;
        Status.SCC.AvailableByTypicalDay(d) = true;
    catch Cause
        Status = record_issue(Status,'SCC',d,Cause);
    end
end

Status.SCC.AllAvailable = all(Status.SCC.AvailableByTypicalDay);
Status.SCR.AllAvailable = all(Status.SCR.AvailableByTypicalDay);
Status.AllAvailable = Status.SCC.AllAvailable && Status.SCR.AllAvailable;

end

function Metric = initialize_metric_status(D, Method)
Metric = struct();
Metric.Method = Method;
Metric.AvailableByTypicalDay = false(1,D);
Metric.AllAvailable = false;
end

function [Configuration_Index, Issue] = identify_configuration(CONF,Module_State)
Configuration_Index = [];
Issue = '';
Matches = all(logical(CONF.GFM_Config_Module_Matrix) == ...
    logical(Module_State(:).'),2);
Indices = find(Matches);
if numel(Indices) ~= 1
    Issue = sprintf(['Final module state matches %d configuration-catalog ', ...
        'rows; exactly one is required.'],numel(Indices));
else
    Configuration_Index = Indices;
end
end

function Union_Index = validate_scc_catalog_state(Bounds,Configuration_Index, ...
    Union_State,Actual_States,Day_Index)
Required = {'Tau_GFL_Scaled','Configuration_Allowed','Valid_State_Pairs', ...
    'Valid_Union_States','State_Catalog'};
if ~all(isfield(Bounds,Required)) || ...
        ~isfield(Bounds.State_Catalog,'SynchronousStates')
    error('AggregatedSecurity:IncompleteSCCBounds', ...
        'SCC transfer-bound catalog is incomplete.');
end
if Configuration_Index > numel(Bounds.Configuration_Allowed) || ...
        ~Bounds.Configuration_Allowed(Configuration_Index)
    error('AggregatedSecurity:InapplicableConfiguration', ...
        ['Typical day %d final configuration does not satisfy the SCC ', ...
        'aggregate calculation applicability conditions.'],Day_Index);
end

States = logical(Bounds.State_Catalog.SynchronousStates);
Union_Index = find(all(States == logical(Union_State(:).'),2),1);
if isempty(Union_Index)
    error('AggregatedSecurity:MissingUnionState', ...
        'Typical day %d SG-union state is absent from the catalog.',Day_Index);
end
if ~any(Bounds.Valid_Union_States(:,1) == Configuration_Index & ...
        Bounds.Valid_Union_States(:,2) == Union_Index)
    error('AggregatedSecurity:InapplicableUnionState', ...
        ['Typical day %d selected configuration/union-state pair is ', ...
        'not applicable to the SCC calculation.'],Day_Index);
end
for t = 1:size(Actual_States,2)
    Actual_Index = find(all(States == logical(Actual_States(:,t).'),2),1);
    Pair_Found = ~isempty(Actual_Index) && any( ...
        Bounds.Valid_State_Pairs(:,1) == Configuration_Index & ...
        Bounds.Valid_State_Pairs(:,2) == Union_Index & ...
        Bounds.Valid_State_Pairs(:,3) == Actual_Index);
    if ~Pair_Found
        error('AggregatedSecurity:InapplicableHourlyState', ...
            ['Typical day %d period %d is not an applicable SCC ', ...
            'configuration/union/actual-state combination.'],Day_Index,t);
    end
end
end

function Status = record_issue(Status,Metric,Day_Index,Cause)
Status = record_text_issue(Status,Metric,Day_Index, ...
    Cause.identifier,Cause.message);
end

function Status = record_text_issue(Status,Metric,Day_Index,Identifier,Message)
Issue = struct('Metric',Metric,'TypicalDay',Day_Index, ...
    'Identifier',Identifier,'Message',Message);
Status.Issues(end+1) = Issue;
end

function Binary_Value = validate_binary_result(Binary_Value,Value_Label)
if any(~isfinite(Binary_Value(:))) || ...
        any(abs(Binary_Value(:)-round(Binary_Value(:))) > 1e-5)
    error('AggregatedSecurity:InvalidDiscreteState', ...
        '%s is not a valid zero-one result.',Value_Label);
end
Binary_Value = round(Binary_Value);
end
