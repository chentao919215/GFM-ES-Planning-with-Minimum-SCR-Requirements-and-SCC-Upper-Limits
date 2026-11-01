## 1. 项目简介

本仓库提供Manuscript所提模型的MATLAB实现及算例复现程序。所建立规划模型考虑风电出力不确定性，在短路比(SCR)下界与短路电流(SCC)上界约束下，联合优化构网型储能(GFM-ES)投建、机组组合(UC)及系统运行。本文件包括如下部分:

1. 项目简介；
2. 项目环境与依赖；
3. 代码结构；
4. Manuscript结果复现步骤。

## 2. 项目环境与依赖

系统级规划采用以下软件环境:

- MATLAB: 已验证R2024b版本，在本项目用于运行代码与处理结果；
- MATPOWER: 已验证7.1版本，在本项目用于提供IEEE-30节点基准算例；
- YALMIP: 已验证20250626版本，在本项目用于构建优化模型与调用求解器；
- Gurobi: 已验证13.0版本，在本项目用于混合整数线性规划(MILP)求解。

安装MATLAB，并将MATPOWER、YALMIP和Gurobi的MATLAB接口目录加入MATLAB搜索路径。运行前，按第4.1节将本项目的源函数与入口脚本目录加入MATLAB搜索路径。

其他功能按需配置以下依赖：

- **设备级仿真**: Simulink和Simscape Electrical/Specialized Power Systems。
- **控制器参数整定与装备级模型初始化**: Control System Toolbox。
- **典型日与风电场景生成**: Statistics and Machine Learning Toolbox(直接使用已处理的时序输入进行规划时，不需要重新生成场景)。

## 3. 代码结构

项目根目录下各主要目录的用途如下：

- **`code/`**：存放项目源脚本与函数。
- **`data/`**：存放算例参数、时序输入数据及数据预处理程序。
- **`results/`**：存放运行规划求解和分析程序后生成的结果文件。
- **`results_for_case/`**：存放Manuscript算例的结果归档，用于结果核对与绘图复现。
- **`figs/`**：存放绘图程序生成的可编辑FIG图件。
- **`simulink/`**：存放设备级验证使用的Simulink模型及仿真生成文件。初始化、整定与验证步骤见[装备级模型说明](simulink/README.md)。

### 3.1 `code/`：源脚本与函数

`code/`分为`scripts/`和`functions/`两部分，分别存放运行入口与可复用函数。
以下路径相对于`code/scripts/`。

| 路径 | 用途 |
|------|------|
| `system/`                   | 规划求解(IV-B与IV-C部分)、时间尺度分析(IV-C部分)与SCC-SCR联合灵敏度分析(IV-D)的入口脚本 |
| `equipment/initialization/` | 单机GFL-WG与单机GFM-ES的参数计算、检查及工作区初始化 |
| `equipment/validation/`     | LVRT、SCR边界与虚拟阻抗限流的工况设置、仿真、验收及归档 |
| `figure/for_paper/`         | Manuscript Fig. 4–10的绘图脚本 |
| `figure/for_debug/`         | 规划配置、运行状态、线路负载与安全指标的详细绘图脚本 |
| `figure/equipment/GFL/`     | GFL的LVRT理论特性与端口验证绘图 |
| `figure/equipment/GFM/`     | GFM的限流/未限流理论特性与端口、状态验证绘图 |
| `figure/equipment/SG/`      | 同步机初始对称短路电流理论特性绘图 |

以下路径相对于`code/functions/`。

| 路径 | 用途 |
|------|------|
| `io/`                    | 参数读取、算例准备、单位换算与结果保存 |
| `network/`               | 潮流网络、安全网络及节点映射的构造 |
| `optimization/`          | 规划模型构建、求解器配置、阶段切换与热启动 |
| `security/`              | SCC/SCR安全约束、固定状态指标复算与聚合保守性核验 |
| `figure/`                | 共用配色、图件创建与FIG保存、调试绘图数据及GFM验证绘图 |
| `case_study/IV-C/`       | Manuscript时间尺度分析与AG/PW对比的输入准备、求解编排及汇总 |
| `case_study/IV-D/`       | Manuscript联合灵敏度分析的扫描、续算、一致性核对及汇总 |
| `equipment/parameters/`  | GFM原始物理参数、控制设计输入与系统基准换算 |
| `equipment/tuning/`      | 显式输入LCL及设计设置，计算Ki并校核的三个控制环函数 |
| `equipment/calculation/` | 验证和绘图共用的GFM端口理论电流计算 |
| `simulink/`              | 公共缓存目录与运行前参数准备 |
| `utils/`                 | 项目根目录定位与输出目录准备两个通用工具 |

