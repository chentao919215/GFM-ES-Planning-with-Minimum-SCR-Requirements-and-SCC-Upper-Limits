# 2026-10-23 论文模型迁移记录

本次技术基准为用户确认的 `manuscript_10_23_17_40.docx`，公式以同名 PDF 的 Section II、Section III 和 Appendix 核验。仓库没有任务最初所写的 `17_00` 文件。新版 Section IV 为空，未据此指定任何新算例参数或参考最优解。

默认建模入口已切换到新版。迁移没有把 Section IV 尚未确认的历史参数或结果指定为新版算例基准。以下路径相对于项目根目录。

## 文件与公式对应

| 文件 | 对应内容 |
| --- | --- |
| `code/functions/network/build_multiple_snapshot_network.m` | 复用 Kron 降阶与位置矩阵，式（1）—（3）；新版按线路投运状态构造网络，忽略电阻、并联电纳、变比和移相对安全网络的影响 |
| `code/functions/network/prepare_converter_security_network.m` | 源电纳、同节点模块电纳求和、式（4）虚拟阻抗修正、故障移除连通分量、Appendix 有效电抗界 |
| `code/functions/security/add_converter_security_constraints.m` | 式（18）—（20）并集/交集，式（21）—（23）并集残压及 SCC，式（24）—（26）交集电抗列及 SCR；支持逐时实际 UC 状态装配 |
| `code/functions/security/add_converter_source_support_constraints.m` | 式（29）、（30）源支撑，独立于 SCC/SCR 限值开关，在规划约束中调用 |
| `code/functions/security/add_lvrt_segment_constraints.m` | 式（9）的精确三段 LVRT MILP |
| `code/functions/optimization/build_multiple_snapshot_planning_model.m` | 式（27）、（28）、（31）—（35）：目标函数、直接投建、逐场景运行及循环边界；构建模型而不调用求解器 |
| `code/functions/optimization/solve_multiple_snapshot_planning.m` | 默认新版求解、诊断、热启动与后验复算；显式 legacy 参数路由到旧版 |
| `code/functions/security/calculate_converter_security_state.m` | 式（4）—（17）、（24）—（25）的独立数值复算，不需要优化求解器 |
| `code/functions/security/calculate_converter_security_metrics.m` | 并集、交集和真实逐时状态分别复算；检查 Appendix 两个定理的保守性 |
| `code/functions/io/aggregate_gfl_node_parameters.m` | 式（8）、（9）、（25）的节点 GFL 聚合；相同节点容量、额定电流及 LVRT 斜率按系统基准合并 |
| `code/functions/io/load_multiple_snapshot_case.m`、`normalize_multiple_snapshot_conf.m` | 版本配置、免枚举加载；保留原有模块效率、SOC 和额定时长一致性校验 |
| `code/functions/io/package_multiple_snapshot_result.m`、`code/functions/figure/prepare_figure_data.m`、`code/functions/utils/print_multiple_snapshot_summary.m` | 新结果语义、绘图数据兼容、单候选节点多模块维度修复 |
| `code/functions/optimization/build_multiple_snapshot_security_constraint_assembly.m`、`solve_one_stage.m` | 新旧装配诊断及求解路由 |
| `code/scripts/system/run_multiple_snapshot_planning.m`、`start_multiple_snapshot_planning_longrun.m`、`resolve_project_root_for_script.m` | 主脚本入口、后台入口和根目录定位；主脚本会重生成默认 JSON，并在求解后调用 `mailTome` |
| `code/functions/utils/run_multiple_snapshot_sensitivity_scan.m` | 结果摘要兼容没有 `lambda_c` 的新结果 |
| `code/functions/optimization/solve_multiple_snapshot_planning_legacy.m`、`solve_multiple_snapshot_planning_periodwise.m` | 保留旧版聚合实现；逐时入口对新版配置调用公共新版模型，仅显式 legacy 配置进入旧逐时实现 |
| `code/tests/build_converter_test_case.m`、`test_converter_security_model.m`、`test_converter_planning_solve.m` | 独立三节点测试数据及分层验证 |

## 数学实现与复用范围

新版优化模型不含配置枚举、`lambda_c`、UC 状态枚举、配置—状态联合选择、禁止状态对或 indicator 约束。旧版这些函数仍保留给 legacy 使用，不被新版构建器调用。新版读取参数时不生成配置目录，也不再受旧版最多 20 个模块的枚举限制。

