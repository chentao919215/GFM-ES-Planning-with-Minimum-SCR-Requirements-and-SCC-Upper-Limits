# GFM-ES安全配置优化项目

## 2026-10 新版论文模型入口

默认规划模型已对齐用户确认的 `manuscript_10_23_17_40`。新版直接优化 GFM-ES 模块投建和逐时 UC，以日内 UC 并集计算 SCC、以交集计算 SCR，并在故障点和故障后连通分量施加源支撑约束（Section II 式（1）—（26）、Section III 式（27）—（35）及 Appendix）。旧模型仅通过显式 `ModelVersion = 'legacy'` 路由，不能与新版变量或约束混用。

详细公式映射和验证记录见[新版模型迁移说明](docs/model_migration_20261023.md)。主入口脚本保持脚本形式：若工作区已设置 `Parameter_File`，脚本直接读取该 JSON；否则运行参数生成脚本并重生成默认 JSON。求解结束后脚本会调用 `mailTome` 发送完成通知。新版 Section IV 算例参数尚未确认，因此仓库现有参数只可视为历史输入，不能据此声称复现了新版算例结果。

## 2026-09 IV-C 灵敏度绘图脚本

- 补充论文 IV-C 灵敏度结果绘图脚本：`code/scripts/figure/for_paper/plot_fig6_scc_sensitivity.m`（SCC）和 `plot_fig7_scr_sensitivity.m`（SCR）。
- Fig. 6/7 脚本读取 `results_useful/from_laptop/IV-C/{SCC,SCR}` 下的 13 个 Stage-2 `.mat` 结果；这些绘图输入随版本提交，脚本不会自动重新运行规划求解。

## 历史 IV-D 聚合与逐时安全建模的时间尺度扫描

- 入口脚本为 `code/scripts/system/run_temporal_scalability_analysis.m`，会启动规划优化。扫描输入将 `ModelVersion` 显式设为 `legacy`，对照旧版聚合安全模型与旧版逐时（PW）安全模型；结果不验证新版聚合安全模型，也不是新版论文算例结果。
- 当前脚本扫描周期数为 `Period_Counts = [3, 6, 12, 24]`；已完成的旧扫描结果应按其记录的输入与求解配置解释。
- 通用扫描函数为 `code/functions/utils/run_multiple_snapshot_temporal_scalability_scan.m`。每个周期数只生成一份时间聚合输入，并由聚合（AG）与逐时（PW）模型共同使用，以保证比较数据一致。
- 时序输入由原 24 个连续小时分块取平均（`q = 24/T`），用于负荷与风电可用出力等时序量；典型日权重、风电场景概率及场景数量保持不变。机组最小开停机时间按新的时段长度换算，爬坡率仍按 MW/h 解释。
- AG 调用 `solve_multiple_snapshot_planning`，PW 调用 `solve_multiple_snapshot_planning_periodwise`。PW 在每个典型日和时段建立安全约束，不使用 AG 的同步机状态并集/交集安全网络。
- IV-D 以默认参数源中的 Gurobi 配置运行 AG 与 PW；除时限外，两者沿用同一组求解配置。PW 的 Stage-1 与 Stage-2 `TimeLimit` 分别设为对应 AG 时限的 5 倍。
- 运行环境需要 MATLAB R2024b、YALMIP、MATPOWER（提供 `case30`）以及已安装并获许可的 Gurobi MATLAB API。入口脚本会优先使用 MATLAB 已有路径；否则读取 `MATPOWER_PATH`、`YALMIP_PATH`、`GUROBI_MATLAB_PATH` 或 `GUROBI_HOME` 环境变量添加依赖路径。使用相同 MATLAB、YALMIP、MATPOWER、Gurobi 版本及数据和求解配置可复现相同模型；运行时间会受硬件影响。
- RTS-GMLC D=4、K=4 的时序 `.mat` 输入由参数生成脚本从项目相对路径读取；MAT 文件按仓库忽略规则不随 Git 提交，运行前需在约定路径提供该文件。
- 扫描输入、分阶段结果和汇总表写入 `results/multiple_snapshot_temporal_scalability_<timestamp>/`；结果目录由 Git 忽略。汇总表每行对应一个 `(Period_Count, Formulation)` 组合。
- 历史 `T=3` 的 AG/PW 配对计算曾达到各自停止目标并通过逐时安全复核；这只是旧版部分扫描验证，不能作为新版模型的验证结果。


