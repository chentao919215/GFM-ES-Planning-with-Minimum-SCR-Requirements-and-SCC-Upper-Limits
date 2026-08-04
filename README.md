# GFM-ES安全配置优化项目

## 最近更新：设备级 GFL/GFM Simulink 模型

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
  for_report/04/
    Report04_Section5_3_Case_Study.m
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

GFM 模型的辅助构建与验证入口为：

```matlab
build_gfm_model;
report = validate_gfm_model;
```

当前参数脚本已能够从分类后的新目录独立运行，模型回调中的 GFM 与混合电源参数路径也已同步更新。现阶段 `validate_gfm_model` 仍会在模型结构检查阶段报告缺少预期模块 `Grid_Forming_Inverters/GFM_1/GFM_Control/PQ_Measurement`；因此在该模块路径与验证脚本一致之前，不应将 GFM 模型标记为已完成编译和验收。

本项目研究高比例跟网型风电（GFL-WG）接入条件下，构网型储能（GFM-ES）的选址、定容与运行协同优化。当前模型在统一框架中联合考虑风电可用出力不确定性、同步机启停、GFM-ES模块化投建、储能充放电、系统运行成本、短路电流上限与经典短路比（SCR）下限。

## 当前进度

项目当前采用考虑GFL-WG可用出力不确定性的场景随机多时段模块化GFM-ES配置优化模型。当前模型包括：

- 低风、基准和高风完整日内轨迹及逐典型日场景概率；
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

## 2026-08 参数结构与论文模型对齐

本轮更新优化了参数赋值结构，并将项目自有代码与《基于场景随机优化的多时段模块化GFM-ES配置优化模型_ver_2》严格对齐：

- 默认参数继续由 `data/params/generate_multiple_snapshot_default_params.m` 统一生成，并通过 `normalize_multiple_snapshot_conf.m` 形成一致的内部参数结构；
- 项目自有变量及内部结构体字段统一采用大写蛇形命名，多文件中的同一物理量保持一致；
- 清理了能够确认冗余的历史兼容、重复检查和静默回退代码，同时保留输入边界、维度、数值稳定性及求解结果有效性检查；
- 多时段规划函数的约束装配顺序已按论文第2.1节至第2.5节组织为规划、基础潮流、UC、GFM-ES、安全约束和McCormick线性化；
- UC状态仍在同一典型日的不同风电场景之间共享，运行补救变量随场景变化；
- 聚合安全状态、阻抗重构、LVRT、短路电流水平、SCR及其McCormick约束仍仅按典型日建立，不随风电场景复制；
- 配置枚举、不可逆状态剔除、阻抗边界与故障转移系数计算继续作为离线预处理，不作为新的在线优化约束。

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

## 当前默认多时段与场景参数

当前默认算例的主要设置如下：

- 典型日数量为3，普通、低净负荷和高净负荷典型日权重分别为255、55和55天；
- 每个典型日包含低风、基准、高风3条完整轨迹，缩放系数分别为0.8、1.0和1.2；
- 三个风电场景的概率分别为0.25、0.50和0.25；
- 默认场景由原确定性可用出力轨迹统一缩放生成，也支持按 `[节点,典型日,场景,时段]` 接入外部显式场景数据；
- GFM-ES候选节点：9、15和19号节点；
- 每个候选节点配置2个候选模块，全系统最多投建4个模块；
- 每个模块额定功率30 MW、额定能量60 MWh；
- 充电效率和放电效率均为0.9；
- SOC上限、初始值和下限分别为0.9、0.5和0.1；
- 故障电流倍数为3；
- 线路参数比例为 `r=x=1.75、b=4/7`；
- 短路电流上限为12.25 kA，经典SCR下限为3；
- 同步机上、下爬坡速率均为 `0.2Pmax`，最小开、停机时段数均为3；
- 同步机单次启动成本为 `2cG`，单次停机成本为 `0.5cG`；
- 完整算例为D=3、K=3；两阶段求解启用时，第一阶段直接收敛则不再执行第二阶段。

这些参数包含用于模型验证的算例设定，不应直接视为工程设备定值。设备成本、额定容量、故障电流能力及安全阈值应在实际研究中根据数据来源重新标定。

## 核心文件

```text
code/functions/optimization/solve_multiple_snapshot_planning.m
code/functions/security/add_impedance_reconstruction_constraints.m
code/functions/security/add_short_circuit_current_constraints.m
code/functions/security/add_classic_scr_constraints.m
code/functions/network/calculate_impedance_bounds.m
code/functions/io/load_multiple_snapshot_case.m
code/functions/equipment/configure_simulink_file_generation.m
code/functions/equipment/configure_simulink_file_generation_from_model.m
```

多时段主模型在每个典型日内使用同步机逐时状态的并集重构最大短路电流工况，使用状态交集重构最弱SCR工况。两类安全网络均不随风电场景复制。该聚合方式能控制模型规模，但相较逐时重构更保守，后续可进一步研究逐时安全约束或更紧的等价表达。

## 结果与复核

求解结果默认写入 `results/`。该目录及Gurobi日志、MATLAB结果文件均不纳入Git版本控制。建议至少检查：

- `Diagnostics.problem`、最优间隙和是否存在可行整数解；
- `u_GFM_Mod`、`u_G_SCC`与`u_G_SCR`；
- 场景名称、概率及 `[元件,典型日,场景,时段]` 运行结果维度；
- `u_G`、`u_G_Start`与`u_G_Stop`的循环状态转换、爬坡及最小开停机时间；
- 各场景节点功率平衡、线路限额和机组出力边界；
- 各场景GFM-ES充放电互斥、SOC范围及典型日末SOC；
- GFL-WG场景可用出力、额定功率、实际出力和弃风功率之间的关系；
- 最大短路电流和最小SCR的安全裕度；
- 保存的阻抗矩阵与最终整数状态直接求逆结果是否一致。

当仅保留基准场景且概率设为1时，可使用确定性退化检查函数验证输入轨迹、运行权重及结果是否与原确定性模型一致。

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

- 使用工程数据校准GFM-ES功率、能量、成本与故障电流参数；
- 开展线路强度、短路电流上限、SCR下限和GFM-ES成本的敏感性分析；
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
