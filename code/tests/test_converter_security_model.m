function Tests = test_converter_security_model
%% 新版模型的无求解器模块测试、结构测试与枚举安全性测试。
Tests = functiontests(localfunctions);
end

function setupOnce(Test)
Root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(genpath(fullfile(Root,'code','functions')));
[Test.TestData.mpc,Test.TestData.CONF] = build_converter_test_case();
end

function testUnionIntersectionTruthTable(Test)
for bits = 0:7
    u = bitget(bits,1:3);
    for Union = 0:1
        for Intersection = 0:1
            Feasible = all(Union >= u) && Union <= sum(u) && ...
                all(Intersection <= u) && Intersection >= sum(u)-2;
            verifyEqual(Test,Feasible,Union == max(u) && Intersection == min(u));
        end
    end
end
end

function testLocalCorrectionAndRemoteWind(Test)
C = Test.TestData.CONF;
NET = build_multiple_snapshot_network(Test.TestData.mpc,C);
SEC = prepare_converter_security_network(NET,C);
[SCC,~,Detail] = calculate_converter_security_state(SEC,C,[1;1],[1;1]);
Without_Virtual = SEC;
Without_Virtual.Module_Delta_b(:) = 0;
[SCC_0,~,Detail_0] = calculate_converter_security_state(Without_Virtual,C,[1;1],[1;1]);
verifyEqual(Test,Detail.Voltage,Detail_0.Voltage,'AbsTol',1e-12);
verifyEqual(Test,SCC_0-SCC,[0;0;sum(SEC.Module_Delta_b)*C.Base_kA],'AbsTol',1e-10);
No_Wind = SEC;
No_Wind.LVRT_Max(:) = 0;
No_Wind.LVRT_Slope(:) = 0;
SCC_No_Wind = calculate_converter_security_state(No_Wind,C,[1;1],[1;1]);
verifyGreaterThan(Test,SCC(1),SCC_No_Wind(1));
verifyLessThan(Test,max(Detail.Residual),1e-8);
end

function testEnumeratedConservatismAndBounds(Test)
C = Test.TestData.CONF;
NET = build_multiple_snapshot_network(Test.TestData.mpc,C);
SEC = prepare_converter_security_network(NET,C);
Comparisons = 0;
for m = 0:3
    Modules = bitget(m,1:2).';
    for a = 0:3
        for b = 0:3
            Hourly = [bitget(a,1:2).',bitget(b,1:2).'];
            Union = max(Hourly,[],2);
            Intersection = min(Hourly,[],2);
            if sum(Intersection)+sum(Modules) == 0, continue; end
            Valid = true;
            for t = 1:2
                Source = SEC.Source_Location*[Hourly(:,t);Modules];
                for n = 1:3
                    for c = 1:numel(SEC.Fault_Components{n})
                        Valid = Valid && sum(Source(SEC.Fault_Components{n}{c})) > 0;
                    end
                end
            end
            if ~Valid, continue; end
            SCC_U = calculate_converter_security_state(SEC,C,Union,Modules,true,false);
            [~,SCR_I,XI] = calculate_converter_security_state(SEC,C,Intersection,Modules,false,true);
            verifyLessThanOrEqual(Test,max(XI.X-SEC.X_Upper,[],'all'),1e-9);
            for t = 1:2
                [SCC_H,SCR_H] = calculate_converter_security_state(SEC,C,Hourly(:,t),Modules);
                verifyLessThanOrEqual(Test,max(SCC_H-SCC_U),1e-9);
                verifyLessThanOrEqual(Test,max(SCR_I-SCR_H),1e-9);
                Comparisons = Comparisons+1;
            end
        end
    end
end
verifyGreaterThan(Test,Comparisons,20);
fprintf('Enumerated hourly security comparisons: %d\n',Comparisons);
end

function testPostfaultComponents(Test)
C = Test.TestData.CONF;
NET = build_multiple_snapshot_network(Test.TestData.mpc,C);
NET.B_0_Safety = [-1 1 0;1 -2 1;0 1 -1];
SEC = prepare_converter_security_network(NET,C);
verifyEqual(Test,numel(SEC.Fault_Components{2}),2);
% 移除节点2后，只有节点1有源，节点3必须被识别为不适用。
Did_Fail = false;
try
    calculate_converter_security_state(SEC,C,[1;1],[0;0]);
catch Cause
    Did_Fail = contains(Cause.message,'式(30)');
end
verifyTrue(Test,Did_Fail);
end