## 历史更新记录：设备级模型与参数维护

以下内容记录迁移前的设备级模型和参数维护工作，不构成新版论文的算例参数基准：

- 设备、网络、经济、安全及求解参数按算例文档统一设置；
- 有明确文献或数据来源的参数沿用相应依据，缺少唯一工程定值或需要检验稳健性的参数明确作为灵敏度分析参数，不再以无来源的默认值代替；
- 典型日权重、24 h 负荷曲线、逐典型日风电场景及场景概率直接读取 `data/RTS-GMLC/processed/rts_gmlc_v0.2.3_fixed_extreme_medoids/run_20260822_162606/` 中的实际结果；
- 当前默认规模为 4 个典型日、每个典型日 4 个风电场景、每个典型日 24 个 1 h 时段；
- 默认 RTS-GMLC D=4、K=4 时序输入文件随版本提供，数据来源和处理版本见 `data/RTS-GMLC/README.md` 及该结果目录的 `csv/source_manifest.csv`。
- 参数维护入口仍为 `data/params/generate_multiple_snapshot_default_params.m`，运行时 JSON 由该脚本生成，二者应保持同步。
- 设备级 GFL-WG 的 LVRT 参数与系统级 `params.GFL_WG` 参数保持一致，包括额定电流、LVRT 电压阈值、无功电流斜率及附加无功电流上限；
- 系统级 GFM 电气参数由 `generate_multiple_snapshot_default_params.m` 统一维护，设备级模型通过运行时 JSON 恢复设备基准量，避免系统基准和设备基准混用；
- `GFM_Inherited_Parameters.m` 集中管理 GFM 公共参数、控制器整定结果和系统级电气参数，`GFM_Parameters.m` 负责模型工作区映射、派生量计算和一致性检查；
- GFM 模型进一步完善了可编程三相电源、PCC 耦合接口、虚拟阻抗限流状态机及启动/恢复工况验证，并保留参数来源追溯信息。

用于代表日选择、极端日保留和储能成本参数核查的参考文献保存在 `docs/05_算例参数/`。新版 Section IV 参数待确认；历史参数需结合研究对象重新核实。

## 设备级 GFL/GFM Simulink 模型

本项目同时维护构网型变流器（GFM）与跟网型变流器（GFL）的设备级 Simulink 模型。设备级脚本已按用途分类，脚本调用应使用下列新路径。

### 设备脚本目录

```text
code/scripts/equipment/
  GFL/
    Find_CgSCR.m
    GFL_Current_Loop_PI_Calculation.m
    GFL_Parameters.m
  GFM/
    GFM_Current_Loop_PI_Calculation.m
    GFM_Parameters.m
    GFM_Voltage_Loop_PI_Calculation.m
  Others/
    Generator_Parameters.m
    Invert_Generator_Parameters.m
  for_report/
    report_04/
      Report04_Section5_3_Case_Study.m
    report_05/
      GFM_VI_Port_Characteristic_Validation.m
      GFM_VI_State_Validation.m
```

### GFM 模型入口

- 模型：`simulink/models/Grid_Forming_Inverters.slx`
- 参数脚本：`code/scripts/equipment/GFM/GFM_Parameters.m`
- 电流环整定：`code/scripts/equipment/GFM/GFM_Current_Loop_PI_Calculation.m`
- 电压环整定：`code/scripts/equipment/GFM/GFM_Voltage_Loop_PI_Calculation.m`
- 模型启动回调会根据模型文件位置定位项目根目录，不依赖 MATLAB 当前工作目录。
- GFM 参数脚本独立定义基础参数、GFM 电流环、电压环、下垂控制和虚拟阻抗参数，不动态调用 GFL 参数脚本。

