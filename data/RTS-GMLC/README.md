# RTS-GMLC典型日与风电场景预处理模块

本模块基于RTS-GMLC官方公开全年时序数据，生成随机优化模型后续可用的24 h典型日、节点负荷曲线和RT实际风电场景。本模块不写入或修改`data/params`，也不修改现有规划模型。


## 目录结构

- `scripts/`：用户直接运行的入口脚本。
- `functions/config/`：固定配置与路径。
- `functions/io/`：原始数据读取与结果保存。
- `functions/clustering/`：典型日与风电场景生成。
- `functions/validation/`：代表性与质量验证。
- `functions/visualization/`：结果绘图。
- `raw/`：只读官方原始数据。
- `processed/`：当前正式方法的研究与验证结果。
- `final/`：冻结的D=4、K=4优化输入预留目录。
- `archive/`：旧版处理结果留档。
\n## 数据来源

- 官方仓库：<https://github.com/GridMod/RTS-GMLC>
- 固定版本：`v0.2.3`
- 固定提交：`3ece0d3725c844056132393ee252b3083dd4eab4`
- 原始数据目录：`data/RTS-GMLC/raw/rts_gmlc_v0.2.3`
- 处理结果目录：`data/RTS-GMLC/processed/rts_gmlc_v0.2.3_fixed_extreme_medoids/run_yyyyMMdd_HHmmss`

实际读取文件、字段、原始分辨率、字节数和SHA-256均写入每次结果的`source_manifest.csv`、XLSX的`Source_Manifest`工作表及MAT结构体`Result.Source_Manifest`。官方数据使用声明保留在原始目录的官方`README.md`中。

## 方法约定

1. 原始官方2020年数据先完成严格时间戳校验；随后对负荷、日前风电和小时聚合后的实时风电一致删除`2020-02-29`，形成365个完整自然日。负荷与日前风电保持官方1 h分辨率；实时风电5 min序列按自然小时的12个点取算术平均。
2. 全系统负荷先对三个区域求和，全部节点按`bus.csv`的区域内静态负荷占比展开。系统与所有节点统一除以全年系统小时峰值负荷，不做逐节点、逐日或min-max归一化。
3. 每个风场的日前与实时出力均除以`gen.csv`中相同场站的`PMax MW`；系统风电除以四个风场总装机容量。
4. 基于系统总负荷与系统聚合日前风电构造日前净负荷，将全年最大、最小日前净负荷所在真实日期固定为不可交换的两个medoid。
5. 以365天的24维系统负荷轨迹与24维系统日前风电轨迹构造联合特征，两块特征分别按小时跨全年做z-score。在固定两个极端medoid的约束下，以PAM交换搜索选取其余`D-2`个medoid，并将全部365天分配到最近的`D`个中心。`D=3:5`表示最终典型日总数，各典型日权重为对应成员天数，权重和严格为365。
6. 对每个典型日的成员日，直接对系统聚合、归一化RT实际风电完整24 h轨迹独立做k-medoids场景缩减，不再使用“DA+预测误差medoid”重构，也不做人工clip。
7. 对每个`D`分别请求统一`K=2:5`：同一`(D,K)`组合下的每个典型日都必须生成恰好K条场景。若任一典型日成员数小于K，则整个组合标记为不可用并记录原因，不降低K，也不复制伪场景。
8. 两座GFL-WG后续共用同一系统聚合归一化风电场景；本模块不映射至IEEE-30绝对容量。
9. 代表性统计中的净负荷先将风电容量因子按RTS-GMLC风电总装机换算为MW，再与负荷MW共同除以全年峰值负荷基准后相减。
10. 爬坡统计只使用同一自然日内相邻小时的23个差分，不人为拼接不同自然日。
11. 固定随机种子为`20260818`。脚本计算并保存全部`D=3:5`和`K=2:5`结果，不自动选择最终D或K。

## 运行

在项目根目录的MATLAB中执行：

```matlab
run('data/RTS-GMLC/scripts/run_rts_gmlc_data_generation.m')
```

需要MATLAB R2024b兼容环境和Statistics and Machine Learning Toolbox。脚本遇到缺失值、重复时间戳、不连续时间戳、日前/实时小时索引不一致、无效维度、概率和错误或物理边界异常时直接报错，不进行插值、静默排序或修正。统一K的样本不足按`(D,K)`明确标记为不可用并保存原因。

## 建议人工审阅顺序

1. `build_rts_gmlc_preprocessing_config.m`：确认固定版本、D/K范围、随机种子、时间尺度与容差。
2. `load_rts_gmlc_annual_data.m`：确认五个实际数据文件、严格时间对齐、闰日删除和统一归一化基准。
3. `generate_rts_gmlc_typical_days.m`：确认两个固定极端medoid、48维联合特征和全年最近中心分配。
4. `generate_rts_gmlc_wind_scenarios.m`：确认统一K可用性判定、RT真实轨迹medoid及场景概率。
5. `validate_rts_gmlc_representativeness.m`：确认DA/RT验证口径、净负荷换基准和日内爬坡定义。
6. `save_...`与`plot_...`：最后核对MAT结构、22张平面表及图件，不在此处改变数据口径。

代码中的数组维度统一写作`[day, hour]`、`[node, day, hour]`或`[typical_day, scenario, hour]`。局部函数按“校验/计算/展平保存”分组；注释重点解释数据口径和约束原因，不逐行复述MATLAB语法。

## 主要输出

- `*.mat`：完整结构体，包括年度/逐日系统数据、节点负荷、场站曲线、D/K结果、成员映射和验证表。
- `*.xlsx`：22个工作表，包含独立的`Scenario_Availability`可用性清单，适合集中人工审阅。
- `csv/*.csv`：与XLSX工作表对应的独立表格，便于版本比较和脚本读取。
- `figures/*.fig|*.png|*.pdf`：D对比、典型日曲线、各典型日的K对比场景和全年统计误差图。