主规划入口为`run_multiple_snapshot_planning.m`，依次完成参数生成、算例准备、阶段求解与结果保存。`solve_multiple_snapshot_planning.m`负责构建并求解规划模型，安全约束由`add_converter_security_constraints.m`装配，求解后的指标由`calculate_converter_security_metrics.m`独立复算。

### 3.2 `data/`：算例参数与时序数据

`data/`分为`params/`和`RTS-GMLC/`两部分，分别维护规划算例参数和典型日、风电场景数据。

| 路径 | 用途 |
|------|------|
| `params/generate_multiple_snapshot_default_params.m` | 参数维护入口，定义Network、SG、UC、GFL-WG、GFM-ES、安全约束、多时段及求解设置 |
| `params/multiple_snapshot_default_params.json`       | 参数脚本生成的中间文件，供规划程序读取 |
| `RTS-GMLC/raw/`                                      | 预处理所需的官方原始CSV，以及数据来源和格式说明 |
| `RTS-GMLC/processed/`                                | 固定Manuscript输入：一个MAT和四个CSV，保存归一化曲线、典型日权重、场景概率、来源清单及质量记录 |
| `RTS-GMLC/scripts/`                                  | 时序数据重新生成和绘图的入口脚本 |
| `RTS-GMLC/functions/`                                | 配置、数据读取与保存、聚类及代表性验证函数 |
| `RTS-GMLC/results/`                                  | 新生成的数据和图件输出目录 |

算例参数在`.m`参数脚本中维护。运行该脚本会读取MATPOWER的`case30`和固定时序输入，将归一化曲线按IEEE-30原始节点负荷分布及GFL-WG额定容量映射为MW，并生成或覆盖JSON。

固定时序输入为4个典型日(D=4)、每个典型日4个风电场景(K=4)，每日包含24个1 h时段。默认规划复现直接使用`RTS-GMLC/processed/rts_gmlc_profiles.mat`，无需重新运行数据预处理。

重新生成的数据写入`RTS-GMLC/results/run_时间戳/`，不覆盖固定输入。需要更新Manuscript输入时，先核对生成结果，再将MAT和四个CSV一并替换到`RTS-GMLC/processed/`，随后重新生成参数JSON。数据来源、预处理方法、重新生成及绘图步骤见[RTS-GMLC说明](data/RTS-GMLC/README.md)。

### 3.3 计算结果与图件

主规划结果保存为`results/multiple_snapshot_planning_result_时间戳.mat`，文件中包含`Result`结构体。主要字段包括：

当前完整规划结果包含22个顶层字段，统一采用以下约定：

- `Cost`保留`Total`、`GEN`、`GFM_Fixed`、`Curt`和`UC`，分别表示总成本、同步机发电成本、GFM-ES年固定成本、弃风成本和启停成本，均以$/年计。

- `u_G`、`u_G_Start`和`u_G_Stop`按[机组,典型日,时段]排列；
- `u_G_SCC`与`u_G_SCR`按[机组,典型日]排列，分别为日内并集、交集；
- `u_GFM_Unit`按[候选节点,设备序号]排列。

- `P_G`、`P_GFL`、`P_GFL_Curt`、`P_Line`按[对应元件,典型日,风电场景,时段]排列；
- `P_GFM_Ch`、`P_GFM_Dis`、`E_GFM`和`u_GFM_Ch`的首维为候选节点。功率以MW计，能量以MWh计，状态变量为0/1。

- `SCC_Aggregated`和`SCR_Aggregated`按[原始节点,典型日]排列，未评估节点为NaN(SCC以kA计，SCR无量纲)；

- `SCC_TimeResolved`与`SCR_TimeResolved`分别按[时段,典型日,SCC安全节点]和[时段,典型日,GFL节点]排列；
- 节点顺序由`CONF.SCC_Constraint_Original_Nodes`和`CONF.Safety_GFL_Original_Nodes`确定。

- `CONF`是唯一配置快照，保存物理输入、实际阶段设置、节点映射、机组节点、线路端点及线路限值。

- `Diagnostics.solvertime`为求解器报告的优化时间，`yalmiptime`为YALMIP报告的调用开销，`walltime`为建模、求解、结果提取及逐时安全后处理的墙钟时间，不含文件保存与摘要输出，三者均以秒计。论文时间对比使用各实际阶段的`solvertime`之和。