GFM 控制链以 PCC 侧 P/Q 测量、P-f/Q-E 下垂控制、`vMid` 电压外环和 `i1` 电流内环为基础。`Future_Extensions_Hook` 预留可旁路的虚拟阻抗限流接口；旁路时应保持下垂参考电压不变。

### 运行与验证

在 MATLAB 中可使用以下方式加载 GFM 参数：

```matlab
Project_Root = 'D:\Project_With_Codex\Project_2';
addpath(fullfile(Project_Root, 'code', 'functions', 'equipment'));
run(fullfile(Project_Root, 'code', 'scripts', 'equipment', ...
    'GFM', 'GFM_Parameters.m'));
```

GFM 模型的参数加载和一致性校验入口为：

```matlab
addpath(fullfile(Project_Root, 'code', 'functions', 'equipment'));
run(fullfile(Project_Root, 'code', 'scripts', 'equipment', ...
    'GFM', 'GFM_Parameters.m'));
```

`GFM_Parameters.m` 会调用 `GFM_Inherited_Parameters.m`，读取系统级运行时 JSON，并将系统基准电气参数换算为设备基准量后提供给模型。脚本同时检查基准量、LCL 参数、控制器增益、下垂限幅、PCC 接口和虚拟阻抗参数之间的一致性。

GFM 模型入口为 `simulink/models/Grid_Forming_Inverters.slx`；虚拟阻抗端口特性和状态切换验证入口分别位于 `code/scripts/equipment/for_report/report_05/`。模型回调会根据模型文件位置定位项目根目录，不依赖 MATLAB 当前工作目录。

本项目研究高比例跟网型风电（GFL-WG）接入条件下，构网型储能（GFM-ES）的选址、定容与运行协同优化。新版模型联合考虑风电可用出力场景、同步机启停、GFM-ES 模块投建与储能运行、系统运行成本、SCC 上限和经典 SCR 下限。

## 当前进度

默认模型采用考虑 GFL-WG 可用功率不确定性的场景随机多时段规划。新版实现包括：

- GFM-ES 模块投建变量跨典型日、风电场景和时段共享；UC 在同一典型日内跨风电场景共享，出力与网络运行量按场景和时段决策；
- 安全网络按投建决策重构，采用无损电抗网络；故障节点 GFM-ES 虚拟阻抗修正、远端 GFL-WG 三段 LVRT 无功电流和非故障节点残压均进入 SCC 计算；
- SCC 使用逐时 UC 并集状态的残压保守上界，SCR 使用交集状态下重构的 GFL 节点电抗列；不再使用旧版配置枚举、`lambda_c`、UC 状态枚举或旧 SCC 分步上界；
- 式（29）源支撑约束用于日内交集安全网络，式（30）用于故障母线移除后的每个逐时连通分量；投建的 GFM-ES 在充电、放电和零有功时均提供构网支撑；
- 标准 UC、DC 潮流、逐场景爬坡、最小开停机时间、循环储能能量及发电成本分段透视割沿用已有实现；典型日之间独立，日内 UC 和 SOC 按循环边界衔接。

当前已增加GFL的LVRT与限流环节，并完成相应的Simulink仿真组织：

- `Grid_Following_Inverters_LVRT.slx`支持自动电流参考和手动电流参考两种模式；
- 手动参考电流仍经过LVRT和无功优先限流环节，不绕过故障穿越控制；
- 参数脚本为 `code/scripts/equipment/GFL/GFL_Parameters.m`，默认手动参考由 `Manual_Current_Ref`、`Id_ref_manual` 和 `Iq_ref_manual` 控制；
- 报告图5-2扫描脚本为 `code/scripts/figure/for_report/report_04/plot_fig_05_02.m`，输出位于 `figs/for_report/`；
- Simulink模型统一位于 `simulink/models/`，缓存和代码生成文件统一位于 `simulink/artifacts/`；
- 模型 `InitFcn` 已自动配置Simulink生成目录，手动运行模型时不再依赖当前工作目录。

