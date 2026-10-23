function [C, Security] = add_converter_security_constraints( ...
    NET, CONF, u_SG, u_Union, u_Intersection, u_Module)
%% 新版式(18)-(26)、(29)-(30)：直接决策的聚合SCC/SCR安全约束。
% SCC残压索引为[非故障/故障节点,故障节点,典型日]；不含场景维度。

SEC = prepare_converter_security_network(NET,CONF);
N = SEC.N;
D = CONF.TypicalDayCount;
T = CONF.PeriodCount;
G = NET.G;
M = CONF.GFM_Module_Count;
Q = G+M;
C = [];
Security = struct('Network',SEC,'Voltage',[],'SCC',[], ...
    'X_SCR',[],'Segment',[]);
if CONF.Enable_SCC
    Security.Voltage = sdpvar(N,N,D,'full');
    Security.SCC = sdpvar(N,D,'full');
end
if CONF.Enable_SCR
    Security.X_SCR = sdpvar(N,numel(SEC.GFL),D,'full');
end
for d = 1:D
    U_Sum = sum(reshape(u_SG(:,d,:),G,T),2);
    for t = 1:T
        % 式(18)-(20)：精确并集和交集逻辑。
        C = [C, u_Union(:,d) >= u_SG(:,d,t), ...
            u_Intersection(:,d) <= u_SG(:,d,t)]; %#ok<AGROW>
    end
    C = [C, u_Union(:,d) <= U_Sum, ...
        u_Intersection(:,d) >= U_Sum-(T-1)]; %#ok<AGROW>
    if ~(CONF.Enable_SCC || CONF.Enable_SCR)
        continue;
    end
    % 式(29)独立于运行充放电状态；交集网络必须有源支撑。
    C = [C, sum(u_Intersection(:,d))+sum(u_Module) >= 1]; %#ok<AGROW>
    if CONF.Enable_SCC
        Union_Sources = [u_Union(:,d);u_Module];
        Source = SEC.Source_Location*(SEC.Source_b.*Union_Sources);
        for n = 1:N
            J = setdiff((1:N).',n);
            % 式(30)作用于每一逐时UC状态，而不是交集或并集状态。
            for c = 1:numel(SEC.Fault_Components{n})
                Nodes = SEC.Fault_Components{n}{c};
                Source_Mask = full(sum(SEC.Source_Location(Nodes,:),1)).';
                for t = 1:T
                    C = [C, Source_Mask.'*[u_SG(:,d,t);u_Module] >= 1]; %#ok<AGROW>
                end
            end
            V = Security.Voltage(:,n,d);
            C = [C, 0 <= V, V <= 1, V(n) == 0]; %#ok<AGROW>
            % 式(21)：只需源所在节点的二进制-残压乘积。
            W = sdpvar(Q,1,'full');
            C = [C, add_binary_product_bounds(W,V(SEC.Source_Bus), ...
                Union_Sources,zeros(Q,1),ones(Q,1))]; %#ok<AGROW>
            Phi = sdpvar(N,1,'full');
            C = [C, Phi(setdiff((1:N).',SEC.GFL)) == 0]; %#ok<AGROW>
            for p = reshape(SEC.GFL,1,[])
                % 式(9)：有界分段析取的精确MILP表达，包含两个断点。
                [C_LVRT,z] = add_lvrt_segment_constraints(V(p),Phi(p), ...
                    SEC.LVRT_On(p),SEC.LVRT_Sat(p),SEC.LVRT_Slope(p),SEC.LVRT_Max(p));
                C = [C,C_LVRT]; %#ok<AGROW>
                Security.Segment = [Security.Segment;z]; %#ok<AGROW>
            end
            AV = SEC.A0*V+SEC.Source_Location*(SEC.Source_b.*W);
            % -B*1保留Kron数值矩阵的行和，避免隐式改变等式。
            RHS = SEC.A0*ones(N,1)+Source;
            C = [C, AV(J)-Phi(J) == RHS(J)]; %#ok<AGROW>
            % 式(4)、(22)：本地所有模块的虚拟阻抗修正求和。
            Beta = SEC.Module_Location(n,:)*(SEC.Module_Delta_b.*u_Module);
            C = [C, Security.SCC(n,d) == SEC.B0(n,J)*V(J) + ...
                RHS(n)-Beta+SEC.LVRT_Max(n), ...
                Security.SCC(n,d) <= CONF.I_limit(NET.Safety_Retained_Nodes(n))]; %#ok<AGROW>
        end
    end
    if CONF.Enable_SCR
        Intersection_Sources = [u_Intersection(:,d);u_Module];
        for k = 1:numel(SEC.GFL)
            n = SEC.GFL(k);
            X = Security.X_SCR(:,k,d);
            Upper = SEC.X_Upper(:,n);
            W = sdpvar(Q,1,'full');
            C = [C, 0 <= X, X <= Upper, ...
                add_binary_product_bounds(W,X(SEC.Source_Bus), ...
                Intersection_Sources,zeros(Q,1),Upper(SEC.Source_Bus))]; %#ok<AGROW>
            E = zeros(N,1); E(n) = 1;
            % 式(24)：-B交集*X=e；式(26)用系统基准标幺额定容量。
            C = [C, SEC.A0*X+SEC.Source_Location*(SEC.Source_b.*W) == E]; %#ok<AGROW>
            Bus = NET.Safety_Retained_Nodes(n);
            SCR_Min = CONF.SCR_min;
            if ~isscalar(SCR_Min), SCR_Min = SCR_Min(Bus); end
            C = [C, X(n) <= 1/(SCR_Min*CONF.PN_GFL_pu_Node(Bus))]; %#ok<AGROW>
        end
    end
end
end