- `SecurityValidation.Conservatism`记录聚合界与逐时极值的关系，正差值表示违反保守性；`Limits`记录逐时安全限值检查，`Failures`保留复算失败信息。`Limits.SCC.Passed`与`Limits.SCR.Passed`分别表示物理限值是否满足，`Limits.Passed`只要求`CONF`中启用的约束满足，因此关闭的约束仍可报告越限。

Manuscript绘图脚本按以下目录和文件名读取归档：

| 目录 | 文件约定 | 用途 |
|------|----------|------|
| `results_for_case/IV-B/` | `Case_1_Stage_1.mat`至`Case_5_Stage_2.mat`，每个Case分别保存实际执行的阶段结果 | 五组规划算例；Fig. 4–7读取各Case的`Stage_2`文件 |
| `results_for_case/IV-C/` | `T03_AG_1.mat`、`T03_AG_2.mat`等；T取03、06、12、24，AG/PW分别表示聚合/逐时模型，1/2表示求解阶段 | Fig. 8–9的模型规模与求解时间对比 |
| `results_for_case/IV-D/` | `joint_summary.csv`、`Cost_Matrix.csv`、`Configuration_Matrix.csv`、`Unit_Count_Matrix.csv`、`Status_Matrix.csv` | Fig. 10的联合灵敏度结果 |

运行计算程序生成的结果写入`results/`，不会自动更新`results_for_case/`。需要使用新结果绘制Manuscript图件时，应先核对结果，再按上述约定复制归档。MAT文件均保留变量名`Result`。

所有绘图入口仅保存`.fig`文件。Manuscript图件写入`figs/for_paper/`，详细运行图件写入`figs/for_debug/`，设备图件按GFL、GFM和SG分别写入`figs/equipment/`下的同名子目录。绘图数据及统计表通过返回值`Report`查看；计算、分析与设备验证程序生成的MAT和CSV仍保存在各自的结果目录，供核对及绘图读取。

图中文字统一使用英文，字体统一为Times New Roman。`figure_style.m`维护原Manuscript配色：SCC使用蓝色`#598EBB`，SCR使用浅蓝色`#6CAAC4`，聚合界与逐时值分别使用青绿色`#8CCDC6`和紫色`#948EC1`；五组算例沿用原有五色顺序。设备图中SG、GFL和GFM分别使用上述蓝色、算例绿色`#9CCB96`和算例橙色`#E8A469`。论文图与检查图分别使用`paper`、`review`字号设置，共用配色、线宽及坐标样式。

### 3.4 源码维护约定

源码以`run_multiple_snapshot_planning.m`及其调用链为风格基准：

- 说明性注释使用中文，图中文字使用英文；保留Manuscript公式编号、单位及数组维度约定。
- 入口先说明职责，再设置参数，随后按编号分节；局部辅助函数放在文件末尾并说明用途。
- 函数名称使用`snake_case`，描述性变量采用`Project_Root`形式；物理量、数学索引和外部接口沿用当前约定。
- 使用四空格缩进，条件及循环分行书写；长调用按参数换行。JSON、MAT归档字段及Simulink模型变量保持明确的单一接口，不补入旧字段或旧入口。

阶段求解的第四个参数`Return_No_Incumbent`默认为`false`；扫描流程可显式设为`true`，保存无可行解时的诊断归档。绘图入口负责默认路径和文件读取，GFM底层绘图函数接收验证结果、FIG路径和样式三个显式输入。

## 4. Manuscript结果复现步骤

### 4.1 运行准备

在 MATLAB 中将当前文件夹切换到项目根目录，按第 2 节配置外部依赖，并将 `code/`与`data/` 及其子目录加入 MATLAB 搜索路径。

以下命令均在项目根目录下执行，也可在MATLAB编辑器中打开相应入口并点击“运行”。仅复现已有结果的图件时，先确认第3.3节所列归档已准备齐全；若下载内容未包含MAT归档，可按下文重新计算并归档。

`run_multiple_snapshot_planning.m`、`run_scc_scr_joint_sensitivity_analysis.m`和`run_temporal_scalability_analysis.m`默认关闭完成通知，不需要个人邮件函数。自行配置`mailTome`后，可将入口中的`Enable_Completion_Notification`设为`true`。

### 4.2 规划结果与安全评估

默认参数对应Manuscript Case 5，即同时考虑风电不确定性、SCR下界与SCC上界。运行：

```matlab
run_multiple_snapshot_planning;
```

脚本会先执行参数生成脚本，再读取生成的JSON并求解。参数修改应在`data/params/generate_multiple_snapshot_default_params.m`中完成；单独修改JSON会在下次运行主规划入口时被覆盖。

五组算例通过参数脚本中`params.Security`下的三个字段切换：

