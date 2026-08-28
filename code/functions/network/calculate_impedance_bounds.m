function Z_Bounds = calculate_impedance_bounds(NET, CONF)
%% 枚举《ver_2》配置方案与同步机状态并计算阻抗上下界。
% SCC采用典型日内同步机并集状态，故障转移网络采用该并集的逐时子状态；
% SCR采用典型日内同步机交集状态。不可逆组合写入目录并在优化中禁止出现。

CONF = normalize_multiple_snapshot_conf(CONF);

if ~isfield(NET, 'Y_0_Safety') || ~isfield(CONF, 'GFM_Config_Module_Matrix')
    error('《ver_2》阻抗预处理需要安全网络与GFM-ES配置方案目录。');
end

NS = NET.Safety_N;
G = NET.G;
NGFL = NET.Safety_GFL_Count;
GFL_Columns = NET.Safety_GFL_Reduced_Indices(:);
Configuration_Status = logical(CONF.GFM_Config_Module_Matrix);
C = size(Configuration_Status,1);

SG_States = local_build_binary_states(G);
State_Count = size(SG_States,1);
Y_SG_Unit = 1./(1i*CONF.Xd_Gen(:));
Y_GFM_Unit = 1./(1i*CONF.GFM_Module_X_Res(:));

SCC_Extrema = local_initialize_extrema(NS,NS);
SCR_Extrema = local_initialize_extrema(NS,NGFL);
Tau_Scaled = zeros(C,NS,NGFL);
Tau_Seen = false(C,NS,NGFL);
Invalid_Pairs = zeros(0,3); % [configuration, union-state, actual-state]
Valid_Pairs = zeros(0,3);
Configuration_Has_Valid_Pair = false(C,1);
Invalid_SCR_States = zeros(0,2); % [configuration, intersection-state]
Valid_SCR_States = zeros(0,2);
Configuration_Has_Valid_SCR_State = false(C,1);

for c = 1:C
    GFM_Status = Configuration_Status(c,:).';
    Y_GFM_Diag = NET.Safety_GFM_Module_Location_Matrix*(GFM_Status.*Y_GFM_Unit);

    % SCR交集状态不一定对应实际时段，因此独立枚举全部配置-交集状态组合。
    for SCR_Index = 1:State_Count
        u_SCR = SG_States(SCR_Index,:).';
        if ~local_source_online(u_SCR,GFM_Status,CONF.Require_Source_Online)
            Invalid_SCR_States(end+1,:) = [c,SCR_Index]; %#ok<AGROW>
            continue;
        end
        Y_SCR = NET.Y_0_Safety + spdiags( ...
            NET.Safety_Generator_Location_Matrix*(u_SCR.*Y_SG_Unit)+Y_GFM_Diag,0,NS,NS);
        [Z_SCR, SCR_Ok] = local_inverse(Y_SCR);
        if SCR_Ok && local_valid_transfer_impedances(Z_SCR,Z_SCR)
            Valid_SCR_States(end+1,:) = [c,SCR_Index]; %#ok<AGROW>
            Configuration_Has_Valid_SCR_State(c) = true;
            SCR_Extrema = local_update_extrema( ...
                SCR_Extrema,CONF.KZ*Z_SCR(:,GFL_Columns));
        else
            Invalid_SCR_States(end+1,:) = [c,SCR_Index]; %#ok<AGROW>
        end
    end

    for Union_Index = 1:State_Count
        u_Union = SG_States(Union_Index,:).';
        if ~local_source_online(u_Union,GFM_Status,CONF.Require_Source_Online)
            SCC_Ok = false;
            Z_SCC = [];
        else
            Y_SCC = NET.Y_0_Safety + spdiags( ...
                NET.Safety_Generator_Location_Matrix*(u_Union.*Y_SG_Unit)+Y_GFM_Diag,0,NS,NS);
            [Z_SCC,SCC_Ok] = local_inverse(Y_SCC);
        end

        for Actual_Index = 1:State_Count
            u_Actual = SG_States(Actual_Index,:).';
            if any(u_Actual > u_Union)
                continue;
            end

            if ~SCC_Ok || ~local_source_online( ...
                    u_Actual,GFM_Status,CONF.Require_Source_Online)
                Invalid_Pairs(end+1,:) = [c,Union_Index,Actual_Index]; %#ok<AGROW>
                continue;
            end

            Y_Fault = NET.Y_0_Safety + spdiags( ...
                NET.Safety_Generator_Location_Matrix*(u_Actual.*Y_SG_Unit)+Y_GFM_Diag,0,NS,NS);
            [Z_Fault,Fault_Ok] = local_inverse(Y_Fault);
            if ~Fault_Ok || ~local_valid_transfer_impedances(Z_SCC,Z_Fault)
                Invalid_Pairs(end+1,:) = [c,Union_Index,Actual_Index]; %#ok<AGROW>
                continue;
            end

            Valid_Pairs(end+1,:) = [c,Union_Index,Actual_Index]; %#ok<AGROW>
            Configuration_Has_Valid_Pair(c) = true;

            Z_SCC_Scaled = CONF.KZ*Z_SCC;
            SCC_Extrema = local_update_extrema(SCC_Extrema,Z_SCC_Scaled);

            % tau(c,n,p)为X_SCC(nn)*|Z_fault(np)/Z_fault(nn)|的KZ缩放值。
            x_SCC = imag(diag(Z_SCC));
            for n = 1:NS
                for GFL_Index = 1:NGFL
                    p = GFL_Columns(GFL_Index);

                    transfer_ratio = abs(Z_Fault(n,p) / Z_Fault(n,n));
                    candidate = CONF.KZ * x_SCC(n) * transfer_ratio;

                    Tau_Scaled(c,n,GFL_Index) = ...
                        max(Tau_Scaled(c,n,GFL_Index), candidate);
                    Tau_Seen(c,n,GFL_Index) = true;
                end
            end
        end
    end