安全状态仅在典型日内跨时段聚合，不随风电场景复制。UC 状态并集/交集由逐时二进制变量及线性约束直接构造；二进制—连续变量乘积采用有效界下的精确 McCormick 线性化，LVRT 三段响应采用精确 MILP 表达。

## 历史参数与时序数据说明

以下数据记录来自迁移前的算例准备，不构成新版 Section IV 的参数确认：

- 参数源位于 `data/params/generate_multiple_snapshot_default_params.m`，生成 JSON 快照 `data/params/multiple_snapshot_default_params.json`；主入口每次运行都会重新生成该快照。
- 仓库中的 RTS-GMLC 典型日和风电场景数据来自 `data/RTS-GMLC/processed/`，可复用原有数据读取和场景概率处理流程。
- 现有参数源中的模块位置、额定容量、成本、LVRT、电抗、SCC/SCR 限值及 UC 参数仍是历史算例设置。运行新版模型前，须由用户按新版算例确认或替换这些输入；本项目不把历史结果作为新版正确答案。

## 运行入口

场景随机多时段模型的主入口为：

```text
code/scripts/system/run_multiple_snapshot_planning.m
```

对应的参数源与生成后的JSON文件为：

```text
data/params/generate_multiple_snapshot_default_params.m
data/params/multiple_snapshot_default_params.json
```

长时间求解可使用：

```text
code/scripts/system/start_multiple_snapshot_planning_longrun.m
```

在 MATLAB 中配置依赖并启动主脚本：

```matlab
Project_Root = 'D:\Project_With_Codex\Project_2';
addpath(genpath(fullfile(Project_Root, 'code')));
clear Parameter_File % 清除后使用默认JSON；也可在此设置为经确认的JSON路径。
run(fullfile(Project_Root, 'code', 'scripts', 'system', ...
    'run_multiple_snapshot_planning.m'));
```

新版 Section IV 参数需先确认。主脚本会求解完整算例；小规模测试入口见迁移说明。

多时段主脚本按当前单阶段或两阶段配置求解算例。未提供 `Parameter_File` 时会先执行参数生成脚本；提供该变量时则直接使用指定 JSON，不会覆盖它。代码保留典型日维度映射和历史结果热启动能力。维护默认参数时应优先修改参数源 `.m` 文件，避免直接修改随后会被覆盖的JSON文件。

脚本运行会调用 `mailTome` 发送结束通知；若当前 MATLAB 环境未配置该函数，规划结果仍会在求解完成后保存，但通知步骤可能报错。新版模型仅使用 Gurobi 作为 MILP 求解器。

未指定 `Parameter_File` 时，参数生成脚本依赖上述 RTS-GMLC 运行目录中的 `rts_gmlc_typical_days_and_wind_scenarios_20260822_162606.mat`。仓库通过 `*.mat` 规则忽略 MAT 文件，因此该 16.3 MiB 时序源文件不随代码提交；运行前需在约定的相对路径准备该文件。生成后的 JSON 参数快照纳入版本控制。

## 新版算例参数待确认

新版 Section IV 尚未给出经确认的算例参数。请在采用新版模型形成论文算例前，确认并配置网络基准和线路参数、GFL-WG 接入节点及聚合参数、GFM-ES 候选节点和逐模块参数、LVRT 参数、SCC/SCR 限值、典型日与场景数据及 UC 参数。特别是同一节点的 GFM-ES 模块需满足论文 Section III-C 的相同效率、SOC 和额定时长条件。仓库现有参数值和历史结果不代表新版模型的默认算例或正确答案。

## 2026-09 Result 输出精简与逐时安全后验复算

新版结果保留聚合安全指标，并提供基于最终规划决策的逐时后验安全指标：

