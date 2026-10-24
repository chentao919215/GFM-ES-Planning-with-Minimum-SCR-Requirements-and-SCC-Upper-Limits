# Section IV-D SCR–SCC 二维联合灵敏度扫描

入口：`code/scripts/system/run_scc_scr_joint_sensitivity_analysis.m`。

当前入口 `Execute_Full_Scan = true`，运行会启动 6×6 网格的真实求解。若只生成、验证输入和输出待求解网格，请先将该开关设为 `false`；底层函数的 `Options.Execute` 缺省为 `false`。两个参数数组可扩展、加密、重新排序，必须包含 `(5.6 kA, 2.8)`，且各轴不能重复。

## 复用及兼容性

现有 `run_multiple_snapshot_sensitivity_scan` 能固定 SCC 扫 SCR，但每次会重新生成默认参数、建立新的时间戳目录，且缺少有效结果续算和精确的无可行解分类；当前默认参数还关闭两个安全约束并采用确定性风电输入，因此没有直接嵌套调用。

新增 `run_multiple_snapshot_joint_sensitivity_scan` 只编排输入、阶段、检查点及汇总。模型仍由 `load_multiple_snapshot_case`、`apply_multiple_snapshot_solver_stage`、`solve_one_stage`、`solve_multiple_snapshot_planning`、`build_multiple_snapshot_mip_start_from_result`、`package_multiple_snapshot_result` 和原保存函数实现。未改写规划约束、目标函数或一维扫描脚本/扫描函数。

小范围兼容扩展：

- 参数生成脚本接受可选 `Parameter_Generation_Options.Output_File` 和 `.Case_5=true`；在生成场景之前启用随机模式与两个安全约束。通过隔离函数工作区生成独立快照，不覆盖默认 JSON。未提供选项时，原入口行为保持不变。
- `solve_one_stage` 第四参数及 `solve_multiple_snapshot_planning` 第三参数可选为 `true`，允许没有 incumbent 时返回、保存结构化诊断，且不提取无效决策。默认仍使用原有报错行为；该诊断出口只支持新版模型。
- `build_multiple_snapshot_diagnostics` 补充原始 Gurobi `solver_status`，保留全部原诊断字段。

4 个典型日及每日至 4 个原始场景只从原参数源生成一次，概率不重新归一化，轨迹不聚合。每点仅修改 `Security.I_limit_kA` 和 `Security.SCR_min`，然后经原加载函数转换为公开 CONF，再转换为内部 CONF。验证所有非扫描输入一致，且 `I_limit_pu * Base_kA == 当前 kA 限值`、SCR 为无量纲。

求解使用原 Stage 1，达到 Stage 2 的目标 gap 时跳过 Stage 2，否则使用原整数热启动流程。目标 gap 为现有的 `0.005`。原实现的第二阶段名义 `Solver.Time_Limit=1800 s`，原生 `Stage_2.Options.gurobi.TimeLimit=900 s`，实际采用原生值；本次完整保留这一既有设置。仅把日志路径分配至各点、各次尝试的独立目录。

如存在 `results_useful/from_laptop/IV-B/Case_5_Stage_{1,2}.mat`，将只读比较其完整内部 CONF（忽略日志路径和热启动缓存），输出核对表；不匹配时先停止，防止静默使用另一套 Case 5。缺少历史文件时仍可按当前参数源生成并验证 Case 5，核对表会标记 reference_unavailable。

## 输出

默认目录为 `results/multiple_snapshot_scc_scr_joint_sensitivity/`：

```text
manifest.mat                           输入源/代码 SHA-256 与冻结快照校验值
case5_baseline_parameters.json          只生成一次的完整随机 Case 5 输入
case5_reference_validation.{mat,csv}    原 Case 5 两阶段配置对照
joint_summary.{mat,csv}                长表；MAT 含 Joint 和 Summary_Table
Cost_Matrix.csv                        行 CSCR，列 SCC 上限（kA）
Module_Count_Matrix.csv
Configuration_Matrix.csv
Status_Matrix.csv
MIP_Gap_Matrix.csv
Feasible_Matrix.csv
Best_Bound_Matrix.csv
Power_MW_Matrix.csv
Energy_MWh_Matrix.csv
monotonicity_checks.csv
SCC_5p6_kA_CSCR_2p8/
  SCC_5p6_kA_CSCR_2p8_parameters.json
  SCC_5p6_kA_CSCR_2p8_point.mat          原子更新的单点检查点
  <独立尝试目录>/
    SCC_5p6_kA_CSCR_2p8_record.mat
    stage_1/SCC_5p6_kA_CSCR_2p8_stage_1.mat
    stage_2/SCC_5p6_kA_CSCR_2p8_stage_2.mat
```

