function [mpc, CONF] = build_converter_test_case()
%% 独立的三节点验证数据，不代表新版论文Section IV算例。

mpc = struct();
mpc.bus = zeros(3,13);
mpc.bus(:,1) = (1:3).';
mpc.bus(:,2) = [3;1;1];
mpc.bus(:,3) = [5;10;15];
mpc.branch = zeros(3,13);
mpc.branch(:,1:2) = [1 2;2 3;3 1];
mpc.branch(:,4) = [0.3;0.4;0.5];
mpc.branch(:,6) = 100;
mpc.branch(:,11) = 1;
mpc.gen = zeros(2,21);
mpc.gen(:,1) = [1;2];
mpc.gen(:,8) = 1;
mpc.gen(:,9) = [60;50];
mpc.gencost = [2 0 0 3 0.01 10 2;2 0 0 3 0.02 12 3];
mpc.baseMVA = 100;
CONF = struct('ModelVersion','2026-10-23','Bn',3,'Gn',2,'Ln',3, ...
    'Base_MVA',100,'Base_kV',100,'Base_kA',1/sqrt(3),'Base_O',100, ...
    'TypicalDayCount',2,'WindScenarioCount',2,'PeriodCount',3, ...
    'Enable_SCC',true,'Enable_SCR',true,'Require_Source_Online',true, ...
    'KZ',1,'ERR_TOL',1e-8,'ObjectiveScale',1e3, ...
    'N_GFM_Module_Max',2,'GFM_MaxModulesPerCandidate',2, ...
    'GFM_Module_Sequential',false,'GFM_Module_Count',2,'GFM_Candidate_Count',1);
CONF.Xd_Gen = [0.25;0.3];
CONF.GenCostBreakpoints = [0 0.25 0.5 0.75 1];
CONF.Gen_Pmin = [5;5];
CONF.Gen_Ramp_Up_MW_per_Hour = [10;10];
CONF.Gen_Ramp_Down_MW_per_Hour = [10;10];
CONF.Gen_Min_Up_Periods = [2;2];
CONF.Gen_Min_Down_Periods = [1;1];
CONF.Gen_Startup_Cost = [20;20];
CONF.Gen_Shutdown_Cost = [5;5];
CONF.u_GFL = [0;1;1];
CONF.PN_GFL_Node = [0;10;20];
CONF.PN_GFL_pu_Node = CONF.PN_GFL_Node/100;
CONF.PN_GFL = 20;
CONF.KQ_GFL_Node = [0;2;2];
CONF.I_GFL_N_pu_Node = [0;0.1;0.2];
CONF.V_LVRT_On_Node = [0;0.9;0.9];
CONF.V_LVRT_Sat_Node = [0;0.4;0.4];
CONF.Delta_I_GFL_pu_Node = [0;0.1;0.2];
CONF.GFL_Curtailment_Cost_per_MWh = 100;
CONF.GFM_Module_Bus = [3;3];
CONF.GFM_Module_Order = [1;2];
CONF.GFM_Module_PN = [10;15];
CONF.GFM_Module_PN_pu = CONF.GFM_Module_PN/100;
CONF.GFM_Module_Rated_Energy = [20;30];
CONF.GFM_Module_Cost_Conv = [100;150];
CONF.GFM_Module_X_Res = [1;0.8];
CONF.GFM_Module_X_Vir = [2;1.5];
CONF.GFM_Module_DeltaY_abs = 1./CONF.GFM_Module_X_Res - ...
    1./(CONF.GFM_Module_X_Res+CONF.GFM_Module_X_Vir);
CONF.GFM_Module_DeltaY = 1i*CONF.GFM_Module_DeltaY_abs;
CONF.GFM_Module_Loc_Mat = sparse([3;3],[1;2],1,3,2);
CONF.GFM_Module_Candidates = 3;
CONF.GFM_Module_Candidate_Index = [1;1];
CONF.GFM_Candidate_Loc_Mat = sparse(3,1,1,3,1);
CONF.GFM_Candidate_Module_Mat = sparse([1 1]);
CONF.GFM_Candidate_Charge_Efficiency = 0.9;
CONF.GFM_Candidate_Discharge_Efficiency = 0.9;
CONF.GFM_Candidate_Rated_Duration = 2;
CONF.GFM_Candidate_SOC_Min = 0.1;
CONF.GFM_Candidate_SOC_Max = 0.9;
CONF.GFM_Candidate_SOC_Initial = 0.5;
CONF.Safety_Retained_Nodes = (1:3).';
CONF.Safety_Original_To_Reduced = (1:3).';
CONF.Safety_Node_Count = 3;
CONF.Safety_GFL_Original_Nodes = [2;3];
CONF.Safety_GFL_Reduced_Indices = [2;3];
CONF.Safety_GFL_Count = 2;
CONF.SCC_Constraint_Original_Nodes = (1:3).';
CONF.I_limit = 100*ones(3,1);
CONF.I_limit_kA_Node = CONF.I_limit*CONF.Base_kA;
CONF.SCR_min = [1;1;1];
CONF.TypicalDayWeights_Days = [180;185];
CONF.PeriodDurations_Hours = [8;8;8];
CONF.OperatingWeights_Hours = CONF.TypicalDayWeights_Days*CONF.PeriodDurations_Hours.';
CONF.WindScenarioProbabilities = [0.4 0.6;0.7 0.3];
CONF.WindScenarioNames = {'low','high'};
CONF.WindScenarioBaseIndex = 1;
CONF.P_Load_Profile = repmat([5;10;15],1,2,3);
CONF.P_GFL_Available_Scenarios = zeros(3,2,2,3);
CONF.P_GFL_Available_Scenarios(2,:,1,:) = 3;
CONF.P_GFL_Available_Scenarios(3,:,1,:) = 5;
CONF.P_GFL_Available_Scenarios(2,:,2,:) = 6;
CONF.P_GFL_Available_Scenarios(3,:,2,:) = 10;
CONF.P_GFL_Available_Profile = reshape(CONF.P_GFL_Available_Scenarios(:,:,1,:),3,2,3);
% 仅继承用户已配置的求解器，不选择或替换后端。
Project_Root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
Parameters = read_json_file(fullfile(Project_Root,'data','params', ...
    'multiple_snapshot_default_params.json'));
CONF.solver = Parameters.solver;
end