- `Result.SCC_1` 保留为典型日同步机并集工况下的聚合 SCC 保守上界；它不代表实际逐时 SCC；
- `Result.SCR` 保留为典型日同步机交集工况下的聚合经典 SCR 下界；它不代表实际逐时 SCR；
- 新增 `Result.SCC_TimeResolved`，概念维度为 `[period, typical_day, scc_security_node]`，单位为 kA；
- 新增 `Result.SCR_TimeResolved`，概念维度为 `[period, typical_day, gfl_node]`，为无量纲经典 SCR；
- 逐时后验使用最终 GFM-ES 投建状态和实际 `u_G(generator, typical_day, period)`，独立于 SCC/SCR 约束辅助变量；
- 逐时 SCC/SCR 的原始节点映射记录在 `Result.SafetyNetwork`、`Result.SCC_Definition` 和 `Result.SCR_Definition` 中；
- `Result.SecurityValidation` 记录聚合 SCC 上界与逐时 SCC 最大值、聚合 SCR 下界与逐时 SCR 最小值的数值容差、最大违反量及位置。

新版结果不含配置枚举变量 `lambda_c` 或 UC 状态枚举字段。旧版结果字段仅适用于 `ModelVersion='legacy'`。保存的 `Result.solve_time` 是进入单次求解至结果提取和逐时后处理完成的墙钟时间；`Result.Diagnostics.solvertime` 是求解器内部时间，`yalmiptime` 是 YALMIP `optimize` 调用开销。

新版安全网络与约束分别由 `prepare_converter_security_network.m`、`add_converter_security_constraints.m` 和 `add_lvrt_segment_constraints.m` 实现；`calculate_converter_security_state.m` 与 `calculate_converter_security_metrics.m` 用于逐时后验计算和聚合保守性检查。旧版安全约束函数保留在代码库中，仅由 legacy 路径使用。

## 核心文件

```text
code/functions/optimization/solve_multiple_snapshot_planning.m
code/functions/optimization/build_multiple_snapshot_planning_model.m
code/functions/security/add_converter_security_constraints.m
code/functions/security/add_lvrt_segment_constraints.m
code/functions/network/prepare_converter_security_network.m
code/functions/security/calculate_converter_security_state.m
code/functions/security/calculate_converter_security_metrics.m
code/functions/io/load_multiple_snapshot_case.m
code/functions/io/package_multiple_snapshot_result.m
code/functions/equipment/configure_simulink_file_generation.m
code/functions/equipment/configure_simulink_file_generation_from_model.m
```

新版主模型在每个典型日内按同步机状态并集和交集分别构造 SCC、SCR 安全约束。两类聚合安全网络均不随风电场景复制；逐时 SCC/SCR 在求解完成后按实际 UC 状态重构，不把聚合指标填充到逐时数组。

## 结果与复核

求解结果默认写入 `results/`。该目录及求解器日志、MATLAB结果文件均不纳入Git版本控制。建议至少检查：

- `Diagnostics.problem`、最优间隙和是否存在可行整数解；
- `u_GFM_Module`、`u_SG`、`u_SG_Start` 与 `u_SG_Stop`；
- 场景名称、概率及 `[元件,典型日,场景,时段]` 运行结果维度；
- 各场景节点功率平衡、线路限额和机组出力边界；
- 各场景GFM-ES充放电互斥、SOC范围及典型日末SOC；
- GFL-WG场景可用出力、额定功率、实际出力和弃风功率之间的关系；
- `SCC_1` 与逐时 `SCC_TimeResolved` 的安全裕度及聚合保守性；
- 聚合 `SCR` 与逐时 `SCR_TimeResolved` 的安全裕度及聚合保守性；
- 保存的聚合阻抗矩阵与最终整数状态直接重构结果是否一致；
- `solve_time`、`Diagnostics.solvertime` 和 `Diagnostics.yalmiptime` 的计时含义。

当前显式场景没有自然基准场景。需要单场景复核时，应明确选用的场景编号并将其概率设为 1，再使用确定性退化检查函数验证输入轨迹、运行权重及结果；不应把任意场景静默解释为基准场景。

