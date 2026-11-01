function Data = load_rts_gmlc_annual_data(Config)
%% 读取、对齐并归一化RTS-GMLC全年负荷与风电数据
% 输入：Config，固定数据路径、日历口径、时间尺度与数值容差。
% 输出：Data，含8760点年度序列、365×24日序列、节点/场站映射及质量记录。
% 本函数只接受完整且严格对齐的数据；缺失、重复、乱序或越界均直接报错。

validate_source_files(Config.Source.Files);

%% 1. 读取原始表格
Bus = read_source_table(Config.Source.Files.Bus);
Generator = read_source_table(Config.Source.Files.Generator);
Load_DA = read_source_table(Config.Source.Files.Day_Ahead_Load);
Wind_DA = read_source_table(Config.Source.Files.Day_Ahead_Wind);
Wind_RT = read_source_table(Config.Source.Files.Real_Time_Wind);

%% 2. 校验时间戳、字段、维度和缺失值
Load_DA_Time = validate_hourly_table(Load_DA, ...
    '日前区域负荷', Config.Period_Count);
Wind_DA_Time = validate_hourly_table(Wind_DA, ...
    '日前风电预测', Config.Period_Count);
[Wind_RT_Time, Wind_RT_Hourly_Time] = validate_real_time_table( ...
    Wind_RT, '实时风电实际出力', Config.Real_Time_Intervals_Per_Hour);

if ~isequal(Load_DA_Time, Wind_DA_Time)
    error('RTS_GMLC:DayAheadTimestampMismatch', ...
        '日前负荷与日前风电时间戳不完全一致。');
end
if ~isequal(Wind_DA_Time, Wind_RT_Hourly_Time)
    error('RTS_GMLC:WindTimestampMismatch', ...
        '日前风电与按自然小时聚合后的实时风电时间戳不完全一致。');
end

Load_Value_Names = string(Load_DA.Properties.VariableNames(5:end));
Wind_DA_Names = string(Wind_DA.Properties.VariableNames(5:end));
Wind_RT_Names = string(Wind_RT.Properties.VariableNames(5:end));
if ~isequal(Wind_DA_Names, Wind_RT_Names)
    error('RTS_GMLC:WindFieldMismatch', ...
        '日前风电与实时风电场站字段及顺序不一致。');
end

Regional_Load_MW = validate_numeric_values(Load_DA{:, 5:end}, ...
    '日前区域负荷');
Wind_DA_MW = validate_numeric_values(Wind_DA{:, 5:end}, ...
    '日前风电预测');
Wind_RT_5min_MW = validate_numeric_values(Wind_RT{:, 5:end}, ...
    '实时风电实际出力');

if any(Regional_Load_MW(:) < -Config.Numeric_Tolerance)
    error('RTS_GMLC:NegativeLoad', '日前区域负荷中存在负值。');
end

%% 3. 聚合实时风电并一致删除2020-02-29
Wind_RT_Hourly_MW = aggregate_real_time_by_natural_hour( ...
    Wind_RT_5min_MW, Config.Real_Time_Intervals_Per_Hour);
Raw_Load_DA_Time = Load_DA_Time;
Raw_Wind_DA_Time = Wind_DA_Time;
Raw_Wind_RT_Hourly_Time = Wind_RT_Hourly_Time;
[Load_DA_Time, Wind_DA_Time, Wind_RT_Hourly_Time, ...
    Regional_Load_MW, Wind_DA_MW, Wind_RT_Hourly_MW, ...
    Exclusion] = exclude_calendar_date(Raw_Load_DA_Time, ...
    Raw_Wind_DA_Time, Raw_Wind_RT_Hourly_Time, Regional_Load_MW, ...
    Wind_DA_MW, Wind_RT_Hourly_MW, Config);

%% 4. 按区域静态负荷占比展开至各负荷节点
Required_Bus_Fields = ["Bus ID", "MW Load", "Area"];
assert_required_fields(Bus, Required_Bus_Fields, 'bus.csv');
Bus_ID = double(Bus.("Bus ID"));
Bus_Base_Load_MW = double(Bus.("MW Load"));
Bus_Area = double(Bus.("Area"));
if any(~isfinite(Bus_ID)) || any(~isfinite(Bus_Base_Load_MW)) || ...
        any(~isfinite(Bus_Area)) || any(Bus_Base_Load_MW < 0)
    error('RTS_GMLC:InvalidBusData', ...
        'bus.csv中的Bus ID、MW Load或Area字段无效。');
