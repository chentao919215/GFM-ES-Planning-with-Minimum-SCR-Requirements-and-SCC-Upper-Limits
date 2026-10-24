# GFM-ES 安全配置优化项目

本项目研究高比例跟网型风电（GFL-WG）接入条件下，构网型储能（GFM-ES）的模块投建、同步机启停与运行协同优化。默认数学模型依据用户确认的 `manuscript_10_23_17_40` Section II 式（1）—（26）、Section III 式（27）—（35）及 Appendix，实现 SCC 上限和 SCR 下限下的多典型日规划。

本次同步包括五个 Case 的安全指标与 UC 绘图、聚合保守性散点图、灵敏度分析，以及新版 Aggregated/Period-Wise 时间尺度对照。仓库参数和归档结果按其自身配置解释；论文 Section IV 的最终参数与结果仍需研究者确认，旧版结果不能作为新版模型的正确答案。

## 环境与目录

- MATLAB R2024b；设备仿真另需 Simulink 及相应电气工具箱。
- MATPOWER（提供 `case30`，本地验证版本为 7.1）。
- YALMIP（提供 `sdpvar`、`optimize`；比较计算时间时应固定版本）。
- **Gurobi 是唯一规划求解器**，需安装 MATLAB API 和有效许可证；本地新版 T=3 验证使用 Gurobi 13.0。

MATPOWER、YALMIP 和 Gurobi 不随仓库分发。先将其加入 MATLAB 路径；时间尺度入口还支持通过 `MATPOWER_PATH`、`YALMIP_PATH`、`GUROBI_MATLAB_PATH` 或 `GUROBI_HOME` 定位依赖。添加 MATPOWER 路径时应避免将 `.github` 等元数据中的可选求解器测试包装加入搜索路径。

```text
code/functions/                 参数读取、网络、优化、安全计算与结果处理
code/scripts/system/            规划、灵敏度和时间尺度分析入口
code/scripts/figure/for_paper/  论文绘图脚本
code/scripts/equipment/         设备级参数与仿真脚本
code/tests/                     自动化测试及模拟阶段求解夹具
data/params/                    参数源 .m 和生成后的 JSON 快照
data/RTS-GMLC/                  典型日/场景输入与来源说明
results_useful/from_laptop/     既有归档和本地绘图输入
simulink/models/                设备模型
docs/                          模型迁移、参数与分析说明
results/                       本地求解结果（忽略）
figs/                          本地生成图
logs/                          本地日志（忽略）
```

以下 MATLAB 示例先在项目根目录执行（也可将 `pwd` 改为实际检出路径）：

```matlab
Project_Root = pwd;
addpath(genpath(fullfile(Project_Root, 'code', 'functions')));
addpath(fullfile(Project_Root, 'code', 'scripts', 'system'));
```

## 参数与风电不确定性

参数维护入口为 `data/params/generate_multiple_snapshot_default_params.m`，输出 `data/params/multiple_snapshot_default_params.json`。修改默认参数时先修改脚本，再生成 JSON，避免快照被下一次运行覆盖。

`%% 4. Security` 中的当前默认开关为：

```matlab
params.Security.Enable_SCC = false;
params.Security.Enable_SCR = false;
params.Security.Consider_Wind_Uncertainty = 0;
```

- `Consider_Wind_Uncertainty = 1`：采用每个典型日的完整原始 4 条风电场景及其原始概率，属于随机优化模型。
- `Consider_Wind_Uncertainty = 0`：对每个典型日、节点、时段计算原始场景的概率加权平均，作为唯一风电轨迹；场景数和概率均设为 1，属于确定性模型。公式为 `P_mean(d,n,t) = sum_k pi(d,k) * P_available(d,n,k,t)`，保持原容量映射和 MW 单位。不会选取任意一条场景，也不会以等概率代替缺失的真实概率。

原始输入为 4 个典型日、每日至 4 个风电场景、24 个 1 h 时段。风电开关只改变风电场景输入，负荷、典型日权重及运行约束保持原含义。仅风电可用功率作为随机输入。

