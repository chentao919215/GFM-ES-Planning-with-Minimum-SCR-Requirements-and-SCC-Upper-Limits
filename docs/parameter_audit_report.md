# 基于场景随机优化的多时段模块化 GFM-ES 配置优化模型

## 参数审计报告

审计范围：`code/`、`data/params/` 中实际用于案例加载、网络构建、安全约束、优化建模和求解器配置的参数。审计为只读；本文件是本次唯一新增文件。参数表中的“派生参数”仍保留，是为了明确单位换算、缩放和公式计算链路；决策变量、结果变量和普通矩阵中间量不作为非派生参数重复列出。

默认算例存在两套口径：单时刻文件 `single_snapshot_default_params.json` 与多时段随机文件 `multiple_snapshot_default_params.json`。以下凡标注“单时刻/多时段”的取值，均以对应 JSON 当前内容为准；多时段随机模型是本项目目标模型。

## 1. 参数总表

|代码变量名|所在文件与行号|数学符号或模型含义|当前取值|单位|原始/派生|参数类别|当前来源|是否存在单位换算|是否可能显著影响优化结果|建议后续处理|
|---|---|---|---|---|---|---|---|---|---|---|
|`mpc.bus(:,3:4)`|`data/params/multiple_snapshot_default_params.json:5-455`；加载：`code/functions/io/load_multiple_snapshot_case.m:6`|IEEE-30 各节点有功/无功基准负荷 `P_D,Q_D`|P 负荷：0；21.7,2.4,7.6,0,0,22.8,30,0,5.8,0,11.2,0,6.2,8.2,3.5,9,3.2,9.5,2.2,17.5,0,3.2,8.7,0,3.5,0,0,2.4,10.6 MW（节点 1–30）；Q：0；12.7,1.2,1.6,0,0,10.9,30,0,2,0,7.5,0,1.6,2.5,1.8,5.8,0.9,3.4,0.7,11.2,0,1.6,6.7,0,2.3,0,0,0.9,1.9 MVAr|MW/MVAr|原始|系统参数|MATPOWER case30，写入 JSON|否（后续乘负荷倍率）|是|保留；论文明确基准负荷与倍率来源|
|`mpc.gen(:,1,3,4,9,10)`|`data/params/multiple_snapshot_default_params.json:457-596`|同步机接入节点、`Qmax/Qmin/Pmax/Pmin`|节点 `[1,2,22,27,23,13]`；Pmax `[80,80,50,55,30,40]` MW；Qmax `[150,60,62.5,48.7,40,44.7]` MVAr；Pmin 原始为 0，模型另设显式最小有功|MW/MVAr|原始+派生 Pmin|系统参数|MATPOWER case30；Pmin 由参数脚本计算|Pmin 采用 `0.05*Pmax`|是|保留；说明同步机数量、容量和 Pmin 口径|
|`mpc.branch(:,1:7)`|`data/params/multiple_snapshot_default_params.json:597-1269`|线路端点、串联 `r,x`、充电电纳 `b`、容量 `RATE_A/B/C`|IEEE-30 的 41 条线路；`RATE_A` 为 `[130,130,65,130,130,65,90,70,130,32,65,32,65,65,32,65,32,32,32,16,16,16,16,32,32,32,32,32,16,16,16,16,16,65,16,16,16,32,32,32]` MVA；完整端点和 `r/x/b` 见 JSON 行段|标幺/MVA|原始|系统参数|MATPOWER case30|是：`r,x,b` 被 BranchScale 修正|是|需要文献/算例依据；尤其核查线路参数修正|
|`mpc.gencost(:,5:7)`|`data/params/multiple_snapshot_default_params.json:1214-1269`；读取：`code/functions/network/build_multiple_snapshot_network.m:23-25`|同步机二次、一次、常数成本系数 `a,b,c`|`(0.02,2,0),(0.0175,1.75,0),(0.0625,1,0),(0.00834,3.25,0),(0.025,3,0),(0.025,3,0)`|成本/MW²、成本/MW、成本|原始；运行时常数项强制为 0|系统参数|MATPOWER case30；`load_*_snapshot_case.m` 将 `gencost(:,7)` 置零|否|是|需要文献支撑；明确成本货币/时间口径|
|`base_MVA`|生成：`data/params/generate_multiple_snapshot_default_params.m:10-15`；JSON：`multiple_snapshot_default_params.json:1271`|系统基准容量 `S_base`|100|MVA|原始|系统参数|MATPOWER case30|否|是|保留|
|`base_kV, base_kA, base_O`|生成：`data/params/generate_multiple_snapshot_default_params.m:13-15`；JSON：`1272-1274`|基准电压、电流、阻抗|135；0.4276668661；182.25|kV、kA、Ω|派生|系统参数|由 `base_MVA` 与 `mpc.bus(1,10)` 公式计算|是|是|人工确认 `base_kV=135` 是否与该 case 的电压等级一致|
|`BranchScale.r/x/b`|`multiple_snapshot_default_params.json:3992-3995`；生成：`generate_multiple_snapshot_default_params.m:42-45`|线路参数修正系数|`r=1.75,x=1.75,b=4/7≈0.5714286`；单时刻为 `2,2,0.5`|无量纲|原始|系统参数|人为设定|否（作用于标幺值）|是|需要文献支撑/灵敏度分析|
|`Gen_Pmin_MW`|`multiple_snapshot_default_params.json:3999-4005`；生成：`generate_multiple_snapshot_default_params.m:53-54`|同步机最小稳定有功出力|`[4,4,2.5,2.75,1.5,2]`|MW|派生|UC参数|由 `0.05*mpc.gen(:,9)`|否|是|需要文献支撑；确认 5% 是否适用于全部机组|
|`Xd_Gen`|`multiple_snapshot_default_params.json:3997`；生成：`generate_multiple_snapshot_default_params.m:48-50`|同步机次暂态/等效短路电抗 `X''_d`（代码注释称暂态电抗）|0.04|标幺（系统基准）|原始|安全参数|人为设定|需确认设备基准到系统基准换算|是|需要文献支撑；统一“次暂态/暂态”术语|
|`GenCostLoading`|`multiple_snapshot_default_params.json:3998`；生成：`generate_multiple_snapshot_default_params.m:49-51`|用于生成固定成本常数项的负荷/出力比例|0.05|无量纲|原始|系统参数|人为设定|否|是|需要文献支撑/灵敏度分析|
|`GenCostBreakpoints`|`multiple_snapshot_default_params.json:4007-4018`；生成：`generate_multiple_snapshot_default_params.m:56-57`|归一化发电出力分段切点|`0:0.1:1`，11 个切点|无量纲|原始|数值参数|人为设定|否|中等|保留并做线性化误差验证|
|`UC.RampUp/Down_Rate_MW_per_Hour`|`multiple_snapshot_default_params.json:4021-4035`；生成：`generate_multiple_snapshot_default_params.m:65-66`|同步机上下爬坡率|上下相同：`[16,16,10,11,6,8]`|MW/h|派生|UC参数|`0.2*Pmax`|时间步内乘 `PeriodDurations_Hours`|是|需要文献支撑/灵敏度分析|
|`UC.MinUp/Down_Periods`|`multiple_snapshot_default_params.json:4037-4051`；生成：`generate_multiple_snapshot_default_params.m:67-68`|最小开机/停机时段|均为 `[3,3,3,3,3,3]`|时段|原始|UC参数|人为设定|是：每时段 2 h，实际约 6 h|是|需要文献支撑；论文说明循环窗口含义|
|`UC.Startup/Shutdown_Cost`|`multiple_snapshot_default_params.json:4053-4067`；生成：`generate_multiple_snapshot_default_params.m:62-70`|单次启机/关停成本|启机 `[8.32,7.28,2.890625,9.00057125,4.55625,6.1]`；关停 `[2.08,1.82,0.72265625,2.2501428125,1.1390625,1.525]`|成本/次|派生|UC参数|由 5% Pmax 处成本分别乘 1.0/0.25|否|是|需要文献支撑；核查成本货币和时间口径|
|UC 初始状态|模型搜索：`code/functions/optimization/solve_multiple_snapshot_planning.m:184-196,277-290`；参数文件无对应字段|日首开机状态、已持续开停机时长|未发现显式输入；状态由时段变量决定，按典型日首末循环衔接|—|缺失/模型规则|UC参数|未配置|不适用|是|需要人工确认；论文必须明确“无外部初始状态、循环日”假设|
|`TypicalDayCount/PeriodCount`|`multiple_snapshot_default_params.json:1275-1277`；生成：`generate_multiple_snapshot_default_params.m:20-22`|典型日数量与时段数量|3、12|日/时段|原始|GFL-WG参数|人为设定|否|是|保留；说明 12×2 h=24 h|
|`TypicalDayWeights_Days`|`multiple_snapshot_default_params.json:1278-1282`|典型日代表天数权重|`[255,55,55]`，合计 365|天|原始|GFL-WG参数|人为设定|否|是|需要文献/数据支撑；敏感性分析|
|`PeriodDurations_Hours`|`multiple_snapshot_default_params.json:1297-1309`|时段持续时间|12 个时段均 2|h|原始|GFL-WG参数|人为设定|否|是|保留；说明储能递推和爬坡换算|
|`Factor`|`multiple_snapshot_default_params.json:1283-1295`；生成：`generate_multiple_snapshot_default_params.m:25-28`|典型日 GFL 可用出力/负荷倍率|`[[1,1],[1.1,0.9],[0.9,1.0]]`|无量纲|原始|GFL-WG参数|人为设定|否|是|需要数据依据/灵敏度分析|
|`LoadFactor`、`Load_P_MW`|`multiple_snapshot_default_params.json:1333-1345,1347-2668`；生成：`generate_multiple_snapshot_default_params.m:144-162`|逐时负荷倍率及节点-典型日-时段负荷|LoadFactor `[0.9444422,0.8333311,0.72222,0.6666644,0.7777756,0.8888867,0.9999978,1.1111089,1.1666644,1.1999978,1.0666644,0.9777756]`；完整 MW 张量在 JSON|无量纲/MW|派生|GFL-WG参数|由 MOST `ex_load_profile` 与 IEEE-30 基准负荷计算，再乘 Factor|是|是|需要保留数据版本/生成脚本和单位说明|
|`WindScenarios.Count/Names/Probabilities/ScaleFactors/GenerationMode`|`multiple_snapshot_default_params.json:1313-1331`；生成：`generate_multiple_snapshot_default_params.m:32-38`|风电场景数、名称、概率、倍率和生成方式|3；low/base/high；`[0.25,0.5,0.25]`；`[0.8,1.0,1.2]`；`scale_base_profiles`|无量纲|原始|GFL-WG参数|基准轨迹由 MOST，场景为倍率生成|否|是|需要文献/统计依据；校验概率与场景相关性|
|`GFL_WG.PN_MW`、`GFL_Built_Nodes`|`multiple_snapshot_default_params.json:4070-4082`；生成：`generate_multiple_snapshot_default_params.m:72-78,84-85`|已建 GFL-WG 接入节点与额定功率|节点 `[11,18]`；每站 60|节点/MW|原始|GFL-WG参数|额定功率另换算为标幺|是|需要文献/算例设定说明|
|`GFL_WG.I_Post_Multiplier`|`multiple_snapshot_default_params.json:4072`|GFL 故障后电流倍数|3|倍额定电流|原始|安全参数|由 `PN/Base_MVA` 换算系统标幺电流|是|是|需要文献支撑/灵敏度分析|
|`GFL_WG.Curtailment_Cost_per_MWh`|`multiple_snapshot_default_params.json:4073`；生成：`generate_multiple_snapshot_default_params.m:74-78`|弃风惩罚成本|30|成本/MWh|原始|GFL-WG参数|多时段按典型日天数和场景概率累计|是|是|需要文献/市场口径支撑|
|`GFM_Candidates`、`GFM_Modules.Bus/ModuleIndex`|`multiple_snapshot_default_params.json:4075-4102`；生成：`generate_multiple_snapshot_default_params.m:80-93`|GFM-ES 候选节点、模块位置和顺序|多时段候选节点 `[9,15,19]`；模块 6 个，节点 `[9,9,15,15,19,19]`，序号 `[1,2,1,2,1,2]`；单时刻候选 `[9,15,20,27]`、模块 8 个|节点/序号|原始|GFM-ES参数|人为设定|否|是|需要人工确认；单/多时段候选集差异必须解释|
|`MaxModulesPerCandidate/N_Module_Max/EnforceSequentialBuild`|`multiple_snapshot_default_params.json:4085-4087`|每候选节点模块上限、全局模块投建上限、顺序投建规则|2；4；true|模块/布尔|原始|GFM-ES参数|人为设定|否|是|需要文献或工程约束依据|
|`GFM_Modules.PN_MW/Rated_Energy_MWh`|`multiple_snapshot_default_params.json:4104-4126`；生成：`generate_multiple_snapshot_default_params.m:95-104`|模块额定功率/能量，额定时长 `E/P`|功率每模块 30 MW；能量每模块 60 MWh；额定时长 2 h|MW/MWh/h|功率、能量原始；时长派生|GFM-ES参数|时长由 `Rated_Energy_MWh/PN_MW`；标幺功率由除以 100 MVA|是|是|需要工程/文献支撑；确认“2 h”是否真实设备配置|
|`Annual_Cost_Power_per_MW/Annual_Cost_Energy_per_MWh`|`multiple_snapshot_default_params.json:4112-4134`；生成：`generate_multiple_snapshot_default_params.m:97-110`|GFM-ES 年化功率成本和能量成本|9600、37120|成本/(MW·年)、成本/(MWh·年)|原始|GFM-ES参数|直接给定；不是模型内贴现计算|否|是|需要文献/报价支撑；核查货币和年化口径|
|`Cost_Conv_GFM`|`multiple_snapshot_default_params.json:4141-4147`；生成：`generate_multiple_snapshot_default_params.m:114-117`|每模块年化投建成本|2,515,200|成本/年·模块|派生|GFM-ES参数|`9600×30+37120×60`|否|是|保留公式；避免与一次性 CAPEX 混淆|
|`Charge/Discharge_Efficiency`、`SOC_Min/Initial/Max`|`multiple_snapshot_default_params.json:4136-4140`；生成：`generate_multiple_snapshot_default_params.m:100-112`|充放电效率、SOC 边界与初值|0.9、0.9；0.1、0.5、0.9|无量纲|原始|GFM-ES参数|SOC 乘装机能量；放电递推除以效率|是|是|需要工程/文献支撑和灵敏度分析|
|`GFM_Modules.I_Post_Multiplier`|`multiple_snapshot_default_params.json:4149-4155`|GFM-ES 故障电流倍数|3|倍额定电流|原始|安全参数|故障电流进入系统标幺并叠加到约束|是|是|需要文献支撑|
|`GFM_Modules.X_GFM_res/X_GFM_vir`|`multiple_snapshot_default_params.json:4157-4171`；生成：`generate_multiple_snapshot_default_params.m:122-127`|GFM 正常运行电抗/虚拟电抗|`X_res=0.1333333`；`X_vir=0.9777778`，系统标幺；单时刻为 0.0666667、1.0444444|标幺|派生（设备值换算后存储）|安全参数|设备级 0.04 等乘 `base_MVA/PN_MW`，虚拟电抗由故障倍数与电阻公式得出|是|是|需要文献支撑；确认代码“阻抗/电抗”命名和电流模型一致|
|`I_limit_kA`、`SCR_min`|`multiple_snapshot_default_params.json:4174-4176`；单时刻：`single_snapshot_default_params.json:1390-1392`|短路电流上限、经典 SCR 下限|多时段 12.25 kA、3；单时刻 11.5 kA、3|kA、无量纲|原始|安全参数|`I_limit_kA/Base_kA` 转系统标幺；SCR 用 `PN_pu·X`|是|是|需要文献/电网规范支撑；单/多时段差异需解释|
|`Require_Source_Online`|`multiple_snapshot_default_params.json:4176`；单时刻：`single_snapshot_default_params.json:1392`|是否强制至少一个同步机或 GFM 模块在线|多时段 false；单时刻 true|布尔|原始|安全参数|无|是|需要人工确认；直接改变全停同步机可行域|
|`KZ`、`ERR_TOL_FACTOR`、`CONF.ERR_TOL`|`multiple_snapshot_default_params.json:4177,4179`；读取：`load_multiple_snapshot_case.m:108-110`；约束：`add_impedance_reconstruction_constraints.m:63-70`|阻抗元素数值缩放、误差因子、绝对容差|KZ=1000；因子=1e-6；实际 `ERR_TOL=0.001`|无量纲/缩放阻抗单位|前两项原始，ERR_TOL 派生|数值参数|由乘法计算；输出阻抗再除 KZ|是|是|数值合理性验证；报告中明确缩放前后口径|
|`ZBoundMargin`|`multiple_snapshot_default_params.json:4178`；`calculate_impedance_bounds.m:59-67,128-166`|阻抗枚举上下界外扩安全裕度|多时段 0.005；单时刻 0.05|比例|原始|数值参数|作用于由枚举极值生成的上下界|否|是|需要灵敏度分析；单/多时段差异需解释|
|阻抗边界、`rcond` 阈值|`calculate_impedance_bounds.m:31,100,110,226-229`|McCormick 连续变量上下界和可逆性筛选|边界由全部同步机/GFM 组合枚举计算；`rcond<1e-10`（安全边界）、初始 Kron 消元 `rcond<1e-12`|标幺/缩放标幺|派生/数值规则|数值参数|Z 边界乘 KZ；阈值无单位|是|是|需要合理性验证；保留枚举覆盖率与有效工况数|
|McCormick `X_lower/X_upper`|`code/functions/optimization/add_binary_product_bounds.m:1-7`；调用：`add_impedance_reconstruction_constraints.m:33-36,50-53`|二元变量与连续阻抗变量乘积线性化界|没有独立手工大 M；使用 `Z_bounds.real/imag_min/max`|缩放标幺|派生|数值参数|由阻抗组合枚举加裕度提供|是|是|保留；增加边界有效性/松弛度验证|
|硬编码数值容差|`calculate_impedance_bounds.m:240`；`calculate_short_circuit_currents.m:15,34`；`solve_multiple_snapshot_planning.m:512`|零除保护、边界最小 padding、矩阵可逆性|`1e-6`；`1e-12`；`1e-10` 等|无量纲|原始/数值规则|数值参数|无|可能影响边界/可行性|数值合理性验证；集中管理并记录|
|`Solver.Threads/MIPGap/TimeLimit/MIPFocus/Heuristics/NoRelHeurWork`|`multiple_snapshot_default_params.json:4180-4188`；应用：`build_gurobi_options.m:25-32`|Gurobi 线程、相对 MIP 间隙、时间上限和搜索策略|0；0.005；600 s；1；0.2；0|—/%/s|原始|求解器参数|无；后台入口可覆盖|影响求解时间和“最优性证明”，通常不改理论最优解但可能改截止时解|合理性验证，不需文献支撑|
|`Solver.TwoStage`|`multiple_snapshot_default_params.json:4189-4205`；阶段控制：`code/scripts/system/run_multiple_snapshot_planning.m:112-132`|两阶段可行搜索/最优性证明|启用；阶段1 1800 s、MIPGap 0.3、Focus 1；阶段2 7200 s、MIPGap 0.005、Focus 3、ConcurrentMIP 2|s/%/枚举|原始|求解器参数|无|影响运行时间、停止状态和结果可复现性|合理性验证；论文报告实际终止状态|
|`ObjectiveScale`|`multiple_snapshot_default_params.json:4187`；读取：`load_multiple_snapshot_case.m:117`；目标：`solve_multiple_snapshot_planning.m:424`|目标函数数值缩放|100000|无量纲|原始|数值参数|年化成本除以该量级，最优解理论上不变|是|数值稳定性相关|保留并验证缩放不改变解|
|`AnnualHours`|`single_snapshot_default_params.json:1283`；读取：`load_single_snapshot_case.m:30-35`|单时刻运行成本年化小时数|8760|h/年|原始|GFM-ES参数|单时刻成本乘年化小时；多时段模型不读取该字段|是|是|需要人工确认单时刻与多时段年化口径|

