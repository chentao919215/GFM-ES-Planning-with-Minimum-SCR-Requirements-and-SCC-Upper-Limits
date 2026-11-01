# RTS-GMLC典型日与风电场景

## 1. 项目简介

本模块将RTS-GMLC全年负荷与风电数据处理为本项目使用的典型日和风电场景。Manuscript采用4个典型日(D=4)，每个典型日包含24个1 h时段，并配置4个风电场景(K=4)。

原始数据固定为[RTS-GMLC 官方仓库](https://github.com/GridMod/RTS-GMLC)的v0.2.3版本，提交为`3ece0d3725c844056132393ee252b3083dd4eab4`。数据来源记录见`raw/rts_gmlc_v0.2.3/SOURCE_PROVENANCE.md`，官方使用声明保留在该目录的`README.md`中。

`processed/`保存固定的Manuscript输入。直接进行规划复现时使用这些文件即可，无需重新运行数据预处理。
归一化曲线在[参数生成脚本](../params/generate_multiple_snapshot_default_params.m)中按IEEE-30原始节点负荷分布和GFL-WG额定容量映射。

## 2. 项目环境与依赖

- **MATLAB R2024b**：读取固定输入、导出表格和绘图。
- **Statistics and Machine Learning Toolbox**：仅重新生成典型日和风电场景时需要，用于`kmedoids`和`pdist2`。

运行前，按项目根目录README的说明，将项目根目录及其子目录加入MATLAB搜索路径。绘图读取`data/params/multiple_snapshot_default_params.json`中的负荷与风电容量设置；修改参数后，应按主项目流程重新生成该JSON。

## 3. 代码结构

- **`raw/`**：五个官方CSV及来源、格式和数据使用说明；保留原始内容。
- **`processed/`**：一个精简 MAT 和四个 CSV，作为Manuscript固定输入及其可读副本。
- **`results/`**：本模块运行后生成的数据和FIG图件，不纳入Git版本管理。
- **`scripts/run_rts_gmlc_data_generation.m`**：数据生成入口脚本，串联读取、聚类、验证与保存。
- **`scripts/plot_rts_gmlc_profiles.m`**：绘图入口脚本，绘制D=4、K=4的负荷与风电场景合图。
- **`functions/config/`**：数据版本、D/K、随机种子、时间尺度和输出目录。
- **`functions/io/`**：原始数据读取、校验和精简结果保存。
- **`functions/clustering/`**：固定两个极端日的典型日生成，以及实时风电场景缩减。
- **`functions/validation/`**：代表性、极端日保持和全年统计偏差核验。

`processed/`中各文件的用途如下：

| 文件 | 内容 |
|------|-----|
| `rts_gmlc_profiles.mat`     | `Result` 结构体，包含曲线、权重、场景概率、代表日期、归一化口径、来源清单及验证记录 |
| `typical_day_profiles.csv`  | 典型日逐时负荷、日前风电归一化曲线，以及日期和权重 |
| `wind_scenario_profiles.csv`| 风电场景逐时归一化曲线及对应概率 |
| `source_manifest.csv`       | 原始文件的相对路径、版本、使用字段、字节数和 SHA-256 |
| `quality_checks.csv`        | 原始数据及最终输入的质量检查记录 |

MAT中的负荷曲线维度为`[典型日, 时段]`，风电场景曲线为`[典型日, 场景, 时段]`，概率为`[典型日, 场景]`。年度数组、RTS节点负荷展开结果和重复平面表不保存在最终MAT中。

CSV按小时展平：同一典型日的权重在各小时重复记录，同一风电场景的概率也重复记录。汇总权重或概率时，每个典型日或场景取一次。

两个入口均将输出保存到本模块的`results/`目录：数据生成脚本在`results/run_时间戳/`中保存一个MAT和四个CSV；绘图脚本保存`results/rts_gmlc_D4_K4_profiles.fig`，重复运行时覆盖同名图件。FIG文件可在MATLAB中打开并继续编辑。

## 4. 结果复现步骤

### 4.1 读取固定输入与绘图

在MATLAB编辑器中打开绘图入口脚本并点击“运行”，或在命令行执行：

```matlab
plot_rts_gmlc_profiles;
```

脚本将固定输入读取到工作区变量`Result`，负荷与风电容量取自当前项目参数JSON，FIG文件位置记录在`Figure_File`中。需要指定其他输入或输出位置时，修改脚本开头的`Result_File`、`Parameter_File`和`Figure_Directory`。若要绘制某次重新生成的数据，将`Result_File`指向该次`results/run_时间戳/`中的MAT文件。

### 4.2 从官方原始数据重新生成

```matlab
run_rts_gmlc_data_generation;
Regenerated = Result;
```

也可在MATLAB编辑器中打开数据生成入口脚本并点击“运行”。脚本将生成结果保存在工作区变量`Result`中，输出文件位置记录在`Output`中；上例将结果另存为`Regenerated`，用于下方核对。默认仅生成Manuscript使用的D=4、K=4。数据版本、D/K、随机种子和重复次数集中定义在`build_rts_gmlc_preprocessing_config.m`中。

处理过程一致删除2020-02-29，将5 min实时风电按自然小时取均值；负荷统一除以全年系统峰值，系统风电统一除以风电总装机容量。典型日保留最大和最小日前净负荷所在日作为固定中心，风电场景取对应成员日的真实实时风电轨迹。时间戳、物理边界、权重与概率不符合约定时直接报错。

生成过程不会覆盖`processed/`，也不会修改项目参数JSON。运行完成后，可核对Manuscript输入：

```matlab
Input = load(fullfile(Module_Directory,'processed','rts_gmlc_profiles.mat'));
Reference = Input.Result;
assert(isequaln(Regenerated.Typical_Day_Sets.System_Load_Normalized, ...
    Reference.Typical_Day_Sets.System_Load_Normalized));
assert(isequaln(Regenerated.Typical_Day_Sets.Weight_Days, ...
    Reference.Typical_Day_Sets.Weight_Days));
assert(isequaln(Regenerated.Wind_Scenario_Sets.Wind_Scenario_Normalized, ...
    Reference.Wind_Scenario_Sets.Wind_Scenario_Normalized));
assert(isequaln(Regenerated.Wind_Scenario_Sets.Probability, ...
    Reference.Wind_Scenario_Sets.Probability));
```

若需要更新固定输入，核对后将该次运行的MAT和四个CSV一并替换到`processed/`，随后重新生成项目参数JSON。
