function C_lvrt = add_gfl_lvrt_residual_constraints( ...
    NET, CONF, u_SG_SCR, u_GFM_mod, V_F, V0, Vlin, Vsat, ...
    D0, Dlin, Dsat, DeltaI, Zeta_SG, Zeta_GFM)
%ADD_GFL_LVRT_RESIDUAL_CONSTRAINTS
% Build the ver_2 three-segment LVRT and intersection-state residual-voltage
% feedback model.  All dimensions are safety-network dimensions.

NS = NET.Safety_N;
G = NET.G;
M = CONF.GFM_Module_Count;
D = CONF.TypicalDayCount;
gfl_reduced = NET.Safety_GFL_Reduced_Indices(:);
gfl_count = numel(gfl_reduced);

if size(V_F,1) ~= NS || size(V_F,2) ~= NS || size(V_F,3) ~= D
    error('Residual-voltage variable dimensions are inconsistent.');
end
if size(DeltaI,1) ~= NS || size(DeltaI,2) ~= gfl_count || ...
        size(DeltaI,3) ~= D
    error('LVRT increment-current variable dimensions are inconsistent.');
end
if size(Zeta_SG,1) ~= G || size(Zeta_SG,2) ~= NS || ...
        size(Zeta_SG,3) ~= NS || size(Zeta_SG,4) ~= D
    error('Synchronous-machine LVRT McCormick variable dimensions are inconsistent.');
end
if size(Zeta_GFM,1) ~= M || size(Zeta_GFM,2) ~= NS || ...
        size(Zeta_GFM,3) ~= NS || size(Zeta_GFM,4) ~= D
    error('GFM-ES LVRT McCormick variable dimensions are inconsistent.');
end

B0 = -imag(NET.Y0_Safety);
b_sg = -imag(1./(1i*CONF.Xd_Gen(:)));
b_gfm = 1./CONF.GFM_Module_X_res(:);

C_lvrt = [V_F(:) >= 0, V_F(:) <= 1, ...
    DeltaI >= 0, DeltaI <= repmat( ...
    CONF.Delta_I_GFL_pu_Node(NET.Safety_Retained_Nodes(gfl_reduced)).',NS,1,D)];

for d = 1:D
    C_lvrt = [C_lvrt, diag(V_F(:,:,d)) == 0]; %#ok<AGROW>

    for p = 1:NS
        % zeta_SG(g,n,p,d) = u_SG_SCR(g,d)*V_F(n,p,d)
        U_sg = repmat(u_SG_SCR(:,d),1,NS);
        X_sg = repmat(V_F(:,p,d).',G,1);
        C_lvrt = [C_lvrt, add_binary_product_bounds( ...
            Zeta_SG(:,:,p,d),X_sg,U_sg,zeros(G,NS),ones(G,NS))]; %#ok<AGROW>

        % zeta_GFM(e,n,p,d) = u_GFM_mod(e)*V_F(n,p,d)
        U_gfm = repmat(u_GFM_mod,1,NS);
        X_gfm = repmat(V_F(:,p,d).',M,1);
        C_lvrt = [C_lvrt, add_binary_product_bounds( ...
            Zeta_GFM(:,:,p,d),X_gfm,U_gfm,zeros(M,NS),ones(M,NS))]; %#ok<AGROW>

        p_original = NET.Safety_Retained_Nodes(p);
        gfl_idx = find(gfl_reduced == p,1);
        module_idx = find(NET.Safety_GFM_Module_Loc_Mat(p,:));

        for n = 1:NS
            if p == n
                % Fault-node GFL current is handled by the saturated
                % fault-node term in the SCC constraint, not by LVRT.
                if ~isempty(gfl_idx)
                    C_lvrt = [C_lvrt, ...
                        D0(n,gfl_idx,d) == 0, ...
                        Dlin(n,gfl_idx,d) == 0, ...
                        Dsat(n,gfl_idx,d) == 0, ...
                        V0(n,gfl_idx,d) == 0, ...
                        Vlin(n,gfl_idx,d) == 0, ...
                        Vsat(n,gfl_idx,d) == 0, ...
                        DeltaI(n,gfl_idx,d) == 0]; %#ok<AGROW>
                end
                continue;
            end

            if ~isempty(gfl_idx)
                von = CONF.V_LVRT_On_Node(p_original);
                vsat = CONF.V_LVRT_Sat_Node(p_original);
                delta_i = DeltaI(n,gfl_idx,d);
                C_lvrt = [C_lvrt, ...
                    D0(n,gfl_idx,d)+Dlin(n,gfl_idx,d)+Dsat(n,gfl_idx,d) == 1, ...
                    von*D0(n,gfl_idx,d) <= V0(n,gfl_idx,d), ...
                    V0(n,gfl_idx,d) <= D0(n,gfl_idx,d), ...
                    vsat*Dlin(n,gfl_idx,d) <= Vlin(n,gfl_idx,d), ...
                    Vlin(n,gfl_idx,d) <= von*Dlin(n,gfl_idx,d), ...
                    0 <= Vsat(n,gfl_idx,d), ...
                    Vsat(n,gfl_idx,d) <= vsat*Dsat(n,gfl_idx,d), ...
                    delta_i == CONF.KQ_GFL_Node(p_original)* ...
                        CONF.I_GFL_N_pu_Node(p_original)* ...
                        (von*Dlin(n,gfl_idx,d)-Vlin(n,gfl_idx,d)) + ...
                        CONF.Delta_I_GFL_pu_Node(p_original)* ...
                        Dsat(n,gfl_idx,d), ...
                    V_F(n,p,d) == ...
                        V0(n,gfl_idx,d)+Vlin(n,gfl_idx,d)+Vsat(n,gfl_idx,d)]; %#ok<AGROW>
                % Keep the sign convention of equations (1.61)-(1.62):
                % DeltaI_GFL is the positive scalar current term on the
                % right-hand side of the residual-voltage balance.
                rhs = delta_i;
            else
                rhs = 0;
            end

            sg_at_p = b_sg.*full(NET.Safety_Gen_Loc_Mat(p,:)).';
            sg_term = sg_at_p.'*(Zeta_SG(:,n,p,d)-u_SG_SCR(:,d));
            if isempty(module_idx)
                gfm_term = 0;
            else
                gfm_term = b_gfm(module_idx).' * ...
                    (Zeta_GFM(module_idx,n,p,d)-u_GFM_mod(module_idx));
            end
            lhs = sum(B0(p,[1:n-1,n+1:NS]).* ...
                V_F(n,[1:n-1,n+1:NS],d)) + sg_term + gfm_term;
            C_lvrt = [C_lvrt, lhs == rhs]; %#ok<AGROW>
        end
    end
end
end