旧版 SCC 的阻抗转移系数上界、交集 LVRT 电流上界及配置分解电流全部退出新版路径。SCC 直接使用并集网络的 `A V - phi(V) = A 1`（非故障行，`A=-B`），随后用故障行的式（22）计算电流。本地修正是故障节点所有已投建模块的 `1/x_res - 1/(x_res+x_virtual)` 之和；远端 GFL 的贡献已经进入联立求解的残压。新版不启用旧后处理中的远端 GFM 自适应限流扩展。

SCR 只重构交集网络中 GFL 节点所需的电抗列。电抗下界为零；上界来自每一个候选单源网络的逆矩阵逐元素最大值。对于任何满足式（29）的网络，选取其中一个已投入源，该实际网络的接地电纳不少于对应单源网络；由 Appendix 的 M 矩阵逆单调性，实际逆矩阵不超过该单源逆矩阵，因此上界有效。实现仅向外添加浮点舍入余量。无需配置或 UC 状态枚举，也无需额外安全裕量近似。

残压使用论文的 `[0,1]` 有效界；式（30）保证非故障连通分量有源，方程解因而为正。没有引入任意正电压下限。二进制与残压/电抗的乘积沿用 `add_binary_product_bounds` 的四条精确 McCormick 约束。三段 LVRT 使用分段选择二进制变量与有界分段电压，两个断点均准确包含。

式（29）作用于日内交集网络，式（29）—（30）已移至规划约束，即使 SCC/SCR 限值均关闭也保留。式（30）作用于每个故障移除分量的**每一个逐时 UC 状态**，不额外要求该分量在交集状态下有源。安全模型中没有充放电开关；已投建 GFM 在充电、放电和零有功状态下均提供源支撑。

原有无损 DC 潮流、标准循环 UC、逐场景爬坡、循环最小开停机时间、储能能量递推及期末闭合、场景概率权重和分段透视成本割得到复用。归一化出力等式改写为等价的乘法形式，以支持 `Pmax=Pmin`，避免除零。移除了旧版额外的 `弃风 >= 可用风电-额定容量` 约束，按式（32）仅使用可用功率作为运行上界；用户应提供物理有效的可用功率场景。新版不施加旧版顺序投建限制，避免不同额定功率/电抗/成本的模块被错误强制排序。

模块投建维度为 `[候选节点,模块序号]`，跨全部典型日、场景和时段共享。UC、启停维度为 `[机组,典型日,时段]`；有功运行变量维度为 `[元件,典型日,风电场景,时段]`。安全残压维度为 `[保留节点,故障节点,典型日]`，SCR 电抗列维度为 `[保留节点,GFL节点,典型日]`。安全内部使用系统基准标幺值；运行功率为 MW、能量为 MWh、时长为小时；输出 SCC 乘 `Base_kA`，SCR 无量纲。

## 初次迁移的验证记录

本节为初次迁移时的记录；后续算例分析、当前可用入口及 T=3 新版 AG/PW 验证见项目 README。本次同步不新增或更新 MAT 输入。

环境为 MATLAB R2024b、现有 YALMIP，以及原参数文件指定的 Gurobi 13.0 MATLAB 接口。没有修改求解器选择；测试只收紧测试专用时限和间隙。所有优化测试均实际求解，未以静态检查冒充求解成功。

最终共 **12 项测试通过，0 项失败，0 项未执行**：

1. 并集/交集逻辑完整真值表。
2. 故障节点多个 GFM 模块修正求和；虚拟阻抗不改变非故障残压；远端 GFL 对无本地 GFL 的故障节点有贡献。
3. 枚举小网络模块状态和两时段 UC，执行 56 次有效逐时比较，满足 `SCC_hourly <= SCC_union` 和 `SCR_hourly >= SCR_intersection`；同时检查电抗界。
4. 故障移除后的多个连通分量识别及无源分量拒绝。
5. 全部约束线性、场景共享关系及变量维度检查，无旧版选择变量。
6. LVRT 三段内部与两个断点，二进制—连续乘积精确性。
7. 同节点 GFL 容量、额定电流、LVRT 斜率和饱和值聚合。
8. Kron 降阶与全网逆矩阵保留块一致；停运线路不参与潮流或安全网络。
9. 强制非零充放电的可行 MILP：节点平衡、DC 潮流、能量损耗和循环 SOC，分别复算发电透视成本、弃风和投资成本。该人工测试目标值为 `1771376.2445`，只用于验证测试数据。
10. 逐时分量有源、但分量交集无源的合法情况可行，防止误加强式（30）。
11. 默认求解、MAT 结果保存、后验一致性和现有绘图数据入口。自由规划测试目标值 `1660601.125`，并非论文新算例结论。
12. 典型日独立循环 UC、首时段启动/末时段停机、启停成本只按日权重计一次；延长最小开机时间后，刻意不满足该条件的测试被正确判为不可行。

