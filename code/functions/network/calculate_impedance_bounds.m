function Z_bounds = calculate_impedance_bounds(NET, CONF)
%% 本函数功能是枚举离散投运组合并估计阻抗矩阵逐元素上下界。
% 阻抗上下界用于二进制-连续变量乘积的McCormick线性化。
% 同步机组合始终纳入全停状态；无电压源状态由Require_Source_Online剔除。
% GFM-ES组合枚举满足模块投建规则的全部状态。

%% 1. 生成离散投运组合
N = NET.N;
G = NET.G;

sg_cases = local_build_sg_cases(G);
gfm_cases = local_build_gfm_module_cases(CONF);

%% 2. 枚举组合并记录阻抗矩阵元素极值
real_min =  inf(N,N);
real_max = -inf(N,N);
imag_min =  inf(N,N);
imag_max = -inf(N,N);

Y_sg_unit  = 1/(1i*CONF.Xd_Gen);
Y_gfm_mod = 1 ./ (1i*CONF.GFM_Module_X_res(:));

for sg_idx = 1:size(sg_cases, 1)
    sg_status = sg_cases(sg_idx,:).';
    Y_sg_diag = (NET.Gen_Loc_Mat * sg_status) * Y_sg_unit;

    for gfm_idx = 1:size(gfm_cases, 1)
        gfm_status = gfm_cases(gfm_idx,:).';

        if CONF.Require_Source_Online && ~any(sg_status) && ~any(gfm_status)
            continue;
        end

        Y_gfm_diag = CONF.GFM_Module_Loc_Mat * (gfm_status .* Y_gfm_mod);

        Y_case = NET.Y0 + sparse(1:N, 1:N, Y_sg_diag + Y_gfm_diag, N, N);

        Z_case = local_inverse(Y_case);
        Z_real_case = CONF.KZ * real(Z_case);
        Z_imag_case = CONF.KZ * imag(Z_case);

        real_min = min(real_min, Z_real_case);
        real_max = max(real_max, Z_real_case);
        imag_min = min(imag_min, Z_imag_case);
        imag_max = max(imag_max, Z_imag_case);
    end
end

%% 3. 添加安全裕度并输出上下界
margin = CONF.ZBoundMargin;

real_pad = local_padding(real_min, real_max, margin);
imag_pad = local_padding(imag_min, imag_max, margin);

real_lower = real_min - real_pad;
real_upper = real_max + real_pad;
imag_lower = imag_min - imag_pad;
imag_upper = imag_max + imag_pad;

Z_bounds = struct();
Z_bounds.real_min = real_lower;
Z_bounds.real_max = real_upper;
Z_bounds.imag_min = imag_lower;
Z_bounds.imag_max = imag_upper;

end

function sg_cases = local_build_sg_cases(G)
% 该函数生成同步机投运组合。
sg_cases = dec2bin(0:(2^G-1))-'0';

end

function gfm_cases = local_build_gfm_module_cases(CONF)
% 该函数生成所有允许的GFM-ES模块投建组合。

n_modules = CONF.GFM_Module_Count;
eligible_modules = (1:n_modules).';

max_modules = min(floor(CONF.N_GFM_Module_Max), numel(eligible_modules));

gfm_cases = false(1, n_modules);

for k = 1:max_modules
    combos = nchoosek(eligible_modules, k);

    for row = 1:size(combos, 1)
        status = false(1, n_modules);
        status(combos(row,:)) = true;

        if local_is_sequential_status(status, CONF)
            gfm_cases = [gfm_cases; status]; %#ok<AGROW>
        end
    end
end
end

function is_valid = local_is_sequential_status(status, CONF)
% 该函数检查同一候选节点内的模块是否按序投建。

if ~CONF.GFM_Module_Sequential
    is_valid = true;
    return;
end

module_bus = CONF.GFM_Module_Bus(:);
module_order = CONF.GFM_Module_Order(:);
unique_bus = unique(module_bus, 'stable');
is_valid = true;

for k = 1:numel(unique_bus)
    idx = find(module_bus == unique_bus(k));
    [~, order_idx] = sort(module_order(idx));
    idx = idx(order_idx);
    status_ordered = status(idx);

    if any(status_ordered(2:end) > status_ordered(1:end-1))
        is_valid = false;
        return;
    end
end
end

function Z = local_inverse(Y)
% 该函数计算导纳矩阵逆矩阵，病态时使用伪逆兜底。

Y_full = full(Y);
if rcond(Y_full) < 1e-10
    Z = pinv(Y_full);
else
    Z = inv(Y_full);
end
end

function pad = local_padding(lower_bound, upper_bound, margin)
% 该函数根据元素范围和绝对尺度生成上下界裕度。

span = upper_bound - lower_bound;
scale = max(abs(lower_bound), abs(upper_bound));
pad = margin * max(span, scale);
pad = max(pad, 1e-6);
end
