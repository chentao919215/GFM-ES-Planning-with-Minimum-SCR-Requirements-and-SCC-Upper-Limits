# GFM-ES安全配置优化项目

## 最近更新：设备级与系统级模型的参数对齐及 GFM 模型完善

本轮更新以 `docs/05_算例参数/基于场景随机优化的多时段模块化GFM-ES配置优化模型_ver_2_算例分析.docx` 为主要依据，并以同目录 PDF 版本交叉核对，对默认多时段算例参数进行了系统更新：

- 设备、网络、经济、安全及求解参数按算例文档统一设置；
- 有明确文献或数据来源的参数沿用相应依据，缺少唯一工程定值或需要检验稳健性的参数明确作为灵敏度分析参数，不再以无来源的默认值代替；
- 典型日权重、24 h 负荷曲线、逐典型日风电场景及场景概率直接读取 `data/RTS-GMLC/processed/rts_gmlc_v0.2.3_fixed_extreme_medoids/run_20260822_162606/` 中的实际结果；
- 当前默认规模为 4 个典型日、每个典型日 4 个风电场景、每个典型日 24 个 1 h 时段；
- 参数维护入口仍为 `data/params/generate_multiple_snapshot_default_params.m`，运行时 JSON 由该脚本生成，二者应保持同步。
- 设备级 GFL-WG 的 LVRT 参数与系统级 `params.GFL_WG` 参数保持一致，包括额定电流、LVRT 电压阈值、无功电流斜率及附加无功电流上限；
- 系统级 GFM 电气参数由 `generate_multiple_snapshot_default_params.m` 统一维护，设备级模型通过运行时 JSON 恢复设备基准量，避免系统基准和设备基准混用；
- `GFM_Inherited_Parameters.m` 集中管理 GFM 公共参数、控制器整定结果和系统级电气参数，`GFM_Parameters.m` 负责模型工作区映射、派生量计算和一致性检查；
- GFM 模型进一步完善了可编程三相电源、PCC 耦合接口、虚拟阻抗限流状态机及启动/恢复工况验证，并保留参数来源追溯信息。

用于代表日选择、极端日保留和储能成本参数核查的参考文献保存在 `docs/05_算例参数/`。参数具有文献依据并不意味着其可直接作为工程定值；涉及设备成本、故障电流能力、安全阈值及网络强度的参数，仍应结合研究对象开展灵敏度分析。

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

本项目研究高比例跟网型风电（GFL-WG）接入条件下，构网型储能（GFM-ES）的选址、定容与运行协同优化。当前模型在统一框架中联合考虑风电可用出力不确定性、同步机启停、GFM-ES模块化投建、储能充放电、系统运行成本、短路电流上限与经典短路比（SCR）下限。

## 当前进度

项目当前采用考虑GFL-WG可用出力不确定性的场景随机多时段模块化GFM-ES配置优化模型。当前模型包括：

- 4 个典型日及逐典型日 4 条显式风电场景轨迹与场景概率；
- GFM-ES投建状态与同步机组合状态跨场景共享；
- 同步机出力、GFM-ES充放电与SOC、GFL-WG弃风、节点相角及线路潮流随场景变化；
- 同步机启停动作、典型日首尾循环状态转换、上下爬坡和最小开停机约束；
- GFL-WG额定功率、场景可用出力、实际出力及弃风功率的严格区分；
- GFM-ES模块化投建、按序建设和总模块数上限；
- 各场景内的GFM-ES充放电互斥、效率、SOC上下限、初始SOC与典型日能量闭环；
- 各场景内的DC潮流、节点功率平衡与线路热稳约束；
- 同步机状态并集对应的短路电流上限约束；
- 同步机状态交集对应的经典SCR下限与电压源存在约束；
- 同步机和GFM-ES共同参与的阻抗矩阵重构及二元变量乘积线性化；
- 非故障节点GFL-WG的三段式LVRT触发与增量故障电流反馈，包括零电流段、线性段和饱和段；
- 故障节点GFL-WG饱和限流、故障节点GFM-ES虚拟阻抗限流，以及非故障节点GFM-ES正常运行电抗；
- GFM-ES配置方案集合、配置选择变量、配置状态映射、配置相关故障转移系数上界及不可行阻抗状态排除；
- 按典型日权重、场景概率和时段时长计算的期望运行成本；
- 两阶段Gurobi求解、场景结果打包、热启动映射、诊断输出和确定性退化检查。