### IEEE-30 原始数据补充

`mpc.bus`、`mpc.gen`、`mpc.branch` 和 `mpc.gencost` 是作为 MATPOWER `case30` 整体写入 JSON 的原始参数。为避免把 41 条线路和 30 个节点逐行复制成难以核查的长表，报告保留其完整 JSON 行段作为唯一数据源：bus `5-455`、gen `457-596`、branch `597-1269`；加载代码在 `load_multiple_snapshot_case.m:6-13`。线路端点/参数的当前摘要为：1-2、1-3、2-4、3-4、2-5、2-6、4-6、5-7、6-7、6-8、6-9、6-10、9-11、9-10、4-12、12-13、12-14、12-15、12-16、14-15、16-17、15-18、18-19、19-20、10-20、10-17、10-21、10-22、21-22、15-23、22-24、23-24、24-25、25-26、25-27、28-27、27-29、27-30、29-30、8-28、6-28；RATE_A 为 `[130,130,65,130,130,65,90,70,130,32,65,32,65,65,32,65,32,32,32,16,16,16,16,32,32,32,32,32,16,16,16,16,16,65,16,16,16,32,32,32]` MVA。

## 2. 简短总结

### 2.1 最需要优先核查的 10 个参数

1. `BranchScale.r/x/b`：对潮流、阻抗、SCC/SCR 和线路约束同时起作用，且与标准 IEEE-30 已不一致。
2. `Xd_Gen=0.04`：代码注释称“暂态电抗”，用户目标要求次暂态电抗，物理含义需统一。
3. `I_limit_kA=12.25`：直接决定 SCC 安全可行域，且单时刻为 11.5 kA。
4. `SCR_min=3`：直接决定 GFL-WG 接入安全下限，需有标准或文献依据。
5. GFM `X_GFM_res/X_GFM_vir`：同时影响正常运行导纳、故障限流和阻抗重构。
6. GFM `I_Post_Multiplier=3` 与 GFL `I_Post_Multiplier=3`：故障电流贡献的核心假设。
7. GFM 模块年化成本 `9600/37120`：决定配置经济性和功率/能量比。
8. `Rated_Energy_MWh=60`、效率和 SOC 边界：决定储能调节能力及是否真正参与优化。
9. 风场景概率 `[0.25,0.5,0.25]` 与倍率 `[0.8,1,1.2]`：决定随机目标的期望成本和弃风成本。
10. `TypicalDayWeights_Days=[255,55,55]` 与 `PeriodDurations_Hours=2`：决定全年加权和储能/爬坡时间尺度。

