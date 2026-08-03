function CATALOG = build_gfm_configuration_catalog(GFM_Modules)
%% 枚举满足投建规则的GFM-ES模块配置方案。
% 配置目录属于离线参数集；优化模型通过lambda_c选择其中一行，
% 再将所选方案映射回各模块投建状态。

M = GFM_Modules.Count;
N = numel(GFM_Modules.Candidate_Bus);
E = max(GFM_Modules.Order);

if M > 20
    error('GFM-ES配置方案枚举最多支持20个模块。');
end
if any(GFM_Modules.Candidate_Index < 1 | GFM_Modules.Candidate_Index > N) || ...
        any(GFM_Modules.Order < 1 | GFM_Modules.Order > E)
    error('GFM-ES模块候选节点索引或模块序号无效。');
end

% 先枚举全部模块状态，再保留满足模块总数与顺序投建规则的方案；
% 不投建任何模块的零配置也属于可行方案。
All_Status = logical(dec2bin(0:(2^M-1)) - '0');
keep = sum(All_Status,2) <= floor(GFM_Modules.N_Module_Max);
All_Status = All_Status(keep,:);

if GFM_Modules.Enforce_Sequential_Build
    keep = false(size(All_Status,1),1);
    for r = 1:size(All_Status,1)
        keep(r) = local_is_sequential(All_Status(r,:), ...
            GFM_Modules.Candidate_Index(:), GFM_Modules.Order(:), N);
    end
    All_Status = All_Status(keep,:);
end

if isempty(All_Status)
    error('未枚举到满足投建规则的GFM-ES配置方案。');
end

Candidate_Module_Mat = sparse(GFM_Modules.Candidate_Index(:), ...
    (1:M).', 1, N, M);
Candidate_Status = double(All_Status)*full(Candidate_Module_Mat.');

% a(c,n,e)对应文档中的配置方案映射参数。
A_CNE = zeros(size(All_Status,1),N,E);
for m = 1:M
    A_CNE(:,GFM_Modules.Candidate_Index(m),GFM_Modules.Order(m)) = ...
        double(All_Status(:,m));
end

CATALOG = struct();
CATALOG.Count = size(All_Status,1);
CATALOG.Module_Status = double(All_Status);
CATALOG.Candidate_Status = Candidate_Status;
CATALOG.A_CNE = A_CNE;
CATALOG.Module_Count = sum(All_Status,2);

end

function Is_Valid = local_is_sequential(status, Candidate_Index, order, Candidate_Count)
Is_Valid = true;
for n = 1:Candidate_Count
    idx = find(Candidate_Index == n);
    [~,Sort_Index] = sort(order(idx));
    Ordered_Status = status(idx(Sort_Index));
    if any(Ordered_Status(2:end) > Ordered_Status(1:end-1))
        Is_Valid = false;
        return;
    end
end
end
