function [C_Imp, C_McCormick] = add_impedance_reconstruction_constraints( ...
    NET, CONF, Z_Bounds, u_SG_State, u_GFM_Module, Z_Real, Z_Imag, ...
    W_SGZ_X, W_SGZ_R, W_GFMZ_X, W_GFMZ_R, Column_Indices)
%% 建立典型日聚合安全状态的降阶电抗列重构约束。
% 对应Manuscript Section II-B, Eqs. (3)-(7)。实现保留复数变量外壳，
% 在无损网络下Z=jX，Z_Real由同一重构方程固定为零。

CONF = normalize_multiple_snapshot_conf(CONF);

N_Row = size(Z_Real,1);
N_Col = size(Z_Real,2);
M_GFM = CONF.GFM_Module_Count;
Generator_Location_Matrix = NET.Safety_Generator_Location_Matrix;
GFM_Module_Location_Matrix = NET.Safety_GFM_Module_Location_Matrix;
C_Imp = [];
C_McCormick = [];

if nargin < 12 || isempty(Column_Indices)
    Column_Indices = (1:N_Col).';
else
    Column_Indices = Column_Indices(:);
end
if N_Row ~= NET.Safety_N || numel(Column_Indices) ~= N_Col || ...
        any(Column_Indices < 1) || any(Column_Indices > N_Row)
    error('降阶阻抗列维度或列节点索引与安全网络不一致。');
end
if numel(u_SG_State) ~= NET.G || numel(u_GFM_Module) ~= M_GFM
    error('典型日聚合安全状态或GFM-ES模块状态维度不一致。');
end

% Manuscript Eq. (7)：同步机状态与所需电抗列的精确McCormick乘积。
Z_SG_Real = Generator_Location_Matrix'*Z_Real;
Z_SG_Imag = Generator_Location_Matrix'*Z_Imag;
U_SG_Row = repmat(u_SG_State,1,N_Col);
Z_SG_Real_L = Generator_Location_Matrix'*Z_Bounds.Real_Min;
Z_SG_Real_U = Generator_Location_Matrix'*Z_Bounds.Real_Max;
Z_SG_Imag_L = Generator_Location_Matrix'*Z_Bounds.Imag_Min;
Z_SG_Imag_U = Generator_Location_Matrix'*Z_Bounds.Imag_Max;

C_McCormick = [C_McCormick, add_binary_product_bounds( ...
    W_SGZ_X,Z_SG_Imag,U_SG_Row,Z_SG_Imag_L,Z_SG_Imag_U)];
C_McCormick = [C_McCormick, add_binary_product_bounds( ...
    W_SGZ_R,Z_SG_Real,U_SG_Row,Z_SG_Real_L,Z_SG_Real_U)];

% Manuscript Eq. (4)：同步机次暂态电纳为非正对角增量B_g^G=-1/Xd_g。
G_Sus = -1./CONF.Xd_Gen(:);
G_Sus_Mat = spdiags(G_Sus,0,NET.G,NET.G);
W_Sum_X = Generator_Location_Matrix*(G_Sus_Mat*W_SGZ_X);
W_Sum_R = Generator_Location_Matrix*(G_Sus_Mat*W_SGZ_R);

% Manuscript Eq. (7)：GFM-ES投建状态与所需电抗列的精确McCormick乘积。
Z_GFM_Real = GFM_Module_Location_Matrix'*Z_Real;
Z_GFM_Imag = GFM_Module_Location_Matrix'*Z_Imag;
U_GFM_Module_Row = repmat(u_GFM_Module,1,N_Col);
Z_GFM_Real_L = GFM_Module_Location_Matrix'*Z_Bounds.Real_Min;
Z_GFM_Real_U = GFM_Module_Location_Matrix'*Z_Bounds.Real_Max;
Z_GFM_Imag_L = GFM_Module_Location_Matrix'*Z_Bounds.Imag_Min;
Z_GFM_Imag_U = GFM_Module_Location_Matrix'*Z_Bounds.Imag_Max;

C_McCormick = [C_McCormick, add_binary_product_bounds( ...
    W_GFMZ_X,Z_GFM_Imag,U_GFM_Module_Row,Z_GFM_Imag_L,Z_GFM_Imag_U)];
C_McCormick = [C_McCormick, add_binary_product_bounds( ...
    W_GFMZ_R,Z_GFM_Real,U_GFM_Module_Row,Z_GFM_Real_L,Z_GFM_Real_U)];

B_GFM_Mat = spdiags(NET.B_GFM_Module(:),0,M_GFM,M_GFM);
W_GFM_Sum_X = GFM_Module_Location_Matrix*(B_GFM_Mat*W_GFMZ_X);
W_GFM_Sum_R = GFM_Module_Location_Matrix*(B_GFM_Mat*W_GFMZ_R);

% Manuscript Eq. (6)：B*X=-I。下式是对缩放复数关系Y*Z=KZ*I的
% 实、虚部分解，其中B_0=Im[Y_0]，且安全网络的real(Y_0)=0。
B_0 = NET.B_0_Safety;
LHS_Real = -B_0*Z_Imag - W_Sum_X - W_GFM_Sum_X;
LHS_Imag =  B_0*Z_Real + W_Sum_R + W_GFM_Sum_R;
I_Columns = sparse(Column_Indices,(1:N_Col).',1,N_Row,N_Col)*CONF.KZ;

C_Imp = [C_Imp, ...
    LHS_Real(:)-I_Columns(:) >= -CONF.ERR_TOL, ...
    LHS_Real(:)-I_Columns(:) <=  CONF.ERR_TOL];
C_Imp = [C_Imp, ...
    LHS_Imag(:) >= -CONF.ERR_TOL, ...
    LHS_Imag(:) <=  CONF.ERR_TOL];

end