默认快照关闭 SCC/SCR 限值；完整随机安全模型须显式开启三个开关。式（29）—（30）的源支撑约束位于规划约束中，**不随 SCC/SCR 限值开关关闭**。节点、模块、LVRT、效率/SOC/额定时长、UC、成本与安全阈值均应结合目标算例核实。

参数源支持可选 `Parameter_Generation_Options.Output_File` 和 `.Case_5=true`，用于独立生成“双安全约束开启、原始四场景”的 Case 5 快照，不覆盖默认 JSON。联合灵敏度扫描已使用此接口，详见[联合扫描说明](docs/scc_scr_joint_sensitivity.md)。

## 规划模型与入口

主入口保持 MATLAB **脚本**形式：

```matlab
clear Parameter_File Parameter_Generation_Options
run(fullfile(Project_Root, 'code', 'scripts', 'system', ...
    'run_multiple_snapshot_planning.m'));
```

未设置 `Parameter_File` 时，入口重新运行参数生成脚本；若先将该变量设为已有 JSON 的路径，则直接读取指定文件。主入口按参数执行单阶段或两阶段求解，保存结果后调用环境中的 `mailTome` 发送完成通知。仓库不提供该外部通知函数；缺少它时通知步骤可能报错，已保存的规划结果仍保留。后台入口为 `start_multiple_snapshot_planning_longrun.m`。

只构建模型而不求解，可使用：

```matlab
Parameter_File = fullfile(Project_Root, 'data', 'params', ...
    'multiple_snapshot_default_params.json');
[mpc, CONF] = load_multiple_snapshot_case(Project_Root, Parameter_File);
Model = build_multiple_snapshot_planning_model(mpc, CONF);
assert(all(is(Model.Constraints, 'linear')));
assert(degree(Model.Objective) <= 1);
```

新版实现的关键关系：

- GFM-ES 投建跨典型日、场景及时段共享；UC 在同一典型日内跨风电场景共享。有功、潮流、弃风、充放电和能量按场景、时段建模。
- Aggregated 以日内 UC 并集计算 SCC 上界，以交集计算 SCR 下界；安全网络不随风电场景复制。
- SCC 联立计算故障点虚拟阻抗修正、非故障节点残压及远端 GFL-WG 三段 LVRT 电流；二进制乘积采用有效界下的精确 McCormick 约束。
- 源支撑覆盖安全网络和故障母线移除后的连通分量；已投建 GFM-ES 在充电、放电及零有功状态下均提供构网支撑。
- 复用标准 UC、DC 潮流、分段透视成本割及储能约束。典型日之间独立，日内 UC、爬坡、最小开停机时间和 SOC 采用循环衔接。

`ModelVersion='2026-10-23'` 为默认新版。旧配置枚举、`lambda_c`、UC 状态枚举和旧 SCC 分步上界仅保留在显式 `ModelVersion='legacy'` 路径中。公式与文件映射见[模型迁移说明](docs/model_migration_20261023.md)。

## 五个 Case 与论文绘图

五个 Case 的绘图读取本地 `results_useful/from_laptop/IV-B/Case_1_Stage_2.mat` 至 `Case_5_Stage_2.mat`。本地已核验这些结果均记录新版模型及逐时 SCC/SCR；本次提交不新增或更新 MAT 输入，其他设备需自行提供这些归档。绘图只读结果，不重新优化。

| Case | SCC 上限 | SCR 下限 | 风电模型 |
| --- | --- | --- | --- |
| 1 | 关闭 | 关闭 | 确定性，1 场景 |
| 2 | 关闭 | 开启 | 确定性，1 场景 |
| 3 | 开启 | 关闭 | 确定性，1 场景 |
| 4 | 开启 | 开启 | 确定性，1 场景 |
| 5 | 开启 | 开启 | 随机，4 场景 |

绘图入口均位于 `code/scripts/figure/for_paper/`：

