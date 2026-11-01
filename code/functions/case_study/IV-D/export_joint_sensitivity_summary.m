function [Summary_Table, Joint] = export_joint_sensitivity_summary( ...
    Rows, I_Values, SCR_Values, Scan, Executed)
%% 按输入轴顺序导出逐点汇总、指标矩阵与单调性核验结果。
Summary_Table = struct2table(Rows);
Summary_File = Scan.Summary_File;
Shape = [numel(SCR_Values), numel(I_Values)];
Joint = struct('I_Limit_Values_kA', I_Values, 'CSCR_Values', SCR_Values, ...
    'Row_Axis', 'CSCR', 'Column_Axis', 'SCC upper limit (kA)', ...
    'Manifest_File', Scan.Manifest_File, 'Manifest_SHA256', Scan.Manifest_SHA256, ...
    'Execute', Executed, 'Summary_Table', Summary_Table, ...
    'Case5_Reference_Audit_File', Scan.Case5_Audit_File);
Fields = {'Total_Annual_Cost', 'GFM_Unit_Count', 'GFM_Configuration', 'Status', ...
    'Final_MIP_Gap', 'Is_Feasible', 'Objective_Best_Bound', 'GFM_Power_MW', 'GFM_Energy_MWh'};
Names = {'Cost_Matrix', 'Unit_Count_Matrix', 'Configuration_Matrix', 'Status_Matrix', ...
    'MIP_Gap_Matrix', 'Feasible_Matrix', 'Best_Bound_Matrix', 'Power_MW_Matrix', 'Energy_MWh_Matrix'};
for n = 1:numel(Fields)
    Joint.(Names{n}) = reshape(Summary_Table.(Fields{n}), Shape);
end
Joint.Grid_Complete = all(Summary_Table.Completed);
Joint.Grid_Count = height(Summary_Table);
Joint.Monotonicity = monotonicity(Summary_Table);
% MAT仅保存Joint，其中的Summary_Table是汇总表的唯一副本。
save_joint_scan_data(Summary_File, struct('Joint', Joint));
Directory = fileparts(Summary_File);
writetable(Summary_Table, fullfile(Directory, 'joint_summary.csv'));
for n = 1:numel(Names)
    Matrix_Table = array2table(Joint.(Names{n}), ...
        'VariableNames', cellstr("SCC_"+string(I_Values)+"_kA"));
    Matrix_Table = addvars(Matrix_Table, SCR_Values, 'Before', 1, 'NewVariableNames', 'CSCR');
    writetable(Matrix_Table, fullfile(Directory, [Names{n}, '.csv']));
end
writetable(Joint.Monotonicity, fullfile(Directory, 'monotonicity_checks.csv'));
end

function Checks = monotonicity(Summary_Table)
%% 基于可行解目标值与最佳界，核验收紧安全限值后的成本变化。
% 对最小化问题，宽松限值下的可靠下界不大于严格限值下的最优值，
% 后者不大于严格限值下的可行解目标值；区间重叠可解释MIP间隙引起的表观反转。
Loose = zeros(0, 1);
Tight = Loose;
Drop = Loose;
Bound_Excess = Loose;
Assessment = strings(0, 1);
Valid_Indices = find(Summary_Table.Status == "target_met" & Summary_Table.Result_Validation_Passed & ...
    isfinite(Summary_Table.Objective_Best_Bound) & isfinite(Summary_Table.Total_Annual_Cost));
for Loose_Index = Valid_Indices(:).'
    for Tight_Index = Valid_Indices(:).'
        if Loose_Index == Tight_Index
            continue;
        end
        Is_Tighter = Summary_Table.I_limit_kA(Tight_Index) <= Summary_Table.I_limit_kA(Loose_Index) && Summary_Table.CSCR(Tight_Index) >= Summary_Table.CSCR(Loose_Index) && ...
            (Summary_Table.I_limit_kA(Tight_Index)<Summary_Table.I_limit_kA(Loose_Index) || Summary_Table.CSCR(Tight_Index)>Summary_Table.CSCR(Loose_Index));
        if ~Is_Tighter
            continue;
        end
        Loose(end+1, 1) = Loose_Index; %#ok<AGROW>
        Tight(end+1, 1) = Tight_Index; %#ok<AGROW>
        Drop(end+1, 1) = Summary_Table.Total_Annual_Cost(Loose_Index)-Summary_Table.Total_Annual_Cost(Tight_Index); %#ok<AGROW>
        Bound_Excess(end+1, ...
            1) = Summary_Table.Objective_Best_Bound(Loose_Index)-Summary_Table.Total_Annual_Cost(Tight_Index); %#ok<AGROW>
        Tolerance = max(1e-4, 1e-8*max(abs(Summary_Table.Total_Annual_Cost([Loose_Index, Tight_Index]))));
        if Bound_Excess(end)>Tolerance
            Assessment(end+1, 1) = "review_disjoint_bounds"; %#ok<AGROW>
        elseif Drop(end)>Tolerance
            Assessment(end+1, 1) = "reversal_within_MIP_uncertainty"; %#ok<AGROW>
        else
            Assessment(end+1, 1) = "consistent"; %#ok<AGROW>
        end
    end
end

Checks = table(Loose, Tight, Drop, Bound_Excess, Assessment);
end