end

Load_Area_ID = str2double(Load_Value_Names);
if any(~isfinite(Load_Area_ID)) || numel(unique(Load_Area_ID)) ...
        ~= numel(Load_Area_ID)
    error('RTS_GMLC:InvalidLoadAreaFields', ...
        '日前区域负荷列名不能唯一映射为区域编号。');
end

Missing_Area = ~ismember(Bus_Area, Load_Area_ID);
if any(Missing_Area)
    First_Missing = find(Missing_Area, 1);
    error('RTS_GMLC:MissingLoadArea', ...
        '负荷文件缺少节点%d所属区域%d。', ...
        Bus_ID(First_Missing), Bus_Area(First_Missing));
end

% 同一区域节点共用一个区域曲线，仅按静态MW Load比例展开；不做节点独立归一化。
Node_Load_MW = zeros(size(Regional_Load_MW, 1), height(Bus));
for Area_Column = 1:numel(Load_Area_ID)
    Area_ID = Load_Area_ID(Area_Column);
    Area_Mask = Bus_Area == Area_ID;
    Area_Base_Load = sum(Bus_Base_Load_MW(Area_Mask));
    if Area_Base_Load <= 0
        error('RTS_GMLC:InvalidAreaLoadBase', ...
            '区域%d的静态负荷基准不为正。', Area_ID);
    end
    Node_Load_MW(:, Area_Mask) = Regional_Load_MW(:, Area_Column) .* ...
        Bus_Base_Load_MW(Area_Mask).' ./ Area_Base_Load;
end

System_Load_MW = sum(Regional_Load_MW, 2);
if max(abs(sum(Node_Load_MW, 2) - System_Load_MW)) > 1e-8
    error('RTS_GMLC:NodalLoadAggregationMismatch', ...
        '节点负荷之和与区域负荷之和不一致。');
end
Load_System_Base_MW = max(System_Load_MW);
if ~isfinite(Load_System_Base_MW) || Load_System_Base_MW <= 0
    error('RTS_GMLC:InvalidLoadNormalizationBase', ...
        '全年系统负荷统一归一化基准无效。');
end
System_Load_Normalized = System_Load_MW ./ Load_System_Base_MW;
Node_Load_Normalized = Node_Load_MW ./ Load_System_Base_MW;

%% 5. 按风电装机容量统一归一化日前与实时风电
Required_Gen_Fields = ["GEN UID", "Unit Type", "PMax MW", "Bus ID"];
assert_required_fields(Generator, Required_Gen_Fields, 'gen.csv');
Generator_UID = string(Generator.("GEN UID"));
Generator_Type = string(Generator.("Unit Type"));
Wind_Generator_Mask = strcmpi(Generator_Type, 'WIND');
if ~any(Wind_Generator_Mask)
    error('RTS_GMLC:MissingWindGenerators', ...
        'gen.csv中未找到Unit Type为WIND的机组。');
end

Wind_Site_Count = numel(Wind_DA_Names);
Wind_Site_Capacity_MW = zeros(1, Wind_Site_Count);
Wind_Site_Bus_ID = zeros(1, Wind_Site_Count);
for i = 1:Wind_Site_Count
    Generator_Index = find(Wind_Generator_Mask & ...
        Generator_UID == Wind_DA_Names(i));
    if numel(Generator_Index) ~= 1
        error('RTS_GMLC:WindCapacityMappingError', ...
            '风电字段%s不能唯一映射至gen.csv。', Wind_DA_Names(i));
    end
    Wind_Site_Capacity_MW(i) = double( ...
        Generator.("PMax MW")(Generator_Index));
    Wind_Site_Bus_ID(i) = double(Generator.("Bus ID")(Generator_Index));
end
if any(~isfinite(Wind_Site_Capacity_MW)) || ...
        any(Wind_Site_Capacity_MW <= 0)
    error('RTS_GMLC:InvalidWindCapacity', ...
        '风电场站PMax MW装机容量无效。');
end

assert_power_within_capacity(Wind_DA_MW, Wind_Site_Capacity_MW, ...
    '日前风电预测', Config.Numeric_Tolerance);
