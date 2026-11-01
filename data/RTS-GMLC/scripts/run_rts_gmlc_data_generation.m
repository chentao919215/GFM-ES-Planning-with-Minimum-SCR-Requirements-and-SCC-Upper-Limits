%% 从官方数据生成Manuscript使用的典型日和风电场景。
% 结果写入本模块results/run_时间戳目录，不覆盖processed中的固定输入。
% 运行前按项目README配置MATLAB搜索路径。
% 运行完成后，Result保存生成结果，Output记录输出文件位置。

Module_Directory = fileparts(fileparts(which('run_rts_gmlc_data_generation')));
Config = build_rts_gmlc_preprocessing_config(Module_Directory);
Original_RNG = rng;

fprintf('RTS-GMLC数据生成：版本%s，D=%s，K=%s。\n', ...
    Config.Source.Version, mat2str(Config.D_Values), mat2str(Config.K_Values));

%% 1. 读取、校验并归一化官方全年数据
Data = load_rts_gmlc_annual_data(Config);

%% 2. 固定两个极端日，生成典型日与风电场景
Typical_Day_Sets = generate_rts_gmlc_typical_days(Data, Config);
Wind_Scenario_Sets = generate_rts_gmlc_wind_scenarios( ...
    Data, Typical_Day_Sets, Config);

%% 3. 验证代表性并保存精简结果
Validation = validate_rts_gmlc_representativeness( ...
    Data, Typical_Day_Sets, Wind_Scenario_Sets, Config);
[Result, Output] = save_rts_gmlc_preprocessing_results( ...
    Data, Typical_Day_Sets, Wind_Scenario_Sets, Validation, Config);

fprintf('完成：%d个自然日，每日%d个时段。\n', ...
    Result.Dimensions.Valid_Day_Count, Result.Dimensions.Period_Count);
fprintf('MAT与CSV结果目录：%s\n', Output.Run_Directory);
rng(Original_RNG);
clear Original_RNG;
