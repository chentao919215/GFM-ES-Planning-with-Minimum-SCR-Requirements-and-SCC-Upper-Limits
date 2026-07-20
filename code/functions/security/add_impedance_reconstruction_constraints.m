function C_imp = add_impedance_reconstruction_constraints( ...
    NET, CONF, Z_bounds, u_SG_state, u_GFM_mod, Z_real, Z_imag, ...
    W_SGZ_X, W_SGZ_R, W_GFMZ_X, W_GFMZ_R, column_indices)
%% 本函数功能是建立一个典型日聚合安全工况的降阶阻抗列重构约束。

N_row = size(Z_real,1);
N_col = size(Z_real,2);
M_GFM = CONF.GFM_Module_Count;
Gen_Loc_Mat = NET.Safety_Gen_Loc_Mat;
GFM_Module_Loc_Mat = NET.Safety_GFM_Module_Loc_Mat;
C_imp = [];

if nargin < 12 || isempty(column_indices)
    column_indices = (1:N_col).';
else
    column_indices = column_indices(:);
end
if N_row ~= NET.Safety_N || numel(column_indices) ~= N_col || ...
        any(column_indices < 1) || any(column_indices > N_row)
    error('降阶阻抗列维度或列节点索引与安全网络不一致。');
end
if numel(u_SG_state) ~= NET.G || numel(u_GFM_mod) ~= M_GFM
    error('典型日聚合安全状态或GFM-ES模块状态维度不一致。');
end

% 同步机支路贡献:W_SGZ_*=u_SG_state.*Z(同步机接入节点,:)。
Z_SG_real = Gen_Loc_Mat'*Z_real;
Z_SG_imag = Gen_Loc_Mat'*Z_imag;
U_SG_Row = repmat(u_SG_state,1,N_col);
Z_SG_real_L = Gen_Loc_Mat'*Z_bounds.real_min;
Z_SG_real_U = Gen_Loc_Mat'*Z_bounds.real_max;
Z_SG_imag_L = Gen_Loc_Mat'*Z_bounds.imag_min;
Z_SG_imag_U = Gen_Loc_Mat'*Z_bounds.imag_max;

C_imp = [C_imp, add_binary_product_bounds( ...
    W_SGZ_X,Z_SG_imag,U_SG_Row,Z_SG_imag_L,Z_SG_imag_U)];
C_imp = [C_imp, add_binary_product_bounds( ...
    W_SGZ_R,Z_SG_real,U_SG_Row,Z_SG_real_L,Z_SG_real_U)];

% 同步机次暂态导纳按机组分别建模：y_g^G=-j/Xd_g。
G_sus = -1./CONF.Xd_Gen(:);
G_sus_mat = spdiags(G_sus,0,NET.G,NET.G);
W_sum_X = Gen_Loc_Mat*(G_sus_mat*W_SGZ_X);
W_sum_R = Gen_Loc_Mat*(G_sus_mat*W_SGZ_R);

% GFM-ES模块贡献:W_GFMZ_*=u_GFM_mod.*Z(模块接入节点,:)。
Z_GFM_real = GFM_Module_Loc_Mat'*Z_real;
Z_GFM_imag = GFM_Module_Loc_Mat'*Z_imag;
U_GFM_Mod_Row = repmat(u_GFM_mod,1,N_col);
Z_GFM_real_L = GFM_Module_Loc_Mat'*Z_bounds.real_min;
Z_GFM_real_U = GFM_Module_Loc_Mat'*Z_bounds.real_max;
Z_GFM_imag_L = GFM_Module_Loc_Mat'*Z_bounds.imag_min;
Z_GFM_imag_U = GFM_Module_Loc_Mat'*Z_bounds.imag_max;

C_imp = [C_imp, add_binary_product_bounds( ...
    W_GFMZ_X,Z_GFM_imag,U_GFM_Mod_Row,Z_GFM_imag_L,Z_GFM_imag_U)];
C_imp = [C_imp, add_binary_product_bounds( ...
    W_GFMZ_R,Z_GFM_real,U_GFM_Mod_Row,Z_GFM_real_L,Z_GFM_real_U)];

B_gfm_mat = spdiags(NET.B_gfm_mod(:),0,M_GFM,M_GFM);
W_gfm_sum_X = GFM_Module_Loc_Mat*(B_gfm_mat*W_GFMZ_X);
W_gfm_sum_R = GFM_Module_Loc_Mat*(B_gfm_mat*W_GFMZ_R);

% 将复数矩阵方程拆成实部和虚部两个线性约束组。
Y0_R = real(NET.Y0_Safety);
Y0_I = imag(NET.Y0_Safety);
LHS_Real = Y0_R*Z_real - Y0_I*Z_imag - W_sum_X - W_gfm_sum_X;
LHS_Imag = Y0_R*Z_imag + Y0_I*Z_real + W_sum_R + W_gfm_sum_R;
I_columns = sparse(column_indices,(1:N_col).',1,N_row,N_col)*CONF.KZ;

C_imp = [C_imp, ...
    LHS_Real(:)-I_columns(:) >= -CONF.ERR_TOL, ...
    LHS_Real(:)-I_columns(:) <=  CONF.ERR_TOL];
C_imp = [C_imp, ...
    LHS_Imag(:) >= -CONF.ERR_TOL, ...
    LHS_Imag(:) <=  CONF.ERR_TOL];

end