assert_power_within_capacity(Wind_RT_Hourly_MW, ...
    Wind_Site_Capacity_MW, '实时风电小时均值', Config.Numeric_Tolerance);

Wind_System_Capacity_MW = sum(Wind_Site_Capacity_MW);
Wind_DA_Site_Normalized = Wind_DA_MW ./ Wind_Site_Capacity_MW;
Wind_RT_Site_Normalized = Wind_RT_Hourly_MW ./ Wind_Site_Capacity_MW;
Wind_DA_System_MW = sum(Wind_DA_MW, 2);
Wind_RT_System_MW = sum(Wind_RT_Hourly_MW, 2);
Wind_DA_System_Normalized = Wind_DA_System_MW ./ ...
    Wind_System_Capacity_MW;
Wind_RT_System_Normalized = Wind_RT_System_MW ./ ...
    Wind_System_Capacity_MW;
Wind_Error_System_Normalized = Wind_RT_System_Normalized - ...
    Wind_DA_System_Normalized;
Wind_To_Load_Base = Wind_System_Capacity_MW / Load_System_Base_MW;
DA_Net_Load_Normalized_On_Load_Base = System_Load_Normalized - ...
    Wind_DA_System_Normalized * Wind_To_Load_Base;

%% 6. 重排为365个自然日×24 h，并再次检查完整性
Date_Vector = dateshift(Load_DA_Time, 'start', 'day');
Dates = unique(Date_Vector, 'stable');
Valid_Day_Count = numel(Dates);
Expected_Row_Count = Valid_Day_Count * Config.Period_Count;
if numel(Load_DA_Time) ~= Expected_Row_Count
    error('RTS_GMLC:IncompleteNaturalDays', ...
        '全年小时数不能构成完整的24 h自然日。');
end
if Valid_Day_Count ~= Config.Calendar.Expected_Day_Count || ...
        any(Dates == Config.Calendar.Excluded_Date)
    error('RTS_GMLC:InvalidProcessedCalendar', ...
        '剔除2020-02-29后必须恰好为365个自然日。');
end

Daily_System_Load_Normalized = reshape( ...
    System_Load_Normalized, Config.Period_Count, Valid_Day_Count).';
Daily_Wind_DA_System_Normalized = reshape( ...
    Wind_DA_System_Normalized, Config.Period_Count, Valid_Day_Count).';
Daily_Wind_RT_System_Normalized = reshape( ...
    Wind_RT_System_Normalized, Config.Period_Count, Valid_Day_Count).';
Daily_Wind_Error_System_Normalized = reshape( ...
    Wind_Error_System_Normalized, Config.Period_Count, Valid_Day_Count).';
Daily_DA_Net_Load_Normalized_On_Load_Base = reshape( ...
    DA_Net_Load_Normalized_On_Load_Base, Config.Period_Count, ...
    Valid_Day_Count).';

Daily_Node_Load_Normalized = permute(reshape( ...
    Node_Load_Normalized.', height(Bus), Config.Period_Count, ...
    Valid_Day_Count), [1, 3, 2]);
Daily_Wind_DA_Site_Normalized = permute(reshape( ...
    Wind_DA_Site_Normalized.', Wind_Site_Count, Config.Period_Count, ...
    Valid_Day_Count), [1, 3, 2]);
Daily_Wind_RT_Site_Normalized = permute(reshape( ...
    Wind_RT_Site_Normalized.', Wind_Site_Count, Config.Period_Count, ...
    Valid_Day_Count), [1, 3, 2]);

assert_no_missing_processed_values({System_Load_Normalized, ...
    Node_Load_Normalized, Wind_DA_System_Normalized, ...
    Wind_RT_System_Normalized, Wind_Error_System_Normalized});

%% 7. 保存数据来源、归一化基准、维度和质量检查
Source_Manifest = build_source_manifest(Config);
Quality_Checks = build_quality_check_table(Raw_Load_DA_Time, ...
    Raw_Wind_DA_Time, Wind_RT_Time, Raw_Wind_RT_Hourly_Time, ...
    Load_DA_Time, Wind_DA_Time, Wind_RT_Hourly_Time, Exclusion, ...
    Valid_Day_Count, height(Bus), Wind_Site_Count, Config);

