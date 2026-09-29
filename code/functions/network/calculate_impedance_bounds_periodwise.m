function Z_Bounds = calculate_impedance_bounds_periodwise(NET, CONF, Need_SCC, Need_SCR)
%% 枚举实际逐时同步机状态，预处理PW阻抗界与不可用网络。
% 对应Manuscript Section II-B，式(3)-(7)的离线参数计算。此处不构造
% 并集/交集状态、转移系数或聚合状态对。

CONF = normalize_multiple_snapshot_conf(CONF);
NS = NET.Safety_N;
G = NET.G;
GFL_Columns = NET.Safety_GFL_Reduced_Indices(:);
Configuration_Status = logical(CONF.GFM_Config_Module_Matrix);
C = size(Configuration_Status,1);

if G > 20
    error('同步机状态枚举最多支持20台机组。');
end
SG_States = logical(dec2bin(0:(2^G-1))-'0');
State_Count = size(SG_States,1);
SCC_Min = inf(NS,NS);
SCC_Max = -inf(NS,NS);
SCR_Min = inf(NS,numel(GFL_Columns));
SCR_Max = -inf(NS,numel(GFL_Columns));
Valid_States = zeros(0,2); % [configuration, actual SG state]
Invalid_States = zeros(0,2);
Configuration_Allowed = false(C,1);
B_SG_Unit = -1./CONF.Xd_Gen(:);
B_GFM_Unit = -1./CONF.GFM_Module_X_Res(:);

for c = 1:C
    GFM_Status = Configuration_Status(c,:).';
    GFM_Diagonal = NET.Safety_GFM_Module_Location_Matrix* ...
        (GFM_Status.*B_GFM_Unit);
    for s = 1:State_Count
        SG_Status = SG_States(s,:).';
        if CONF.Require_Source_Online && ~any(SG_Status) && ~any(GFM_Status)
            Invalid_States(end+1,:) = [c,s]; %#ok<AGROW>
            continue;
        end
        B = NET.B_0_Safety + spdiags( ...
            NET.Safety_Generator_Location_Matrix*(SG_Status.*B_SG_Unit) + ...
            GFM_Diagonal,0,NS,NS);
        B_Full = full(B);
        if any(~isfinite(B_Full(:))) || rcond(B_Full) < 1e-12
            Invalid_States(end+1,:) = [c,s]; %#ok<AGROW>
            continue;
        end
        X = -(B_Full\eye(NS));
        if any(~isfinite(X(:))) || any(diag(X) <= 1e-10) || ...
                any(X(:) < -1e-10)
            Invalid_States(end+1,:) = [c,s]; %#ok<AGROW>
            continue;
        end
        Valid_States(end+1,:) = [c,s]; %#ok<AGROW>
        Configuration_Allowed(c) = true;
        X_Scaled = CONF.KZ*X;
        if Need_SCC
            SCC_Min = min(SCC_Min,X_Scaled);
            SCC_Max = max(SCC_Max,X_Scaled);
        end
        if Need_SCR
            SCR_Min = min(SCR_Min,X_Scaled(:,GFL_Columns));
            SCR_Max = max(SCR_Max,X_Scaled(:,GFL_Columns));
        end
    end
end

if ~any(Configuration_Allowed)
    error('没有GFM-ES配置方案满足逐时安全网络适用条件。');
end
Z_Bounds = struct();
Z_Bounds.SCC = [];
Z_Bounds.SCR = [];
if Need_SCC
    Z_Bounds.SCC = finalize_bounds(SCC_Min,SCC_Max,CONF.ZBoundMargin);
    Z_Bounds.SCC.Column_Reduced_Indices = (1:NS).';
end
if Need_SCR
    Z_Bounds.SCR = finalize_bounds(SCR_Min,SCR_Max,CONF.ZBoundMargin);
    Z_Bounds.SCR.Column_Reduced_Indices = GFL_Columns;
end
Z_Bounds.Configuration_Allowed = Configuration_Allowed;
Z_Bounds.Valid_States = Valid_States;
Z_Bounds.Invalid_States = Invalid_States;
Z_Bounds.State_Catalog = struct('SynchronousStates',SG_States, ...
    'StateDefinition','[configuration, actual period SG state]');
end

function Bounds = finalize_bounds(Lower,Upper,Margin)
if any(~isfinite(Lower(:))) || any(~isfinite(Upper(:)))
    error('逐时阻抗上下界中存在未初始化元素。');
end
Imag_Pad = Margin*max(Upper-Lower,max(abs(Lower),abs(Upper)));
Imag_Pad = max(Imag_Pad,1e-6);
Bounds.Real_Min = -1e-6*ones(size(Lower));
Bounds.Real_Max =  1e-6*ones(size(Upper));
Bounds.Imag_Min = Lower-Imag_Pad;
Bounds.Imag_Max = Upper+Imag_Pad;
end