当前已增加GFL的LVRT与限流环节，并完成相应的Simulink仿真组织：

- `Grid_Following_Inverters_LVRT.slx`支持自动电流参考和手动电流参考两种模式；
- 手动参考电流仍经过LVRT和无功优先限流环节，不绕过故障穿越控制；
- 参数脚本为 `code/scripts/equipment/GFL/GFL_Parameters.m`，默认手动参考由 `Manual_Current_Ref`、`Id_ref_manual` 和 `Iq_ref_manual` 控制；
- 报告图5-2扫描脚本为 `code/scripts/figure/for_report/report_04/plot_fig_05_02.m`，输出位于 `figs/for_report/`；
- Simulink模型统一位于 `simulink/models/`，缓存和代码生成文件统一位于 `simulink/artifacts/`；
- 模型 `InitFcn` 已自动配置Simulink生成目录，手动运行模型时不再依赖当前工作目录。

多时段优化模型的 ver_2 安全约束额外考虑非故障节点的 LVRT 触发。GFL-WG 故障节点保留饱和限流处理，非故障节点根据残余电压在零电流、线性增量和饱和增量三个区段间切换；同步机交集工况的残余电压方程显式反馈非故障节点GFL-WG增量电流。配置集合和阻抗网络在优化前离线枚举，GFM-ES配置与UC跨场景共享，安全网络和LVRT变量不增加风电场景维度。

安全状态仍仅在各典型日内跨时段聚合：SCC采用同步机状态并集，SCR采用同步机状态交集。安全网络阻抗重构、McCormick辅助变量及阻抗上下界预处理不增加风电场景维度。同步机运行状态、启动动作、停机动作、爬坡过程和最小开停机过程均在各典型日日首与日末之间循环衔接。

## 2026-08 算例参数、时序数据与论文模型对齐

本轮更新优化了参数赋值结构，并将默认算例与《基于场景随机优化的多时段模块化GFM-ES配置优化模型_ver_2》及其算例分析文档对齐：

- 默认参数继续由 `data/params/generate_multiple_snapshot_default_params.m` 统一生成，并通过 `normalize_multiple_snapshot_conf.m` 形成一致的内部参数结构；
- 项目自有变量及内部结构体字段统一采用大写蛇形命名，多文件中的同一物理量保持一致；
- 清理了能够确认冗余的历史兼容、重复检查和静默回退代码，同时保留输入边界、维度、数值稳定性及求解结果有效性检查；
- 多时段规划函数的约束装配顺序已按论文第2.1节至第2.5节组织为规划、基础潮流、UC、GFM-ES、安全约束和McCormick线性化；
- UC状态仍在同一典型日的不同风电场景之间共享，运行补救变量随场景变化；
- 聚合安全状态、阻抗重构、LVRT、短路电流水平、SCR及其McCormick约束仍仅按典型日建立，不随风电场景复制；
- 配置枚举、不可逆状态剔除、阻抗边界与故障转移系数计算继续作为离线预处理，不作为新的在线优化约束。
- 典型日和风电场景不再由固定倍率缩放构造，而是直接读取指定 RTS-GMLC 处理结果中的负荷轨迹、风电轨迹、代表日权重和逐日场景概率；
- 参数分为文献或算例文档直接支撑项，以及需要灵敏度分析验证的算例假设项，后者不解释为唯一工程定值。

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

多时段主脚本运行时会先执行参数生成脚本，随后按当前单阶段或两阶段配置求解完整算例。代码保留典型日维度映射和历史结果热启动能力。维护参数时应优先修改参数源 `.m` 文件，避免直接修改随后会被覆盖的JSON文件。