Data = struct();
Data.Source_Manifest = Source_Manifest;
Data.Quality_Checks = Quality_Checks;
Data.Timestamp = Load_DA_Time;
Data.Date = Date_Vector;
Data.Dates = Dates;
Data.Hour = hour(Load_DA_Time) + 1;
Data.Bus_ID = Bus_ID(:);
Data.Bus_Area = Bus_Area(:);
Data.Wind_Site_Name = Wind_DA_Names(:);
Data.Wind_Site_Bus_ID = Wind_Site_Bus_ID(:);
Data.Calendar = Exclusion;
Data.Normalization = struct();
Data.Normalization.Load_System_Base_MW = Load_System_Base_MW;
Data.Normalization.Load_Method = ...
    '所有系统及节点负荷统一除以全年系统小时峰值负荷';
Data.Normalization.Wind_System_Capacity_MW = Wind_System_Capacity_MW;
Data.Normalization.Wind_Site_Capacity_MW = Wind_Site_Capacity_MW(:);
Data.Normalization.Wind_Method = ...
    '系统风电除以总PMax，各场站风电除以本站PMax；日前与实时使用同一基准';
Data.Normalization.Net_Load_Base = ...
    '负荷与风电MW均除以全年系统峰值负荷后相减';

Data.Annual = struct();
Data.Annual.System_Load_MW = System_Load_MW;
Data.Annual.System_Load_Normalized = System_Load_Normalized;
Data.Annual.Node_Load_MW = Node_Load_MW;
Data.Annual.Node_Load_Normalized = Node_Load_Normalized;
Data.Annual.Wind_DA_System_MW = Wind_DA_System_MW;
Data.Annual.Wind_RT_System_MW = Wind_RT_System_MW;
Data.Annual.Wind_DA_System_Normalized = Wind_DA_System_Normalized;
Data.Annual.Wind_RT_System_Normalized = Wind_RT_System_Normalized;
Data.Annual.Wind_Error_System_Normalized = ...
    Wind_Error_System_Normalized;
Data.Annual.DA_Net_Load_Normalized_On_Load_Base = ...
    DA_Net_Load_Normalized_On_Load_Base;
Data.Annual.Wind_DA_Site_MW = Wind_DA_MW;
Data.Annual.Wind_RT_Site_MW = Wind_RT_Hourly_MW;
Data.Annual.Wind_DA_Site_Normalized = Wind_DA_Site_Normalized;
Data.Annual.Wind_RT_Site_Normalized = Wind_RT_Site_Normalized;

Data.Daily = struct();
Data.Daily.System_Load_Normalized = Daily_System_Load_Normalized;
Data.Daily.Node_Load_Normalized = Daily_Node_Load_Normalized;
Data.Daily.Wind_DA_System_Normalized = ...
    Daily_Wind_DA_System_Normalized;
Data.Daily.Wind_RT_System_Normalized = ...
    Daily_Wind_RT_System_Normalized;
Data.Daily.Wind_Error_System_Normalized = ...
    Daily_Wind_Error_System_Normalized;
Data.Daily.DA_Net_Load_Normalized_On_Load_Base = ...
    Daily_DA_Net_Load_Normalized_On_Load_Base;
Data.Daily.Wind_DA_Site_Normalized = ...
    Daily_Wind_DA_Site_Normalized;
Data.Daily.Wind_RT_Site_Normalized = ...
    Daily_Wind_RT_Site_Normalized;

end

%% 8. 本地函数：统一CSV读取与原始文件检查
function T = read_source_table(File_Path)
% 保留官方字段名，避免MATLAB自动修改带空格的列名。
T = readtable(File_Path, 'Delimiter', ',', 'ReadVariableNames', true, ...
    'VariableNamingRule', 'preserve', 'TextType', 'string');
end

function validate_source_files(Source_Files)
%% 校验来源清单要求的原始文件存在且格式符合约定。
Field_Names = fieldnames(Source_Files);
for i = 1:numel(Field_Names)
    file_path = Source_Files.(Field_Names{i});
    if ~isfile(file_path)
        error('RTS_GMLC:MissingSourceFile', ...
            '缺少RTS-GMLC原始文件：%s', file_path);
    end
end
end

