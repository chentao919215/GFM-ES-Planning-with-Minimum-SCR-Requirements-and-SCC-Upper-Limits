function Config = build_rts_gmlc_preprocessing_config(Module_Directory)
%% 构造RTS-GMLC预处理模块的固定配置
% 输入为模块绝对路径；输出集中保存数据版本、算法参数、日历口径与输出路径。
% 所有会影响结果复现的常量均只在本函数定义，其他函数不得另设隐式默认值。

arguments
    Module_Directory (1, :) char
end

Data_Directory = Module_Directory;

%% 1. 时间尺度、候选规模与数值容差
Config = struct();
Config.Random_Seed = 20260818;
Config.D_Values = 4;
Config.K_Values = 4;
Config.Forced_Extreme_Day_Count = 2;
Config.Period_Count = 24;
Config.Period_Duration_Hours = 1;
Config.Real_Time_Intervals_Per_Hour = 12;
Config.KMedoids_Replicates = 20;
Config.KMedoids_Distance = 'sqeuclidean';
% kmedoids与pdist2对同一距离使用不同名称，数值定义均为平方欧氏距离。
Config.Pairwise_Distance = 'squaredeuclidean';
Config.Fixed_Medoid_Swap_Max_Iterations = 100;
Config.Numeric_Tolerance = 1e-10;
Config.Probability_Tolerance = 1e-12;

Config.Calendar = struct();
Config.Calendar.Excluded_Date = datetime(2020, 2, 29);
Config.Calendar.Expected_Day_Count = 365;

%% 2. 固定数据版本与实际读取文件
Config.Source = struct();
Config.Source.Repository = 'https://github.com/GridMod/RTS-GMLC';
Config.Source.Version = 'v0.2.3';
Config.Source.Commit = '3ece0d3725c844056132393ee252b3083dd4eab4';
Config.Source.Release_Date = '2025-10-23';
Config.Source.Root = fullfile(Data_Directory, 'raw', ...
    'rts_gmlc_v0.2.3');
Config.Source.Data_Root = fullfile(Config.Source.Root, 'RTS_Data');
Config.Source.Files = struct();
Config.Source.Files.Bus = fullfile(Config.Source.Data_Root, ...
    'SourceData', 'bus.csv');
Config.Source.Files.Generator = fullfile(Config.Source.Data_Root, ...
    'SourceData', 'gen.csv');
Config.Source.Files.Day_Ahead_Load = fullfile(Config.Source.Data_Root, ...
    'timeseries_data_files', 'Load', ...
    'DAY_AHEAD_regional_Load.csv');
Config.Source.Files.Day_Ahead_Wind = fullfile(Config.Source.Data_Root, ...
    'timeseries_data_files', 'WIND', 'DAY_AHEAD_wind.csv');
Config.Source.Files.Real_Time_Wind = fullfile(Config.Source.Data_Root, ...
    'timeseries_data_files', 'WIND', 'REAL_TIME_wind.csv');
Config.Source.Files.Time_Series_Readme = fullfile( ...
    Config.Source.Data_Root, 'timeseries_data_files', 'README.md');
Config.Source.Files.Repository_Readme = fullfile( ...
    Config.Source.Root, 'README.md');
Config.Source.Files.Update_Log = fullfile( ...
    Config.Source.Root, 'RTS-GMLC_updates.md');

%% 3. 独立结果目录
Config.Output = struct();
% 重新生成的结果独立保存，processed中的Manuscript输入保持固定。
Config.Output.Root = fullfile(Module_Directory, 'results');

end