参数生成脚本依赖上述 RTS-GMLC 运行目录中的 `rts_gmlc_typical_days_and_wind_scenarios_20260822_162606.mat`。仓库通过 `*.mat` 规则忽略 MAT 文件，因此该 16.3 MiB 时序源文件不随代码提交；运行前需在约定的相对路径准备该文件。生成后的 JSON 参数快照纳入版本控制。

## 当前默认多时段与场景参数

当前默认算例的主要设置如下：

- 典型日数量为 4，权重依次为 31、76、88 和 170 天，合计 365 天；
- 每个典型日包含 24 个 1 h 时段和 4 条显式风电场景轨迹，数据规模为 `D=4、K=4、T=24`；
- 四个典型日的场景概率分别为 `[0.2581,0.2258,0.2581,0.2581]`、`[0.0658,0.2763,0.1842,0.4737]`、`[0.6250,0.1705,0.1023,0.1023]` 和 `[0.4882,0.2118,0.1824,0.1176]`；
- 负荷曲线、日前风电曲线、风电场景和场景概率来自指定 RTS-GMLC 处理结果，风电场景生成模式为 `explicit`；
- 实际场景集合不存在自然的“基准场景”，因此 `Base_Index=NaN`；单场景绘图或导出时必须显式指定 `Scenario_Index=1..4`，期望量仍按逐典型日场景概率计算；
- GFL-WG 仅建于 11 号节点，单场额定功率 60 MW，弃风成本为 30（模型成本单位）/MWh；
- GFM-ES 候选节点为 9、15 和 19 号节点；每个候选节点最多配置 2 个模块，全系统最多投建 4 个模块；
- 每个 GFM-ES 模块额定功率 30 MW、额定能量 60 MWh，充放电效率均为 0.9，SOC 上限、初始值和下限分别为 0.9、0.5 和 0.1；
- 同步机与 GFM-ES 的设备基准电抗均按 0.10 p.u. 输入后换算至系统基准，GFM-ES 故障后电流倍数为 1.5；
- 线路串联电纳按 `4/7` 缩放（等价于 `x=7/4`），`r` 与 `b` 保持原始 case30 数据；安全网络另按无损感性近似忽略 `r` 与 `b`；
- 短路电流上限为 12.25 kA（系统基准下 28.64 p.u.），经典 SCR 下限为 3；GFM-ES 年固定成本采用 12390 $/(MW·year) 与 37120 $/(MWh·year)，各自均已包含年化投资和固定运维且只计一次；
- 六台同步机最小出力为 `[20,20,10,11,6,8]` MW，上爬坡率为 `[20,20,10,11,6,8]` MW/h，下爬坡率为 `[24,24,18,20,12,14]` MW/h；
- 六台同步机最小开机时段为 `[4,4,4,4,2,4]`，最小停机时段为 `[4,4,2,2,2,2]`；启动成本按满载发电成本的 0.5 倍计算，停机成本按 0.05 倍计算；
- 两阶段求解的第一阶段时限为 300 s、目标间隙为 30%，第二阶段时限为 1800 s、目标间隙为 0.5%。

以上设置用于复现指定算例。来源明确的参数按算例文档或配套文献设置；网络强度、设备成本、额定容量、故障电流能力、安全阈值等缺少唯一通用取值或可能显著影响规划结果的参数，应在研究中列为灵敏度分析对象。

## 2026-09 Result 输出精简与逐时安全后验复算

本轮结果整理与论文中的聚合安全定义保持一致，并补充了基于最终规划决策的逐时后验安全指标：

- `Result.SCC_1` 保留为典型日同步机并集工况下的聚合 SCC 保守上界；它不代表实际逐时 SCC；
- `Result.SCR` 保留为典型日同步机交集工况下的聚合经典 SCR 下界；它不代表实际逐时 SCR；
- 新增 `Result.SCC_TimeResolved`，概念维度为 `[period, typical_day, scc_security_node]`，单位为 kA；
- 新增 `Result.SCR_TimeResolved`，概念维度为 `[period, typical_day, gfl_node]`，为无量纲经典 SCR；
- 逐时后验使用最终 GFM-ES 投建状态和实际 `u_G(generator, typical_day, period)`，独立于 SCC/SCR 约束辅助变量；
- 逐时 SCC/SCR 的原始节点映射记录在 `Result.SafetyNetwork`、`Result.SCC_Definition` 和 `Result.SCR_Definition` 中；
- `Result.SecurityValidation` 记录聚合 SCC 上界与逐时 SCC 最大值、聚合 SCR 下界与逐时 SCR 最小值的数值容差、最大违反量及位置。

