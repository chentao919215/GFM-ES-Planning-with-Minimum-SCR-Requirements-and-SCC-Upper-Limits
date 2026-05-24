function Z_bounds = calculate_impedance_bounds(NET, CONF)
%CALCULATE_IMPEDANCE_BOUNDS 枚举离散投运组合并估计阻抗矩阵逐元素上下界。
%
% 同步机组合枚举全部非全停状态，共 2^G-1 种。
% GFM-ES 组合枚举候选节点中投建数量不超过 CONF.N_GFM_max 的全部状态。

N = NET.N;
G = NET.G;

sg_cases = dec2bin(1:(2^G-1)) - '0';
gfm_cases = local_build_gfm_cases(N, CONF);

real_min = inf(N,N);
real_max = -inf(N,N);
imag_min = inf(N,N);
imag_max = -inf(N,N);

Y_sg_unit = 1/(1i*CONF.Xd_Gen);
Y_gfm_unit = 1/(1i*CONF.X_GFM_res);

for sg_idx = 1:size(sg_cases, 1)
    sg_status = sg_cases(sg_idx,:).';
    Y_sg_diag = (NET.Gen_Loc_Mat * sg_status) * Y_sg_unit;

    for gfm_idx = 1:size(gfm_cases, 1)
        gfm_status = gfm_cases(gfm_idx,:).';
        Y_gfm_diag = gfm_status * Y_gfm_unit;
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

function gfm_cases = local_build_gfm_cases(N, CONF)
candidate_nodes = CONF.GFM_Candidates(:).';
candidate_nodes = candidate_nodes(CONF.u_GFL(candidate_nodes) == 0);

max_gfm = min(CONF.N_GFM_max, numel(candidate_nodes));
num_cases = sum(arrayfun(@(k) nchoosek(numel(candidate_nodes), k), 0:max_gfm));
gfm_cases = false(num_cases, N);

case_idx = 1;
for k = 0:max_gfm
    if k == 0
        case_idx = case_idx + 1;
    else
        combos = nchoosek(candidate_nodes, k);
        for row = 1:size(combos, 1)
            gfm_cases(case_idx, combos(row,:)) = true;
            case_idx = case_idx + 1;
        end
    end
end
end

function Z = local_inverse(Y)
Y_full = full(Y);
if rcond(Y_full) < 1e-10
    Z = pinv(Y_full);
else
    Z = inv(Y_full);
end
end

function pad = local_padding(lower_bound, upper_bound, margin)
span = upper_bound - lower_bound;
scale = max(abs(lower_bound), abs(upper_bound));
pad = margin * max(span, scale);
pad = max(pad, 1e-6);
end