end

if ~any(Configuration_Has_Valid_Pair)
    error('未找到可逆的《ver_2》SCC配置-状态组合。');
end
if ~any(Configuration_Has_Valid_SCR_State)
    error('未找到可逆的《ver_2》SCR配置-交集状态组合。');
end

% 可选配置必须同时存在有效SCC状态对、有效SCR交集状态，并具有完整tau上界。
Configuration_Allowed = Configuration_Has_Valid_Pair & Configuration_Has_Valid_SCR_State;
for c = 1:C
    if Configuration_Allowed(c) && ~all(Tau_Seen(c,:,:),'all')
        Configuration_Allowed(c) = false;
    end
end
if ~any(Configuration_Allowed)
    error('没有GFM-ES配置方案同时满足安全网络可逆性与完整故障转移上界要求。');
end

Z_Bounds = struct();
Z_Bounds.SCC = local_finalize_extrema(SCC_Extrema,CONF.ZBoundMargin);
Z_Bounds.SCR = local_finalize_extrema(SCR_Extrema,CONF.ZBoundMargin);
Z_Bounds.SCC.Column_Reduced_Indices = (1:NS).';
Z_Bounds.SCR.Column_Reduced_Indices = GFL_Columns;
Z_Bounds.Valid_Case_Count = size(Valid_Pairs,1);
Z_Bounds.Typical_Day_Count = CONF.TypicalDayCount;
Z_Bounds.Shared_Across_Typical_Days = true;
Z_Bounds.Tau_GFL_Scaled = Tau_Scaled;
Z_Bounds.Configuration_Allowed = Configuration_Allowed;
Z_Bounds.Valid_State_Pairs = Valid_Pairs;
Z_Bounds.Invalid_State_Pairs = Invalid_Pairs;
Z_Bounds.Valid_SCR_States = Valid_SCR_States;
Z_Bounds.Invalid_SCR_States = Invalid_SCR_States;
Z_Bounds.Valid_SCR_Case_Count = size(Valid_SCR_States,1);
Z_Bounds.State_Catalog = struct( ...
    'SynchronousStates',SG_States, ...
    'StateDefinition','[并集状态,实际状态]，且实际状态不大于并集状态');

end

function states = local_build_binary_states(n)
if n > 20
    error('同步机状态枚举最多支持20台机组。');
end
states = logical(dec2bin(0:(2^n-1))-'0');
end

function tf = local_source_online(u_SG,u_GFM,Require_Source)
tf = ~Require_Source || any(u_SG) || any(u_GFM);
end

function [Z,Is_Invertible] = local_inverse(Y)
Y_Full = full(Y);
if any(~isfinite(Y_Full(:))) || rcond(Y_Full) < 1e-10
    Z = [];
    Is_Invertible = false;
    return;
end
Z = Y_Full\eye(size(Y_Full));
Is_Invertible = all(isfinite(Z(:)));
end

function tf = local_valid_transfer_impedances(Z_SCC,Z_Fault)
if isempty(Z_SCC) || isempty(Z_Fault)
    tf = false;
    return;
end
x_SCC = imag(diag(Z_SCC));
x_Fault = imag(diag(Z_Fault));
tf = all(isfinite(x_SCC)) && all(isfinite(x_Fault)) && ...
    all(x_SCC > 1e-10) && all(x_Fault > 1e-10);
end

function extrema = local_initialize_extrema(n_Rows,n_Columns)
extrema.Real_Min = inf(n_Rows,n_Columns);
extrema.Real_Max = -inf(n_Rows,n_Columns);
extrema.Imag_Min = inf(n_Rows,n_Columns);
extrema.Imag_Max = -inf(n_Rows,n_Columns);
end

function extrema = local_update_extrema(extrema,Z_Case)
extrema.Real_Min = min(extrema.Real_Min,real(Z_Case));
extrema.Real_Max = max(extrema.Real_Max,real(Z_Case));
extrema.Imag_Min = min(extrema.Imag_Min,imag(Z_Case));
extrema.Imag_Max = max(extrema.Imag_Max,imag(Z_Case));
end

function bounds = local_finalize_extrema(extrema,margin)
if any(~isfinite(extrema.Real_Min(:))) || any(~isfinite(extrema.Real_Max(:))) || ...
        any(~isfinite(extrema.Imag_Min(:))) || any(~isfinite(extrema.Imag_Max(:)))
    error('阻抗上下界中存在未初始化元素。');
end
Real_Pad = local_padding(extrema.Real_Min,extrema.Real_Max,margin);
Imag_Pad = local_padding(extrema.Imag_Min,extrema.Imag_Max,margin);
bounds.Real_Min = extrema.Real_Min-Real_Pad;
bounds.Real_Max = extrema.Real_Max+Real_Pad;
bounds.Imag_Min = extrema.Imag_Min-Imag_Pad;
bounds.Imag_Max = extrema.Imag_Max+Imag_Pad;
end

function pad = local_padding(Lower_Bound,Upper_Bound,margin)
span = Upper_Bound-Lower_Bound;
scale = max(abs(Lower_Bound),abs(Upper_Bound));
pad = margin*max(span,scale);
pad = max(pad,1e-6);
end
