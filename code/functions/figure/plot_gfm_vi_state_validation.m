function Figure_Handle = plot_gfm_vi_state_validation(ValidationResult, Figure_File, Style)
%% 从当前验证归档直接绘制电压、电流和已归档的状态跃迁，不执行仿真。
Style.Close_After_Save = false;
validateattributes(ValidationResult, {'struct'}, {'scalar'});
Result = ValidationResult.SelectedResult;
Data = Result.Data;
Time_s = Data.Time_s(:);
U_PCC_pu = Data.Voltage_pu(:);
I_GFM_pu = Data.Current_pu(:);
validateattributes(Time_s, {'numeric'}, {'vector', 'real', 'finite', 'nonempty'});
assert(numel(Time_s) >= 2 && all(diff(Time_s) > 0), ...
    'GFMValidation:InvalidTime', '记录时间必须严格递增且至少包含两个采样点。');
for Values = {U_PCC_pu, I_GFM_pu}
    validateattributes(Values{1}, {'numeric'}, ...
        {'vector', 'real', 'finite', 'numel', numel(Time_s)});
end
U_boundary_pu = ValidationResult.U_boundary_pu;
I_threshold_pu = ValidationResult.I_switch_threshold_pu;
Release_Confirm_Time_s = Result.ReleaseConfirmTime;
validateattributes(U_boundary_pu, {'numeric'}, {'scalar', 'real', 'finite'});
validateattributes(I_threshold_pu, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
validateattributes(Release_Confirm_Time_s, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'});
Case_Boundary_Times_s = [Result.FaultStartTime, Result.FaultClearTime];
validateattributes(Case_Boundary_Times_s, {'numeric'}, {'vector', 'real', 'finite', 'numel', 2});
assert(Case_Boundary_Times_s(1) < Case_Boundary_Times_s(2), ...
    'GFMValidation:InvalidCases', '故障投入时刻必须早于清除时刻。');
Case_Boundary_Times_s = Case_Boundary_Times_s( ...
    Case_Boundary_Times_s > Time_s(1) & Case_Boundary_Times_s < Time_s(end));

%% 1. 绘图设置
Case_Names = {'Case A', 'Case B', 'Case C'};
Show_Case_Boundaries = true;
Show_Case_Names = true;
Show_Transition_Labels = true;
Figure_Width_cm = 18.0;
Figure_Height_cm = 7.5;
Label_Font_Size = Style.Label_Size;
Output_File = char(Figure_File);

%% 2. 直接使用验证阶段按实际Slim信号记录的跃迁表。
Transition_Table = Result.Transitions;
assert(istable(Transition_Table) && ...
    all(ismember({'Time_s', 'Direction'}, Transition_Table.Properties.VariableNames)), ...
    'GFMValidation:InvalidTransitions', '状态归档必须包含跃迁时刻和方向。');
Transition_Times_s = Transition_Table.Time_s;
validateattributes(Transition_Times_s, {'numeric'}, ...
    {'column', 'real', 'finite', '>=', Time_s(1), '<=', Time_s(end)});
assert(all(diff(Transition_Times_s) > 0) && ...
    all(ismember(Transition_Table.Direction, ["OFF->ON", "ON->OFF"])), ...
    'GFMValidation:InvalidTransitions', '跃迁时刻须递增，方向须为OFF->ON或ON->OFF。');

fprintf('\n=== 虚拟阻抗限流状态切换验证 ===\n');
fprintf('状态跃迁总次数：%d\n', height(Transition_Table));
fprintf('U_boundary = %.6f p.u.\n', U_boundary_pu);
fprintf('I_switch_threshold = %.6f p.u.\n', I_threshold_pu);
fprintf('ReleaseConfirmTime = %.6f s\n', Release_Confirm_Time_s);
if isempty(Transition_Table)
    fprintf('当前时间范围内没有检测到状态跃迁。\n');
else
    disp(Transition_Table);
end

%% 3. 创建图窗和坐标区
Font_Name = Style.Font_Name;

Figure_Handle = new_figure([Figure_Width_cm Figure_Height_cm], Style);

Axes_U = subplot(2, 1, 1, 'Parent', Figure_Handle);
Axes_I = subplot(2, 1, 2, 'Parent', Figure_Handle);
Axes_List = [Axes_U, Axes_I];

% 坐标轴和网格风格沿用 plot_gfm_vi_limited.m。
for Axes_Index = 1:numel(Axes_List)
    Axes_Handle = Axes_List(Axes_Index);
    style_sci_axes(Axes_Handle);
    hold(Axes_Handle, 'on');
end

%% 4. 绘制 UPCC 和 IGFM
Voltage_Color = Style.Colors.SCC;
Current_Color = Style.Colors.GFM;
Activation_Color = Style.Colors.Highlight;
Release_Color = Style.Colors.SCC;
Gray_Color = Style.Colors.Reference;

plot(Axes_U, Time_s, U_PCC_pu, '-', ...
    'Color', Voltage_Color, 'LineWidth', 1.7);
plot(Axes_U, [Time_s(1), Time_s(end)], ...
    [U_boundary_pu, U_boundary_pu], '--', ...
    'Color', Activation_Color, 'LineWidth', 1.3);
ylabel(Axes_U, '|{\itU}^{PCC}|/{\itU}^{N}', ...
    'FontName', 'Times New Roman', 'FontSize', Label_Font_Size);
yticks(Axes_U, 0:0.5:1.5);

plot(Axes_I, Time_s, I_GFM_pu, '-', ...
    'Color', Current_Color, 'LineWidth', 1.7);
plot(Axes_I, [Time_s(1), Time_s(end)], ...
    [I_threshold_pu, I_threshold_pu], '--', ...
    'Color', Activation_Color, 'LineWidth', 1.3);
ylabel(Axes_I, '|{\itI}^{GFM}|/{\itI}^{N}', ...
    'FontName', 'Times New Roman', 'FontSize', Label_Font_Size);

xlabel(Axes_I, 'Time (s)', ...
    'FontName', Font_Name, 'FontSize', Label_Font_Size - 1);

U_limits = [min([U_PCC_pu; U_boundary_pu]), ...
    max([U_PCC_pu; U_boundary_pu])];
U_span = max(diff(U_limits), 0.05);
ylim(Axes_U, [U_limits(1) - 0.08 * U_span, ...
    U_limits(2) + 0.60 * U_span]);

I_upper = max([I_GFM_pu; I_threshold_pu]);
ylim(Axes_I, [0, max(1.10 * I_upper, I_threshold_pu + 0.1)]);

for Axes_Index = 1:numel(Axes_List)
    xlim(Axes_List(Axes_Index), [Time_s(1), Time_s(end)]);
end
linkaxes(Axes_List, 'x');

% 阈值文字位置可在这里直接手动修改。
Label_Time_s = Time_s(1) + 0.985 * (Time_s(end) - Time_s(1));
text(Axes_U, Label_Time_s, U_boundary_pu, '{\itU}_b  ', ...
    'Color', Activation_Color, 'FontName', 'Times New Roman', ...
    'FontSize', 11, 'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'bottom');
text(Axes_I, Label_Time_s, I_threshold_pu, '{\itI}^{lim}  ', ...
    'Color', Activation_Color, 'FontName', 'Times New Roman', ...
    'FontSize', 11, 'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'bottom');

%% 5. 标出 Case 边界和状态跃迁
if Show_Case_Boundaries
    for Boundary_Index = 1:numel(Case_Boundary_Times_s)
        Boundary_Time_s = Case_Boundary_Times_s(Boundary_Index);
        for Axes_Index = 1:numel(Axes_List)
            Y_Limits = ylim(Axes_List(Axes_Index));
            if Axes_Index == 1
                Y_Limits(2) = U_limits(2) + 0.08*U_span;
            end
            plot(Axes_List(Axes_Index), ...
                [Boundary_Time_s, Boundary_Time_s], Y_Limits, ':', ...
                'Color', Gray_Color, 'LineWidth', 1.0, ...
                'HandleVisibility', 'off');
        end
    end
end

for Row_Index = 1:height(Transition_Table)
    Transition_Time_s = Transition_Table.Time_s(Row_Index);
    if Transition_Table.Direction(Row_Index) == "OFF->ON"
        Transition_Color = Activation_Color;
        Transition_Label = sprintf('VI on: %.4f s', Transition_Time_s);
    else
        Transition_Color = Release_Color;
        Transition_Label = sprintf('VI off: %.4f s', Transition_Time_s);
    end

    for Axes_Index = 1:numel(Axes_List)
        Y_Limits = ylim(Axes_List(Axes_Index));
        if Axes_Index == 1
            Y_Limits(2) = U_limits(2) + 0.08*U_span;
        end
        plot(Axes_List(Axes_Index), ...
            [Transition_Time_s, Transition_Time_s], Y_Limits, '--', ...
            'Color', Transition_Color, 'LineWidth', 1.15, ...
            'HandleVisibility', 'off');
    end

    if Show_Transition_Labels
        Y_Limits = ylim(Axes_U);
        text(Axes_U, Transition_Time_s, ...
            Y_Limits(2) - 0.03 * diff(Y_Limits), Transition_Label, ...
            'Color', Transition_Color, 'FontName', Font_Name, ...
            'FontSize', 9, 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'top');
    end
end

if Show_Case_Boundaries && Show_Case_Names
    Case_Edges_s = [Time_s(1), Case_Boundary_Times_s, Time_s(end)];
    Number_Of_Case_Regions = numel(Case_Edges_s) - 1;
    Number_Of_Case_Labels = min(Number_Of_Case_Regions, numel(Case_Names));
    Y_Limits = ylim(Axes_U);
    for Case_Index = 1:Number_Of_Case_Labels
        Case_Center_s = mean(Case_Edges_s(Case_Index:Case_Index + 1));
        text(Axes_U, Case_Center_s, ...
            Y_Limits(2) - 0.20 * diff(Y_Limits), Case_Names{Case_Index}, ...
            'Color', Gray_Color, 'FontName', 'Times New Roman', ...
            'FontSize', 9.5, 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'top');
    end
end

%% 6. 仅保存可编辑的FIG图件。
if ~isempty(Output_File)
    save_figure_file(Figure_Handle, Output_File);
    fprintf('FIG: %s\n', Output_File);
end
end