原完整参数规模也完成了一次新版模型构建检查：配置目录为零，17,117 个 YALMIP 约束块全部线性；没有对原大规模参数执行优化或将旧结果作为正确答案。

MATLAB Code Analyzer 未发现语法错误；复用的模型拼接代码保留原有动态扩展性能提示。YALMIP `sdpsettings` 初始化产生现有 OSQP 安装缺少 `osqp_mex` 的警告，实际选用的 Gurobi 求解通过。首次扩展 UC 负例测试返回 Gurobi 的 `INF_OR_UNBD`，对该负例关闭 dual reductions 后确认不可行，测试通过。初次单候选多模块结构测试发现的向量方向错误已修复。

工作区验证日志保存在 `tmp/migration/validation_log.txt`、`validation_retry_log.txt` 和 `validation_results.mat`；这些文件为临时验证记录，不作为论文算例数据。

未进行新版 Section IV 的工程算例优化、性能比较或灵敏度实验，因为新算例参数尚未提供。未对旧版模型重新求解；未逐张重绘所有历史论文图。已验证新结果的通用绘图数据适配路径，历史论文图仍属于历史算例。

## 运行步骤

在 MATLAB 中执行：

```matlab
Project_Root = 'D:\Project_With_Codex\Project_2';
addpath(genpath(fullfile(Project_Root,'code')));

% 无求解器安全计算、YALMIP结构测试；缺少YALMIP时相关测试标记未执行。
runtests(fullfile(Project_Root,'code','tests','test_converter_security_model.m'))

% 使用参数文件已配置的求解器执行独立的小规模优化测试。
runtests(fullfile(Project_Root,'code','tests','test_converter_planning_solve.m'))
```

主运行脚本保持 MATLAB 脚本形式。若工作区已设置 `Parameter_File`，直接读取指定 JSON；否则运行参数生成器并重生成默认 JSON。使用新版算例时，应传入经确认的参数文件；仓库默认值仍是历史设置：

```matlab
Project_Root = 'D:\Project_With_Codex\Project_2';
addpath(genpath(fullfile(Project_Root,'code')));
Parameter_File = 'D:\your_case\confirmed_parameters.json'; % 替换为真实路径
run(fullfile(Project_Root,'code','scripts','system', ...
    'run_multiple_snapshot_planning.m'));
% 脚本加载指定参数并按配置执行单阶段或两阶段规划。
```

清除 `Parameter_File` 后运行主脚本会使用默认参数源；这会覆盖默认 JSON。主脚本最后调用 `mailTome` 发送完成通知；若环境未配置该函数，通知步骤可能报错。后台入口 `start_multiple_snapshot_planning_longrun(Project_Root,Parameter_File)` 使用传入参数文件。结果沿用现有 MAT 输出和绘图流程；绘图时应使用生成该结果时的参数文件。

JSON 顶层 `ModelVersion` 缺省为 `2026-10-23`。显式设为 `legacy` 时，加载器才建立旧目录，默认求解接口路由到保存的旧版实现。新版 `solve_multiple_snapshot_planning_periodwise` 设置 `SecurityFormulation='periodwise'`，调用与聚合模型相同的新版构建和求解流程；旧逐时实现仅用于显式 legacy 配置，不能将不同版本混作性能对照。新模型结果没有 `lambda_c`，`Z_SCC` 为空；`Z_SCR` 保留物理标幺复数外壳供已有结果接口使用，真正决策变量只有实电抗。

## 需确认的算例输入

需用户给定或确认新的网络/基准值、GFL 节点及节点聚合额定容量、GFM 候选节点和逐模块容量/能量/电抗/虚拟电抗/年化成本、LVRT 斜率和阈值、节点 SCC 上限和 SCR 下限，以及负荷、典型日权重、风电场景与概率、UC 参数。沿用参数 JSON 的既有分组结构；`SCR_min` 可用标量或完整节点向量，SCC 限值同样由配置输入。

同节点 GFM 必须满足 Section III-C 的共同效率、SOC 和额定时长条件，现有加载器会拒绝不一致输入。重复 GFL 节点记录可在共同 LVRT 阈值条件下精确聚合；异阈值会产生超过三段的响应，代码明确拒绝，不能在未修改论文模型前擅自合并。MATPOWER 节点须为连续内部编号 `1:N`，安全网络须连通，在运线路须具有正电抗。

原参数文件仅是现有输入格式及读取兼容性的来源；本迁移没有将其中的旧设备参数认定为新版默认算例参数。