Result 中已删除确认重复或仅用于模型构建的缓存字段，包括 `SCC_0`、`SCC_2`、顶层 GFM 配置状态、顶层 `u_GFL`、顶层风电场景描述和 `SolveStage`，以及离线状态枚举、LVRT 中间变量和故障转移缓存。对应权威配置保留在 `Result.CONF` 或 `Result.Diagnostics.ConfigurationAllowed` 中；`lambda_c` 保留最终配置选择结果。保存的 `Result.solve_time` 是从进入单次求解到完成结果提取和逐时后处理的墙钟时间，不含打包与文件保存；`Result.Diagnostics.solvertime` 是求解器内部时间，`yalmiptime` 是 `optimize` 调用开销。

固定状态安全网络重构位于 `code/functions/network/build_fixed_state_safety_network.m`；SCC/SCR 指标计算和聚合保守性检查位于 `code/functions/security/`。SCC 后验继续沿用无损安全网络、故障节点局部虚拟阻抗和三段 LVRT 增量电流逻辑；SCR 后验直接复用 `calculate_classic_scr.m`，不另设 SCR 定义。

## 核心文件

```text
code/functions/optimization/solve_multiple_snapshot_planning.m
code/functions/security/add_impedance_reconstruction_constraints.m
code/functions/security/add_short_circuit_current_constraints.m
code/functions/security/add_classic_scr_constraints.m
code/functions/network/calculate_impedance_bounds.m
code/functions/network/build_fixed_state_safety_network.m
code/functions/security/calculate_fixed_state_scc.m
code/functions/security/calculate_fixed_state_scr.m
code/functions/security/calculate_time_resolved_security_metrics.m
code/functions/security/check_aggregated_security_conservatism.m
code/functions/io/load_multiple_snapshot_case.m
code/functions/io/package_multiple_snapshot_result.m
code/functions/equipment/configure_simulink_file_generation.m
code/functions/equipment/configure_simulink_file_generation_from_model.m
```

多时段主模型在每个典型日内使用同步机逐时状态的并集重构最大短路电流工况，使用状态交集重构最弱 SCR 工况。两类聚合安全网络均不随风电场景复制；逐时 SCC/SCR 仅在求解完成后按实际 SG 状态重构，不把聚合结果填充到逐时数组。该聚合方式能控制模型规模，但相较逐时安全约束更保守。

## 结果与复核

求解结果默认写入 `results/`。该目录及Gurobi日志、MATLAB结果文件均不纳入Git版本控制。建议至少检查：

- `Diagnostics.problem`、最优间隙和是否存在可行整数解；
- `u_GFM_Mod`、`lambda_c`、`u_G`、`u_G_Start` 与 `u_G_Stop`；
- 场景名称、概率及 `[元件,典型日,场景,时段]` 运行结果维度；
- 各场景节点功率平衡、线路限额和机组出力边界；
- 各场景GFM-ES充放电互斥、SOC范围及典型日末SOC；
- GFL-WG场景可用出力、额定功率、实际出力和弃风功率之间的关系；
- `SCC_1` 与逐时 `SCC_TimeResolved` 的安全裕度及聚合保守性；
- 聚合 `SCR` 与逐时 `SCR_TimeResolved` 的安全裕度及聚合保守性；
- 保存的聚合阻抗矩阵与最终整数状态直接重构结果是否一致；
- `solve_time`、`Diagnostics.solvertime` 和 `Diagnostics.yalmiptime` 的计时含义。

当前显式历史场景没有自然基准场景。需要单场景复核时，应明确选用的场景编号并将其概率设为 1，再使用确定性退化检查函数验证输入轨迹、运行权重及结果；不应把任意历史场景静默解释为基准场景。

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

- MATLAB
- MATPOWER
- YALMIP
- Gurobi

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