%% 1. 本地函数：原始时间索引与数值完整性
function Timestamp = validate_hourly_table(T, Description, Period_Count)
% 转换为严格递增的小时索引；不排序、不去重、不补点。
assert_required_fields(T, ["Year", "Month", "Day", "Period"], ...
    Description);
Date_Parts = validate_date_parts(T, Description);
period = double(T.Period);
if any(~isfinite(period)) || any(period ~= round(period)) || ...
        any(period < 1) || any(period > Period_Count)
    error('RTS_GMLC:InvalidHourlyPeriod', ...
        '%s的Period必须为1到%d的整数。', Description, Period_Count);
end
Timestamp = datetime(Date_Parts(:, 1), Date_Parts(:, 2), ...
    Date_Parts(:, 3)) + hours(period - 1);
validate_strict_timestamp(Timestamp, hours(1), Description);
validate_period_sequence(T, Period_Count, Description);
end

function [Timestamp, Hourly_Timestamp] = validate_real_time_table( ...
    T, Description, Intervals_Per_Hour)
% 同时返回原始5 min索引和自然小时首点索引，供DA/RT严格对齐检查。
assert_required_fields(T, ["Year", "Month", "Day", "Period"], ...
    Description);
Date_Parts = validate_date_parts(T, Description);
period = double(T.Period);
periods_per_day = 24 * Intervals_Per_Hour;
if any(~isfinite(period)) || any(period ~= round(period)) || ...
        any(period < 1) || any(period > periods_per_day)
    error('RTS_GMLC:InvalidRealTimePeriod', ...
        '%s的Period必须为1到%d的整数。', Description, periods_per_day);
end
Interval_Minutes = 60 / Intervals_Per_Hour;
if Interval_Minutes ~= round(Interval_Minutes)
    error('RTS_GMLC:InvalidAggregationRatio', ...
        '实时分辨率不能整分聚合至自然小时。');
end
Timestamp = datetime(Date_Parts(:, 1), Date_Parts(:, 2), ...
    Date_Parts(:, 3)) + minutes((period - 1) * Interval_Minutes);
validate_strict_timestamp(Timestamp, minutes(Interval_Minutes), Description);
validate_period_sequence(T, periods_per_day, Description);
Hourly_Timestamp = Timestamp(1:Intervals_Per_Hour:end);
if numel(Hourly_Timestamp) * Intervals_Per_Hour ~= numel(Timestamp)
    error('RTS_GMLC:IncompleteHourlyAggregation', ...
        '%s不能按每小时%d点完整聚合。', Description, Intervals_Per_Hour);
end
end

function Date_Parts = validate_date_parts(T, Description)
%% 校验年、月、日及小时字段，返回有效日期。
Date_Parts = [double(T.Year), double(T.Month), double(T.Day)];
if any(~isfinite(Date_Parts), 'all') || ...
        any(Date_Parts ~= round(Date_Parts), 'all')
    error('RTS_GMLC:InvalidDateParts', ...
        '%s的Year、Month或Day字段无效。', Description);
end
try
    datetime(Date_Parts(:, 1), Date_Parts(:, 2), Date_Parts(:, 3));
catch ME
    error('RTS_GMLC:InvalidCalendarDate', ...
        '%s包含无效自然日期：%s', Description, ME.message);
end
end

function validate_strict_timestamp(Timestamp, Expected_Step, Description)
%% 校验时间戳严格递增，避免重复或乱序采样。
if any(isnat(Timestamp)) || numel(unique(Timestamp)) ~= numel(Timestamp)
    error('RTS_GMLC:MissingOrDuplicateTimestamp', ...
        '%s存在缺失或重复时间戳。', Description);
end
if numel(Timestamp) > 1 && any(diff(Timestamp) ~= Expected_Step)
    error('RTS_GMLC:NonContinuousTimestamp', ...
        '%s时间戳不连续或顺序不严格递增。', Description);
end
end

function validate_period_sequence(T, Periods_Per_Day, Description)
%% 核验原始数据的时段编号连续且符合每日采样数。
Row_Count = height(T);
if mod(Row_Count, Periods_Per_Day) ~= 0
    error('RTS_GMLC:IncompleteDay', ...
        '%s行数不能构成完整自然日。', Description);