模型中的同步机二次成本采用分段透视割近似，因此报告成本与原始二次成本可能存在小幅误差。当前已验证算例中的误差约为0.21%。

## 项目结构

```text
code/
  scripts/system/      主运行脚本、路径解析与后台启动入口
  scripts/equipment/   设备级仿真与参数计算脚本
  scripts/figure/      调试图和报告图生成脚本
  functions/equipment/ Simulink设备仿真与生成目录配置函数
  functions/           数据加载、网络构建、优化、安全约束与结果输出
simulink/
  models/              Simulink模型文件
  artifacts/           Simulink缓存、slprj和代码生成文件（Git忽略）
data/
  params/              默认参数源脚本及生成后的JSON参数文件
docs/                  模型文档、论文材料与环境说明
results/               本地优化结果（Git忽略）
logs/                  本地运行日志（Git忽略）
```

`docs/`中的PDF和Word材料默认不提交。Git不会保存空目录；如需长期保留文档分类目录，应加入可跟踪的说明文件或 `.gitkeep`。

## 环境依赖

- MATLAB R2024b
- MATPOWER（提供 `case30`；当前本地验证版本为 7.1）
- YALMIP（提供 `optimize`；跨设备运行请使用同一版本）
- Gurobi MATLAB API 与有效许可证（当前本地 IV-D 验证使用 Gurobi 12.0.3）

IV-D 入口优先使用已在 MATLAB 路径中的依赖。若依赖未加入路径，可在启动 MATLAB 前设置 `MATPOWER_PATH`、`YALMIP_PATH` 和 `GUROBI_MATLAB_PATH`；也可设置 `GUROBI_HOME` 指向 Gurobi 安装目录。扫描所需的 RTS-GMLC `.mat` 输入已随仓库提供。硬件、并行线程和求解器版本会影响运行时间以及多线程求解路径；代码固定了输入生成规则和模型求解参数，但不承诺跨设备逐位一致的运行时间或解向量。

MATLAB后台启动与环境配置说明见：

```text
docs/matlab_environment_note.md
```

## 后续工作

- 继续补充可获得的工程数据与文献依据，并校准 GFM-ES 功率、能量、成本与故障电流参数；
- 对缺少唯一工程定值或可能显著影响结果的线路强度、短路电流上限、SCR 下限、GFM-ES 成本及设备故障电流参数开展灵敏度分析；
- 比较安全工况交并集聚合与逐时安全约束的保守性；
- 引入构网容量要求或辅助服务价值；
- 接入外部生成或缩减后的风电场景，并评估场景数量对求解规模的影响；
- 在场景随机优化基础上进一步研究分布鲁棒配置模型。

## 2026-07 当前进度与常规备份

当前项目已完成以下阶段性工作：

- 建立了 IEEE-30 系统、多典型日、多风电场景的模块化 GFM-ES 配置优化模型；
- 完成了参数审计，报告见 `docs/parameter_audit_report.md`；
- 去除了同步机发电成本中的常数项；
- 将同步机启机成本设置为 5% 额定出力成本的 1.0 倍，将关停成本设置为该成本的 0.25 倍；
- 保留了同步机 UC、GFL-WG 弃风成本、GFM-ES 投建成本与储能运行约束；
- 已形成仅考虑经济性约束的算例结果：`results/multiple_snapshot_planning_result_20260717_103238.mat`；
- 已根据该结果生成同步机 UC 状态图，图表位于 `figs/economic_20260717_103238/02_operation/`；其中 D01 典型日的同步机启停次数最多，共 4 次启动和 4 次关停；
- 上述经济性结果由历史上的纯经济性约束版本生成；当前求解函数已按论文第2.1节至第2.5节装配包含安全约束的完整集合。经济性结果中的安全相关后处理不应作为安全性结论。

本次提交用于项目当前状态的常规备份。后续工作包括：完善经济性算例专用后处理、补充安全约束算例对照、开展参数灵敏度分析，并进一步核查 GFM-ES 成本和故障电流参数的工程依据。