### 2.2 可能存在量纲或年化口径风险的参数

- `base_kV=135`、`base_kA=0.4277`、`base_O=182.25`：需确认 `case30` 的电压基准列与三相电流公式是否一致。
- `Xd_Gen`、GFM 电抗：设备标幺值乘 `base_MVA/PN_MW` 的换算只在 GFM 生成脚本中显式体现；同步机电抗没有设备基准字段。
- `Ramp_*_MW_per_Hour` 与 2 h 时段：模型乘时段长度，最小开停机时间则用“时段数”，两者需要在论文中同时说明。
- `Annual_Cost_*`、`Cost_Conv_GFM`、`UC` 成本和弃风成本：代码以年化成本/年、每次成本、每 MWh 成本混合，必须明确货币、年度和典型日权重口径。
- 单时刻 `AnnualHours=8760` 与多时段 `TypicalDayWeights_Days` 的年化方式不同；不能直接比较两个算例的目标值而不做口径说明。

### 2.3 可能属于人为设定但目前注释/依据不足的参数

- 线路 `BranchScale` 三个系数。
- `Xd_Gen=0.04`、`GenCostLoading=0.05`、Pmin=5% Pmax。
- UC 爬坡率=20% Pmax/h、最小开停机=3 个时段、启停成本=固定成本的 2 倍/0.5 倍。
- 候选节点集合、模块数量上限、顺序投建规则。
- GFM 额定 30 MW/60 MWh、2 h 时长、效率 90%、SOC 10/50/90%。
- GFL/GFM 故障电流倍数 3、`SCR_min=3`、SCC 上限 12.25 kA。
- 典型日权重、负荷/GFL 倍率、风场景概率和倍率。
- `ZBoundMargin`、`KZ`、`ObjectiveScale`（这些应有数值合理性说明，而非文献支撑）。