| 脚本 | 内容与输入 |
| --- | --- |
| `plot_fig3_security_metrics.m` | 五个 Case 的逐时最大 SCC、最小 SCR 与限值 |
| `plot_fig4_selected_uc_schedules.m` | Case 2/4/5、Day 2 的 Bus 2/23 UC；已移除 Bus 22，配色与 Fig. 3 一致 |
| `plot_fig5_scc_conservatism_scatter.m` | 五个 Case 的逐时最大 SCC 与并集 SCC 上界 |
| `plot_fig6_scr_conservatism_scatter.m` | 五个 Case 的逐时最小 SCR 与交集 SCR 下界 |
| `plot_fig6_scc_sensitivity.m` | `IV-C/SCC` 归档的 8 个 SCC 阈值结果 |
| `plot_fig7_scr_sensitivity.m` | `IV-C/SCR` 归档的 6 个 SCR 阈值结果 |
| `plot_fig8_temporal_model_size.m` | 读取 `from_desktop/IV-D` 的 T=3/6/12/24 模型规模归档 |
| `plot_fig9_temporal_solution_time.m` | 读取同一时间尺度归档的分阶段求解时间 |

历史文件名保留既有编号，因此两个不同用途的脚本含 `fig6`；调用时使用完整文件名。Fig. 8/9 所需的完整四尺度归档未随本次提交提供，当前新版 T=3 验证不能填补其余三个尺度。

在所需本地 MAT 归档齐备后，最小绘图命令为（无需求解器许可证）：

```matlab
run(fullfile(Project_Root, 'code', 'scripts', 'figure', ...
    'for_paper', 'plot_fig3_security_metrics.m'));
```

将文件名替换为表中其他入口即可生成对应图。输出位于 `figs/for_paper/`，包括脚本各自导出的 FIG、PDF、PNG 和统计 CSV。

**版本区别：** `IV-C/SCC` 和 `IV-C/SCR` 是旧版灵敏度归档，含 `lambda_c`，未记录新版 `ModelVersion`。它们用于重绘已有分析图，不验证新版 SCC 或新版灵敏度趋势；新计算应使用当前模型重新求解并保存独立结果。

## 新版时间尺度对照（当前仅 T=3）

```matlab
run(fullfile(Project_Root, 'code', 'scripts', 'system', ...
    'run_temporal_scalability_analysis.m'));
```

该入口会实际启动优化。当前 `Period_Counts = 3`，总时长保持 24 h，每段 8 h。入口读取现有默认 JSON 的物理与求解设置，在独立运行目录生成 SCC/SCR 全开、4 典型日、原始 4 场景的输入，不覆盖默认 JSON。

Aggregated 和 Period-Wise 均调用新版公共模型，投建/UC 决策、场景运行、成本和求解设置相同；区别仅为安全约束采用日内并集/交集状态，或逐时实际 UC 状态。旧版 legacy 不是该实验的对照模型，PW 也不再使用 5 倍时限。

从 24 个小时连续分块取平均，保持负荷和风电的日能量；典型日权重与原始场景概率不变。最小开停机时间按新时长向上取整，爬坡参数保持 MW/h 含义。两模型使用相同的阶段原生时限（当前 300/900 s）与目标 gap（0.005）；Stage 2 的名义 `Time_Limit=1800` 被原生 Gurobi `TimeLimit=900` 覆盖，比较时以实际原生选项为准。

结果保存到 `results/multiple_snapshot_temporal_scalability_<timestamp>/`，包括冻结基准 JSON、各 T 输入、AG/PW 分阶段 MAT 与汇总 MAT/CSV。2026-10-24 的 T=3 单次验证记录如下，时间取决于硬件和求解环境：

| 指标 | Aggregated | Period-Wise |
| --- | --- | --- |
| 标量变量 | 11,086 | 14,382 |
| 二进制变量 | 534 | 774 |
| 标量约束 | 24,389 | 32,869 |
| 年总成本 | 2,323,417.2745 | 2,323,417.2745 |
| 两阶段流程时间 / s | 7.058 | 18.696 |

流程时间包括建模、求解、提取及后验复算，不等同于 Gurobi 内部时间。该次两模型的功率平衡最大误差为 `1.64e-13 MW` 以内，成本复算误差为 `7e-10` 以内，并通过逐时安全复核及 MILP 结构检查；最优解未投建储能，因此该次运行不覆盖非零储能运行。T=6/12/24 未在本轮执行。

## 灵敏度分析与测试