function testLinearStructureAndSharedDimensions(Test)
assumeTrue(Test,exist('sdpvar','file') ~= 0,'YALMIP unavailable');
C = Test.TestData.CONF;
Model = build_multiple_snapshot_planning_model(Test.TestData.mpc,C);
verifyTrue(Test,all(is(Model.Constraints,'linear')));
verifyEqual(Test,size(Model.Variables.u_SG),[2 2 3]);
verifyEqual(Test,size(Model.Variables.P_SG),[2 2 2 3]);
verifyEqual(Test,size(Model.Variables.u_GFM_Module),[1 2]);
verifyEqual(Test,size(Model.Security.Voltage),[3 3 2]);
verifyEqual(Test,size(Model.Security.X_SCR),[3 2 2]);
verifyFalse(Test,isfield(Model.Variables,'Lambda_Configuration'));
verifyFalse(Test,isfield(Model.Variables,'z_SG_Union'));
end

function testLVRTSegmentsAndMcCormick(Test)
assumeTrue(Test,exist('sdpvar','file') ~= 0,'YALMIP unavailable');
V = sdpvar(1); Phi = sdpvar(1);
[C,z,v] = add_lvrt_segment_constraints(V,Phi,0.9,0.4,2,1);
for Voltage = [0 0.2 0.4 0.6 0.9 1]
    Current = min(1,max(0,2*(0.9-Voltage)));
    Feasible = 0;
    for s = 1:3
        Z = zeros(3,1); Z(s) = 1;
        assign(z,Z); assign(v,Voltage*Z); assign(V,Voltage); assign(Phi,Current);
        Feasible = Feasible+(min(check(C)) >= -1e-10);
    end
    verifyGreaterThanOrEqual(Test,Feasible,1);
end
U = binvar(1); X = sdpvar(1); W = sdpvar(1);
C = add_binary_product_bounds(W,X,U,-2,3);
for u = 0:1
    for x = [-2 0 3]
        assign(U,u); assign(X,x); assign(W,u*x);
        verifyGreaterThanOrEqual(Test,min(check(C)),-1e-10);
        assign(W,u*x+0.01);
        verifyLessThan(Test,min(check(C)),-1e-5);
    end
end
end

function testGFLNodeAggregation(Test)
GFL = struct('Built_Nodes',[2;2;3],'PN_MW',[10;20;30], ...
    'K_Q',[2;3;2],'I_N_Rated',1,'Delta_I_Rated',[1;1.5;1], ...
    'V_LVRT_On',0.9,'V_LVRT_Sat',0.4);
A = aggregate_gfl_node_parameters(GFL);
verifyEqual(Test,A.Built_Nodes,[2;3]);
verifyEqual(Test,A.PN_MW,[30;30]);
verifyEqual(Test,A.K_Q(1)*A.I_N_Rated(1)*A.PN_MW(1),80,'AbsTol',1e-10);
verifyEqual(Test,A.Delta_I_Rated(1)*A.PN_MW(1),40,'AbsTol',1e-10);
end

function testKronReductionAndLineStatus(Test)
C = Test.TestData.CONF;
mpc = Test.TestData.mpc;
% 节点4为无源节点，保留集合与全部状态相关源保持不变。
mpc.bus(4,:) = mpc.bus(3,:); mpc.bus(4,1) = 4; mpc.bus(4,3) = 0;
mpc.branch(4,:) = mpc.branch(1,:); mpc.branch(4,1:2) = [1 4];
mpc.branch(5,:) = mpc.branch(2,:); mpc.branch(5,1:2) = [4 3];
C.Bn = 4; C.Ln = 5;
C.GFM_Module_Loc_Mat(4,:) = 0;
C.P_Load_Profile(4,:,:) = 0;
C.P_GFL_Available_Profile(4,:,:) = 0;
C.P_GFL_Available_Scenarios(4,:,:,:) = 0;
C.Safety_Original_To_Reduced = [1;2;3;0];
NET = build_multiple_snapshot_network(mpc,C);
Afull = -NET.B_0_Safety_Full+diag([4;1/0.3;2.25;0]);
Xfull = full(Afull\eye(4));
Xred = full((-NET.B_0_Safety+diag([4;1/0.3;2.25]))\eye(3));
verifyEqual(Test,Xred,Xfull(1:3,1:3),'AbsTol',1e-10);
mpc.branch(5,11) = 0;
NET = build_multiple_snapshot_network(mpc,C);
verifyEqual(Test,NET.Line_B_Series(5),0);
verifyEqual(Test,full(NET.B_0_Safety_Full(3,4)),0);
end