失败、重试均写入新尝试目录，保留既有阶段文件。单点检查点含 `Record.Row`、完整 `Params`、`Manifest` 和阶段结果的 SHA-256；阶段 MAT 保留原 `Result` 结构，无可行解时仅有 CONF、Diagnostics 和 solve_time。只有运行过的阶段才有对应文件。

长表记录阈值、矩阵坐标、状态、可行性、gap、下界、时间、成本及其四项分项、模块配置、节点和模块数、MW/MWh 容量、输入/结果路径及异常。`Total_Solve_Time_s` 为参与本结果的各阶段墙钟时间之和；`Runtime_s` 为最近一次尝试耗时。求解器内部时间保留在各阶段 `Result.Diagnostics.solvertime` 中。

MAT 的 `Joint` 含各矩阵、两条轴、长表、来源和基准核对信息。轴严格采用输入数组的顺序；模块配置按参数源的模块顺序表示，节点模块数按候选节点顺序表示，避免 MATLAB 列优先展平导致错配。未获得有效可行解的成本和配置数量用 NaN/空字符串表示，不填零。

## 状态和续算

| Status | 含义 |
| --- | --- |
| pending / running | 尚未求解 / 阶段检查点 |
| target_met | 可行、通过结果校验，且达到目标 gap |
| feasible_target_not_met | 保留可行解，未达到目标 gap（gap 未知也归此类） |
| proven_infeasible | 求解器明确证明不可行 |
| stopped_no_incumbent | 时限、资源限制或中断，且未得到可行解 |
| no_incumbent_unknown | 不可行/无界未区分等未定状态 |
| solver_or_model_error | 建模、求解器、结果验证等错误；仍可保留之前的可行解 |

`Is_Feasible` 表示有通过必要校验的可行结果；不能由“不是 target_met”推断不可行。各阶段 Status 和结果文件保留阶段诊断。第二阶段失败或无 incumbent 时不丢弃第一阶段的有效解。

再次使用同一 Run_Directory 会核对源码、原始数据、冻结基准、完整点参数、阶段文件校验值、内部 CONF、数组维度、整数决策、成本加总/目标值和当前安全阈值。只有有效且完整的 target_met 或 proven_infeasible 点默认跳过。`Retry_Unfinished=false` 可同时接受已完整保存的 feasible_target_not_met 点。默认重试其余点；如第一阶段有效，则只重跑第二阶段。

改动源码或时序数据后使用新的 Run_Directory；修改网格轴不需要新目录。篡改点输入会报错，不允许以同一阈值目录静默混合另一份输入；损坏或缺失结果会拒绝检查点并重算。

## 轻量验证

测试入口：`code/tests/test_scc_scr_joint_sensitivity.m`。测试使用临时路径下的模拟阶段求解函数，未调用 optimize/Gurobi，且模拟输出与正式结果目录分离，来源校验也会阻止混用。

验证覆盖原始场景和概率、24 点合成测试网格、非排序轴映射、模块布局、成本加总、阶段切换、结果损坏、断点续算和各类停止状态。2026-10-24 的 6 项测试全部通过；本次文档与代码同步未启动真实网格求解。仅准备输入时，网格全部标记为 pending。

单调性检查仅使用通过验证且达到目标 gap、具有有效 best bound 的点。收紧方向为 SCC 上限减小、SCR 下限增大。若宽松点的下界仍高于严格点的可行上界，则标记 review_disjoint_bounds；若仅 incumbent 成本下降且区间重叠，则标记 reversal_within_MIP_uncertainty。原始成本均不改写。无真实可靠解时不声称已验证数值成本趋势。