| 算例 | `Consider_Wind_Uncertainty` | `Enable_SCR` | `Enable_SCC` |
|------|---------------------------|--------------|--------------|
| Case 1 | 0 | false | false |
| Case 2 | 0 | true  | false |
| Case 3 | 0 | false | true  |
| Case 4 | 0 | true  | true  |
| Case 5 | 1 | true  | true  |

`Consider_Wind_Uncertainty=0`时，使用四个原始场景的概率加权平均风电轨迹；取1时，保留四个场景及其概率。其余物理和成本参数保持一致，SCR下限为2.8，SCC上限为5.6 kA。关闭限值约束后，程序仍对最终方案复算安全指标，便于比较约束的影响。

默认采用两阶段求解：第一阶段以30%的相对MIP间隙为目标，限时300 s；第二阶段以第一阶段结果热启动，将目标间隙收紧至0.5%，限时900 s。若第一阶段已经达到最终目标，则跳过第二阶段。单阶段与两阶段的切换及各阶段设置均在参数脚本的`Solver`部分维护。

运行完成后，工作区中的`Result`为最终结果，`Result_File`记录保存位置。实际执行两阶段时，`Result_File_Stage_1`记录第一阶段文件，`Result_File`记录第二阶段文件。分别计算五组算例后，将各阶段结果副本按第3.3节命名归档；阶段2未执行时，应保留实际阶段信息，不能将阶段1文件直接当作阶段2归档。

成本分项可从`Result.Cost`读取。判断是否达到求解目标时，结合`Result.Diagnostics.has_incumbent`和`Result.Diagnostics.mip_gap`；达到时间上限时返回的可行解不一定达到0.5%的目标间隙。计算时间和返回解可能随计算机配置、求解器设置及版本变化。

### 4.3 聚合方法验证与时间尺度分析

Fig. 6–7通过比较五组算例的聚合安全指标与逐时极值，核验SCC上界和SCR下界的保守性。完成Case 1–5归档后，可直接按第4.5节绘图。

时间尺度分析以Case 5为基准，在同一24 h范围内比较T=3、6、12、24时的聚合模型和逐时模型。开始前，将参数脚本恢复为Case 5设置，并执行：

```matlab
run_temporal_scalability_analysis;
```

入口脚本中的`Period_Counts`指定时间尺度。程序按时间块平均负荷和风电曲线，并换算最小开停机时段数；同一时间尺度的两种模型共用输入和两阶段求解设置。

`functions/case_study/IV-C/`保留三个函数：`run_multiple_snapshot_temporal_scalability_scan.m`负责流程编排，`prepare_temporal_scalability_input.m`负责单个时间尺度的输入准备，`solve_temporal_scalability_point.m`负责单个对比点的两阶段求解与结果核验。汇总导出由编排文件内的局部函数逐点完成。

结果保存在`results/multiple_snapshot_temporal_scalability_时间戳/`。各T下按`aggregated/`、`periodwise/`及`stage_1/`、`stage_2/`分目录保存实际阶段结果，根目录保存参数副本、汇总MAT和CSV；工作区的`Summary_Table`与`Summary_File`分别记录汇总表和MAT位置。汇总中的`Stage_1_Result_File`、`Stage_2_Result_File`可用于定位归档来源。

汇总MAT仅保存`Summary_Table`和`Experiment`，分别记录各对比点的指标、状态与文件路径，以及时间尺度、模型类型和基准输入位置。完整`Result`只保存在阶段文件中，汇总不再嵌入结果副本。

绘制Fig. 8–9前，将相应阶段的结果副本按第3.3节的`Txx_AG/PW_1/2.mat`约定放入`results_for_case/IV-C/`。Manuscript求解时间采用各实际执行阶段的求解器时间之和；达到时间上限且未满足目标间隙的点，应结合最终MIP间隙解释。

### 4.4 SCC-SCR联合灵敏度分析

联合灵敏度分析采用Case 5，默认计算6个SCC上限与6个SCR下限的36种组合：

- SCC上限：5.5、5.6、5.7、5.8、5.9、6.0 kA；
- SCR下限：2.3、2.6、2.7、2.8、2.9、3.0。

确认参数脚本已恢复为Case 5设置后，运行：

```matlab
run_scc_scr_joint_sensitivity_analysis;
```

扫描范围在入口脚本的`I_Limit_Values_kA`和`CSCR_Values`中修改，须保留基准组合(5.6 kA, 2.8)。`Execute_Full_Scan=true`执行规划求解，设为`false`时仅准备和核验输入、导出网格。默认输出目录为`results/multiple_snapshot_scc_scr_joint_sensitivity/`。

