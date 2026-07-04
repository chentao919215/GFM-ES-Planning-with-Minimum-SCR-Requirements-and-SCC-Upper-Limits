function Report = compare_multiple_snapshot_deterministic_results( ...
    ScenarioResult, DeterministicResult, tolerance)
%% 比较单基准场景随机模型结果与原确定性模型结果。
% ScenarioResult应由WindScenarioCount=1且概率为1的退化算例生成。

if nargin < 3 || isempty(tolerance)
    tolerance = 1e-6;
end
check_multiple_snapshot_deterministic_degradation(ScenarioResult.CONF);

scenario_fields = {'P_Line','theta','P_G','P_GFL','P_GFL_Curt', ...
    'P_GFM','P_GFM_Dis','P_GFM_Ch','E_GFM','u_GFM_Ch'};
shared_fields = {'u_G','u_G_Start','u_G_Stop','u_G_SCC','u_G_SCR', ...
    'u_GFM_Mod','SCC_1','SCR','Z_SCC','Z_SCR'};

field_names = {};
max_errors = [];
for k = 1:numel(scenario_fields)
    name = scenario_fields{k};
    if isfield(ScenarioResult,name) && isfield(DeterministicResult,name)
        scenario_value = remove_singleton_scenario( ...
            ScenarioResult.(name), ScenarioResult.CONF);
        [field_names,max_errors] = append_error(field_names,max_errors, ...
            name,scenario_value,DeterministicResult.(name));
    end
end
for k = 1:numel(shared_fields)
    name = shared_fields{k};
    if isfield(ScenarioResult,name) && isfield(DeterministicResult,name)
        [field_names,max_errors] = append_error(field_names,max_errors, ...
            name,ScenarioResult.(name),DeterministicResult.(name));
    end
end

cost_names = {'Total','GEN','CON','Curt','UC'};
for k = 1:numel(cost_names)
    name = cost_names{k};
    if isfield(ScenarioResult.Cost,name) && isfield(DeterministicResult.Cost,name)
        [field_names,max_errors] = append_error(field_names,max_errors, ...
            ['Cost.' name],ScenarioResult.Cost.(name), ...
            DeterministicResult.Cost.(name));
    end
end

Report = struct();
Report.Fields = field_names;
Report.MaxAbsoluteErrors = max_errors;
Report.Tolerance = tolerance;
Report.Passed = ~isempty(max_errors) && all(max_errors <= tolerance);
if ~Report.Passed
    [largest_error,index] = max(max_errors);
    error('确定性退化结果不一致：%s最大绝对误差为%.6g。', ...
        field_names{index},largest_error);
end

end

function value = remove_singleton_scenario(value, CONF)
%% 将[元件,典型日,1,时段]还原为确定性[元件,典型日,时段]。

expected_count = size(value,1)*CONF.TypicalDayCount*CONF.PeriodCount;
if numel(value) ~= expected_count
    error('单场景结果变量的元素数量与确定性维度不一致。');
end
value = reshape(value,size(value,1),CONF.TypicalDayCount,CONF.PeriodCount);

end

function [names,errors] = append_error(names,errors,name,left,right)
%% 记录同维数值结果的最大绝对误差。

if numel(left) ~= numel(right)
    error('确定性退化比较字段%s的元素数量不一致。',name);
end
names{end+1} = name;
errors(end+1) = max(abs(left(:)-right(:)));

end