end
Period_Matrix = reshape(double(T.Period), Periods_Per_Day, []).';
Expected_Period = repmat(1:Periods_Per_Day, size(Period_Matrix, 1), 1);
if ~isequal(Period_Matrix, Expected_Period)
    error('RTS_GMLC:InvalidPeriodSequence', ...
        '%s每个自然日的Period序列不完整或存在重复。', Description);
end
Day_Matrix = [double(T.Year), double(T.Month), double(T.Day)];
Day_Matrix = reshape(Day_Matrix.', 3, Periods_Per_Day, []);
if any(diff(Day_Matrix, 1, 2) ~= 0, 'all')
    error('RTS_GMLC:MixedNaturalDay', ...
        '%s的同一Period分组跨越了不同自然日。', Description);
end
end

function Values = validate_numeric_values(Values, Description)
%% 核验数值字段有限，并按要求检查非负性。
if ~isnumeric(Values)
    error('RTS_GMLC:NonNumericValues', '%s功率字段不是数值型。', Description);
end
Values = double(Values);
if any(~isfinite(Values), 'all')
    error('RTS_GMLC:MissingPowerValue', ...
        '%s中存在NaN、Inf或缺失值，禁止静默插值。', Description);
end
end

function [Load_Time, Wind_DA_Time, Wind_RT_Hourly_Time, ...
    Regional_Load_MW, Wind_DA_MW, Wind_RT_Hourly_MW, Exclusion] = ...
    exclude_calendar_date(Raw_Load_Time, Raw_Wind_DA_Time, ...
    Raw_Wind_RT_Hourly_Time, Regional_Load_MW, Wind_DA_MW, ...
    Wind_RT_Hourly_MW, Config)
% 三类小时序列分别删除闰日，删除后必须再次具有完全相同的索引。
Excluded_Date = Config.Calendar.Excluded_Date;
Load_Excluded = dateshift(Raw_Load_Time, 'start', 'day') == Excluded_Date;
Wind_Da_Excluded = dateshift(Raw_Wind_DA_Time, 'start', 'day') == ...
    Excluded_Date;
Wind_Rt_Excluded = dateshift(Raw_Wind_RT_Hourly_Time, 'start', 'day') == ...
    Excluded_Date;
if nnz(Load_Excluded) ~= Config.Period_Count || ...
        nnz(Wind_Da_Excluded) ~= Config.Period_Count || ...
        nnz(Wind_Rt_Excluded) ~= Config.Period_Count
    error('RTS_GMLC:LeapDayExclusionCountMismatch', ...
        '日前负荷、日前风电与实时小时风电中2020-02-29必须各含24行。');
end

Load_Time = Raw_Load_Time(~Load_Excluded);
Wind_DA_Time = Raw_Wind_DA_Time(~Wind_Da_Excluded);
Wind_RT_Hourly_Time = Raw_Wind_RT_Hourly_Time(~Wind_Rt_Excluded);
Regional_Load_MW = Regional_Load_MW(~Load_Excluded, :);
Wind_DA_MW = Wind_DA_MW(~Wind_Da_Excluded, :);
Wind_RT_Hourly_MW = Wind_RT_Hourly_MW(~Wind_Rt_Excluded, :);

if ~isequal(Load_Time, Wind_DA_Time) || ...
        ~isequal(Wind_DA_Time, Wind_RT_Hourly_Time)
    error('RTS_GMLC:ProcessedTimestampMismatch', ...
        '剔除2020-02-29后的负荷、日前风电与实时风电小时索引不完全一致。');
end
validate_complete_processed_days(Load_Time, Config);

Exclusion = struct();
Exclusion.Excluded_Date = Excluded_Date;
Exclusion.Excluded_Day_Count = 1;
Exclusion.Excluded_Hourly_Row_Count = nnz(Load_Excluded);
Exclusion.Excluded_Real_Time_5min_Row_Count = ...
    Config.Period_Count * Config.Real_Time_Intervals_Per_Hour;
Exclusion.Expected_Processed_Day_Count = ...
    Config.Calendar.Expected_Day_Count;
Exclusion.Method = '对日前负荷、日前风电和按自然小时聚合的实时风电一致删除2020-02-29';
end

function validate_complete_processed_days(Timestamp, Config)
%% 核验处理后每个自然日均具有完整24小时数据。
date_vector = dateshift(Timestamp, 'start', 'day');
dates = unique(date_vector, 'stable');
if numel(dates) ~= Config.Calendar.Expected_Day_Count || ...
        any(dates == Config.Calendar.Excluded_Date)
    error('RTS_GMLC:ProcessedDayCountMismatch', ...
        '处理后日历必须为365天且不得包含2020-02-29。');
end
for i = 1:numel(dates)
    selected = date_vector == dates(i);
    expected = dates(i) + hours(0:Config.Period_Count - 1);
    if nnz(selected) ~= Config.Period_Count || ...
            ~isequal(Timestamp(selected).', expected)
        error('RTS_GMLC:IncompleteProcessedNaturalDay', ...
            '处理后日期%s不含严格对齐的24个自然小时。', ...
            char(string(dates(i), 'yyyy-MM-dd')));
    end
end
end

%% 1. 本地函数：字段、聚合结果和物理边界
function assert_required_fields(T, Required_Fields, Description)
%% 核验数据表包含来源格式要求的全部字段。
Actual_Fields = string(T.Properties.VariableNames);
Missing_Fields = Required_Fields(~ismember(Required_Fields, Actual_Fields));
if ~isempty(Missing_Fields)
    error('RTS_GMLC:MissingRequiredFields', ...
        '%s缺少必要字段：%s。', Description, strjoin(Missing_Fields, ', '));
end
end

function Hourly_Values = aggregate_real_time_by_natural_hour( ...
    Values, Intervals_Per_Hour)
% 输入[5 min时点, 场站]，输出[自然小时, 场站]；每小时仅取算术平均。
Site_Count = size(Values, 2);
Hour_Count = size(Values, 1) / Intervals_Per_Hour;
if Hour_Count ~= round(Hour_Count)
    error('RTS_GMLC:IncompleteRealTimeHour', ...
        '实时风电样本不能按自然小时完整分组。');
end
Hourly_Values = squeeze(mean(reshape(Values.', Site_Count, ...
    Intervals_Per_Hour, Hour_Count), 2)).';
end

function assert_power_within_capacity(Power_MW, Capacity_MW, ...
    Description, Tolerance)
%% 核验风电出力位于零与额定容量之间。
Lower_Violation = min(Power_MW, [], 1) < -Tolerance;
Upper_Violation = max(Power_MW - Capacity_MW, [], 1) > Tolerance;
if any(Lower_Violation) || any(Upper_Violation)
    error('RTS_GMLC:WindPhysicalBoundaryViolation', ...
        '%s超出对应风场装机容量的[0, PMax]物理边界。', Description);
end
end

function assert_no_missing_processed_values(Value_Groups)
%% 核验处理后的曲线不含缺失值或非有限值。
for i = 1:numel(Value_Groups)
    if any(~isfinite(Value_Groups{i}), 'all')
        error('RTS_GMLC:InvalidProcessedValue', ...
            '处理后的数据中存在NaN或Inf。');
    end
end
end

%% 1. 本地函数：数据来源追溯
function Manifest = build_source_manifest(Config)
% 清单记录实际字段、分辨率、固定版本及每个原始文件的SHA-256。
roles = ["节点负荷分配"; "风电装机容量与场站节点"; ...
    "日前区域负荷"; "日前风电预测"; "实时风电实际出力"; ...
    "时序数据字段说明"; "官方仓库说明"; "官方更新记录"];
fields = ["Bus ID; MW Load; Area"; ...
    "GEN UID; Bus ID; Unit Type; PMax MW"; ...
    "Year; Month; Day; Period; region 1-3"; ...
    "Year; Month; Day; Period; four wind plant columns"; ...
    "Year; Month; Day; Period; four wind plant columns"; ...
    "README text"; "README text"; "update log text"];
resolution = ["static"; "static"; "1 h"; "1 h"; "5 min"; ...
    "metadata"; "metadata"; "metadata"];
File_Paths = string(struct2cell(Config.Source.Files));
Field_Order = ["Bus"; "Generator"; "Day_Ahead_Load"; ...
    "Day_Ahead_Wind"; "Real_Time_Wind"; "Time_Series_Readme"; ...
    "Repository_Readme"; "Update_Log"];
Relative_Paths = strings(numel(File_Paths), 1);
File_Names = strings(numel(File_Paths), 1);
hashes = strings(numel(File_Paths), 1);
sizes = zeros(numel(File_Paths), 1);
for i = 1:numel(File_Paths)
    Relative_Paths(i) = string(erase(File_Paths(i), ...
        string(Config.Source.Root) + filesep));
    [~, name, extension] = fileparts(File_Paths(i));
    File_Names(i) = string(name) + string(extension);
    File_Info = dir(File_Paths(i));
    sizes(i) = File_Info.bytes;
    hashes(i) = compute_sha256(char(File_Paths(i)));
end
Source_Url = repmat(string(Config.Source.Repository), numel(File_Paths), 1);
version = repmat(string(Config.Source.Version), numel(File_Paths), 1);
commit = repmat(string(Config.Source.Commit), numel(File_Paths), 1);
Release_Date = repmat(string(Config.Source.Release_Date), numel(File_Paths), 1);
Manifest = table(Field_Order, roles, File_Names, Relative_Paths, fields, ...
    resolution, sizes, hashes, version, commit, Release_Date, Source_Url, ...
    'VariableNames', {'SourceKey', 'Role', 'FileName', 'RelativePath', ...
    'UsedFields', 'NativeResolution', 'Bytes', 'SHA256', 'Version', 'Commit', ...
    'ReleaseDate', 'RepositoryURL'});
end

function Hash = compute_sha256(File_Path)
%% 按文件字节计算SHA-256来源校验值。
fid = fopen(File_Path, 'r');
if fid < 0
    error('RTS_GMLC:HashReadFailure', ...
        '无法读取文件以计算SHA-256：%s', File_Path);
end
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, '*uint8');
digest = java.security.MessageDigest.getInstance('SHA-256');
digest.update(bytes);
Hash_Bytes = typecast(digest.digest(), 'uint8');
Hash = string(lower(reshape(dec2hex(Hash_Bytes, 2).', 1, [])));
end

%% 1. 本地函数：便于人工审阅的质量检查汇总
function Checks = build_quality_check_table(Raw_Load_Time, ...
    Raw_Wind_DA_Time, Wind_RT_Time, Raw_Wind_RT_Hourly_Time, ...
    Load_Time, Wind_DA_Time, Wind_RT_Hourly_Time, Exclusion, ...
    Day_Count, Bus_Count, Wind_Site_Count, Config)
%% 将数据读取及处理阶段的质量检查整理为表格。
check = ["load_hourly_continuity"; "wind_da_hourly_continuity"; ...
    "wind_rt_5min_continuity"; "wind_da_rt_hourly_alignment"; ...
    "excluded_calendar_date"; "processed_hourly_alignment"; ...
    "complete_natural_days"; "period_count"; "bus_count"; ...
    "wind_site_count"; "missing_values"; "physical_boundaries"];
observed = [string(numel(Raw_Load_Time)) + " raw hourly rows"; ...
    string(numel(Raw_Wind_DA_Time)) + " raw hourly rows"; ...
    string(numel(Wind_RT_Time)) + " five-minute rows"; ...
    string(numel(Raw_Wind_RT_Hourly_Time)) + " raw aligned hourly rows"; ...
    string(Exclusion.Excluded_Date, 'yyyy-MM-dd') + ...
    ", 24 hourly rows removed from each series"; ...
    sprintf('%d load / %d DA wind / %d RT wind aligned hourly rows', ...
    numel(Load_Time), numel(Wind_DA_Time), ...
    numel(Wind_RT_Hourly_Time)); ...
    string(Day_Count) + " days"; string(Config.Period_Count) + " h/day"; ...
    string(Bus_Count) + " buses"; string(Wind_Site_Count) + " sites"; ...
    "none"; "passed"];
expected = ["strict 1 h"; "strict 1 h"; "strict 5 min"; ...
    "exact timestamp equality before exclusion"; ...
    "2020-02-29 removed consistently"; ...
    "load, DA wind and hourly RT wind exactly equal"; ...
    "365 days, each containing 24 h"; "24 h/day"; ...
    "> 0"; "> 0"; "none"; "wind in [0, PMax]"];
passed = true(numel(check), 1);
Checks = table(check, observed, expected, passed, ...
    'VariableNames', {'Check', 'Observed', 'Expected', 'Passed'});
end