`functions/case_study/IV-D/`保留六个函数，分别负责扫描编排、基准准备、单点处理、汇总导出、配置核对及结果核对。输入、源代码或代码目录结构改变后，应使用新的运行目录；续算仅复用与当前清单及阶段文件校验值一致的记录。

重复使用相同`Run_Directory`可读取已校验的结果并续算。`Retry_Unfinished=true`时，重新尝试未达到目标间隙、无可行解或报错的点；修改源代码或输入参数后，应使用新的输出目录。

输出包括逐点参数和阶段结果、`joint_summary.mat`、`joint_summary.csv`及各指标矩阵CSV。矩阵行对应SCR下限，列对应SCC上限。核对完成后，将第3.3节列出的五个CSV一并复制到`results_for_case/IV-D/`，用于Fig. 10绘图。

`joint_summary.mat`仅保存`Joint`，汇总表位于`Joint.Summary_Table`，不再同时保存顶层副本。公共来源清单与Case 5归档核对表分别集中保存在`manifest.mat`和`case5_reference_validation.mat`，`Joint`通过文件路径引用它们。各点续算MAT及每次尝试的历史记录只保存状态、文件引用和SHA-256校验值，不再嵌入完整参数与来源清单；逐点参数仍保存在对应JSON中，两个阶段仍分别保存完整`Result`。修改代码后须使用新的扫描目录，既有归档不自动改写。

### 4.5 Manuscript图件复现

准备好Manuscript归档后，运行`code/scripts/figure/for_paper/`中对应的脚本：

| 图件 | 脚本 | 内容 |
|------|------|------|
| Fig. 4  | `plot_fig4_security_metrics.m`           | 五组算例的最大逐时SCC与最小逐时SCR |
| Fig. 5  | `plot_fig5_selected_uc_schedules.m`      | Case 2、4、5在典型日2的指定同步机UC状态 |
| Fig. 6  | `plot_fig6_scc_conservatism_scatter.m`   | 聚合SCC上界与逐时SCC最大值的逐点比较 |
| Fig. 7  | `plot_fig7_scr_conservatism_scatter.m`   | 聚合SCR下界与逐时SCR最小值的逐点比较 |
| Fig. 8  | `plot_fig8_temporal_model_size.m`        | 不同时间尺度下的模型变量规模 |
| Fig. 9  | `plot_fig9_temporal_solution_time.m`     | 不同时间尺度下的两阶段求解器时间与最终MIP间隙 |
| Fig. 10 | `plot_fig10_joint_sensitivity_heatmap.m` | SCC-SCR联合灵敏度下的总年成本与GFM-ES配置 |

例如，复现Fig. 4和Fig. 10：

```matlab
plot_fig4_security_metrics;
plot_fig10_joint_sensitivity_heatmap;
```

这些入口只读取结果并生成图件，不启动规划求解。Fig. 4–9仅使用结果中的配置快照；Fig. 10只读取五个归档CSV。重复运行时覆盖同名FIG。

`code/scripts/figure/`下的入口统一为接受可选`Options`结构体、返回`Report`的函数。无参数调用使用默认路径；需要指定输入或输出时显式传入选项，例如：

```matlab
Report = plot_fig4_security_metrics(struct( ...
    'Input_Directory',fullfile(pwd,'results_for_case','IV-B'), ...
    'Output_Directory',fullfile(pwd,'figs','for_paper')));
```

所有入口均支持`Visible`与`Close_After_Save`，默认分别为`false`与`true`；保存的FIG在MATLAB中打开时正常显示。需要保留当前图窗供检查时，可传入`struct('Visible',true,'Close_After_Save',false)`。

### 4.6 详细运行图件

完成一次主规划求解后，可批量查看各风电场景和典型日的规划配置、调度、储能能量、线路负载与安全指标：

```matlab
run_all_scenarios_for_debug;
```

该入口在开始时确定`results/`根目录下最新的主规划结果，并将同一个结果文件显式传给各单图函数，使用其中的`CONF`配置快照，按场景写入`figs/for_debug/`。绘图无需启动Simulink。

需要指定结果文件或场景时，通过`Options`传入；`plot_04_security`还可指定`Typical_Day_Index`，留空时绘制全部典型日：

```matlab
Report = plot_02_operation(struct( ...
    'Result_File',Result_File,'Scenario_Index',1));
Batch_Report = run_all_scenarios_for_debug(struct('Result_File',Result_File));
```

设备理论图支持`Output_Directory`；设备验证重绘入口还支持`Result_File`，默认读取`results/equipment/GFL/`或`results/equipment/GFM/`中的对应验证归档。
