function MIP_Start = build_multiple_snapshot_mip_start_from_result(Result, CONF)
%% 从同一算例的已完成阶段结果，构造下一阶段的整数热启动。
% 各阶段沿用相同的机组、候选节点、典型日、风电场景与时段索引。

%% 1. 按目标算例定义整数变量的维度
G = CONF.Gn;
D = CONF.TypicalDayCount;
K = CONF.WindScenarioCount;
T = CONF.PeriodCount;
N_GFM = CONF.GFM_Candidate_Count;
N_GFM_Unit = CONF.GFM_Max_Units_Per_Bus;
Fields = {'u_G', 'u_G_Start', 'u_G_Stop', 'u_G_SCC', 'u_G_SCR', ...
    'u_GFM_Unit', 'u_GFM_Ch'};
Expected_Sizes = {[G D T], [G D T], [G D T], [G D], [G D], ...
    [N_GFM N_GFM_Unit], [N_GFM D K T]};

%% 2. 核对维度与数值，将整数解按相同索引取整
MIP_Start = struct();
for k = 1:numel(Fields)
    Field = Fields{k};
    Values = Result.(Field);
    Expected_Size = Expected_Sizes{k};
    if ndims(Values) > numel(Expected_Size) || ...
            ~isequal(size(Values, 1:numel(Expected_Size)), Expected_Size)
        error('MultipleSnapshot:InvalidMIPStartDimensions', ...
            '源结果中的%s维度与目标算例不一致，热启动须使用同一算例的阶段结果。', Field);
    end
    if ~isnumeric(Values) || ~isreal(Values) || any(~isfinite(Values(:)))
        error('MultipleSnapshot:InvalidMIPStartValues', ...
            '源结果中的%s须为有限实数数组。', Field);
    end
    MIP_Start.(Field) = reshape(round(Values), Expected_Size);
end

%% 3. 记录热启动来源，文件位置由调用方补充
MIP_Start.Source_File = '';
MIP_Start.Source_Stage = Result.CONF.SolveStage;
end
