function Z_bounds = calculate_impedance_bounds(NET, CONF)
%CALCULATE_IMPEDANCE_BOUNDS 用两个极端工况估计阻抗矩阵元素上下界。
%
% 下界工况：全部同步机停运，全部 GFM 候选节点不投建。
% 上界工况：全部同步机投运，全部 GFM 候选节点投建。

N = NET.N;

gfm_mask = false(N,1);
gfm_mask(CONF.GFM_Candidates(:)) = true;

Y_min_support = NET.Y0;
Y_max_support = NET.Y0_all + sparse(find(gfm_mask), find(gfm_mask), ...
    1/(1i*CONF.X_GFM_res), N, N);

Z_min_support = local_inverse(Y_min_support);
Z_max_support = local_inverse(Y_max_support);

real_cases = CONF.KZ * cat(3, real(Z_min_support), real(Z_max_support));
imag_cases = CONF.KZ * cat(3, imag(Z_min_support), imag(Z_max_support));

real_min = min(real_cases, [], 3);
real_max = max(real_cases, [], 3);
imag_min = min(imag_cases, [], 3);
imag_max = max(imag_cases, [], 3);

if isfield(CONF, 'ZBoundMargin')
    margin = CONF.ZBoundMargin;
else
    margin = 0.05;
end

real_pad = local_padding(real_min, real_max, margin);
imag_pad = local_padding(imag_min, imag_max, margin);

real_lower = real_min - real_pad;
real_upper = real_max + real_pad;
imag_lower = imag_min - imag_pad;
imag_upper = imag_max + imag_pad;

real_abs_bound = max(abs(real_lower), abs(real_upper));
imag_abs_bound = max(abs(imag_lower), abs(imag_upper));

Z_bounds = struct();
Z_bounds.real_M = real_abs_bound;
Z_bounds.imag_M = imag_abs_bound;
Z_bounds.real_min = -real_abs_bound;
Z_bounds.real_max =  real_abs_bound;
Z_bounds.imag_min = -imag_abs_bound;
Z_bounds.imag_max =  imag_abs_bound;
Z_bounds.raw_real_min = real_min;
Z_bounds.raw_real_max = real_max;
Z_bounds.raw_imag_min = imag_min;
Z_bounds.raw_imag_max = imag_max;
Z_bounds.margin = margin;
Z_bounds.is_symmetric = true;
Z_bounds.rcond_min_support = rcond(full(Y_min_support));
Z_bounds.rcond_max_support = rcond(full(Y_max_support));

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