### 2.4 论文算例部分需要明确说明的参数

应至少报告：case30 版本和 MATPOWER 数据来源；线路参数修正；系统基准 MVA/kV；同步机容量、成本、Pmin、UC 参数；GFL 节点/额定容量/弃风成本；GFM 候选节点、模块数、功率/能量、效率、SOC、电抗和年化成本；典型日权重、时长、负荷和风电场景；SCC/SCR 阈值及故障电流倍数；日首日末循环规则；以及求解器终止状态、MIPGap 和 TimeLimit。

### 2.5 只属于数值求解设置、通常不需要文献支撑但需要合理性验证的参数

`KZ`、`ERR_TOL_FACTOR`、`ZBoundMargin`、McCormick 阻抗上下界、`rcond` 阈值、`ObjectiveScale`、Gurobi `Threads/MIPGap/TimeLimit/MIPFocus/Heuristics/NoRelHeurWork`、两阶段的时间上限和并发 MIP 设置，以及分段成本切点数量。它们仍需通过尺度检查、线性化误差检查、不同容差/界限下的解稳定性检查和求解器终止状态记录来验证。

## 3. 重要缺项与审计结论

1. 未发现显式的同步机初始开机状态、初始已开/停机持续时间参数；多时段模型采用典型日内循环状态和循环最小开停机窗口。
2. 未发现 GFM-ES 寿命、贴现率或 CRF 计算参数；成本字段已经是“Annual_Cost_*”，所以当前模型是直接读取年化成本，不是由寿命和贴现率现场年化。
3. 未发现独立的手工大 M 参数；阻抗乘积的上下界由所有允许同步机/GFM 投运组合枚举，并通过 `ZBoundMargin` 外扩后用于 McCormick 线性化。
4. 未发现单独的电压支撑强度阈值；当前安全参数主要是 SCC 电流上限、经典 SCR 下限、故障后电流倍数和阻抗/导纳参数。
5. 单时刻与多时段默认文件在候选节点、模块数量、线路修正、SCC 上限、源在线要求和数值裕度上存在差异，不能把它们视为同一组参数的不同维度。
6. `data/params/generate_multiple_snapshot_default_params.m` 是可读参数源脚本，JSON 是运行时读取文件；后续若调整参数，应保持二者同步并重新生成 JSON。