- `run_scc_sensitivity_analysis.m`、`run_scr_sensitivity_analysis.m`：一维扫描，会重新生成默认 JSON；运行前须在参数源启用 SCC、SCR 和原始四场景，并满足扫描函数的基准检查。
- `run_scc_scr_joint_sensitivity_analysis.m`：二维 Case 5 扫描，冻结独立输入、保存完整诊断并支持校验后续算。**当前入口 `Execute_Full_Scan=true`，运行会求解 6×6 网格**；若只准备输入，应先设为 `false`。底层函数 `Options.Execute` 缺省为 `false`。详见[联合扫描说明](docs/scc_scr_joint_sensitivity.md)。

轻量回归测试使用模拟阶段求解器，不调用实际优化：

```matlab
runtests(fullfile(Project_Root, 'code', 'tests', ...
    'test_scc_scr_joint_sensitivity.m'))
```

当前 6 项测试全部通过，覆盖原始场景与概率、网格索引、模块映射、成本、状态分类、结果完整性、续算和考虑 MIP 区间的单调性检查。本次文档/同步工作未启动真实联合网格求解。早期模型迁移的独立测试记录见迁移说明，不将旧版数值结果作为新版回归答案。

同步前另完成默认配置 MILP 构建检查；原始场景概率和误差及确定性加权平均轨迹误差均为 0，确定性输入尺寸为 `[30,4,1,24]`。使用本地归档实际运行了 Fig. 3、UC 图、两张保守性散点图及两张灵敏度图的六个脚本，均成功导出；这些 MAT 输入与生成图未纳入本次提交。26 个待提交 MATLAB 文件静态检查仅有动态扩展、未使用变量或多余抑制标记提示。

结果复核应同时查看 `Diagnostics.problem`、原生 `solver_status`、是否存在可行整数解和 gap。新版 `Result.SCC_1`/`SCR` 分别为并集上界/交集下界；`SCC_TimeResolved`/`SCR_TimeResolved` 为最终决策下实际逐时后验值，不能混用。`SecurityValidation` 和 `Diagnostics.SecurityPosthocRegression` 记录相应保守性或辅助变量复算检查。

## 随版本提供的数据边界

复现参数生成所需的 16.3 MiB 原始场景 MAT **已纳入版本控制**：

```text
data/RTS-GMLC/processed/rts_gmlc_v0.2.3_fixed_extreme_medoids/
  run_20260822_162606/
    rts_gmlc_typical_days_and_wind_scenarios_20260822_162606.mat
```

数据来源见 [RTS-GMLC 说明](data/RTS-GMLC/README.md) 和该目录的 `csv/source_manifest.csv`、`run_metadata.csv`。参数生成和本文列出的分析不需要额外提交完整上游原始数据副本、年度 CSV、Excel 副本或重复中间结果。

本次同步不新增或更新 MAT 文件。已有受版本控制的源场景文件和历史结果保持原状；新增绘图所需的本地输入须另行准备：IV-B 五个 Stage-2 MAT、IV-C 的 8 个 SCC 与 6 个 SCR MAT，或 Fig. 8/9 的完整时间尺度归档。具体文件名见相应脚本开头和数据校验函数；缺少输入时脚本会报出路径，不会自动补造数据。新求解结果、求解日志、生成图、设备调试输出、缓存、本地论文 DOCX/PDF 和许可证也不属于本次同步范围。

## 设备级模型

设备模型位于 `simulink/models/`。GFM 参数入口为 `code/scripts/equipment/GFM/GFM_Parameters.m`，经 `GFM_Inherited_Parameters.m` 读取系统级 JSON 并换算设备基准；GFL 参数入口为 `code/scripts/equipment/GFL/GFL_Parameters.m`。报告验证脚本位于 `code/scripts/equipment/for_report/`，相关绘图位于 `code/scripts/figure/for_report/`。

系统规划的额定电流、LVRT 和虚拟电抗采用参数文件中的单位与基准；设备仿真需使用匹配的参数快照。Simulink 缓存写入被忽略的 `simulink/artifacts/`。本次同步聚焦算例分析，不包含本地设备模型或教学材料的额外改动。
