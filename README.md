# GFM-ES安全配置优化项目

本项目面向高比例GFL-WG接入场景下的GFM-ES配置优化问题，目标是在统一优化框架中协调系统运行经济性、短路电流安全性与电压支撑强度。项目关注同步机启停状态、GFL-WG已接入状态以及GFM-ES投建决策之间的耦合关系，并通过SCC-SCR协同安全约束刻画不同设备在故障电流贡献和系统强度支撑方面的差异化作用。

## 最终目标

本科研项目的最终目标是建立一套面向不确定新能源接入场景的GFM-ES配置优化方法，主要包括:

1. 构建计及UC与GFM-ES投建决策的SCC-SCR协同安全约束配置框架，在同一优化模型中同时嵌入短路电流水平约束与电压支撑强度约束，实现经济性、安全性和系统强度之间的协调权衡。
2. 建立GFL-WG与GFM-ES在正常工况和故障工况下的等值模型，形成可嵌入优化模型的线性安全约束表达，为SCC与SCR协同约束提供可求解的数学建模基础。
3. 面向GFL-WG出力分布不确定且精确概率分布难以获取的情况，进一步构建分布鲁棒GFM-ES配置模型，用于优化GFM-ES的选址、定容与运行策略，提升配置方案在高比例GFL-WG场景下的安全性与鲁棒性。

## 当前进度

当前代码已完成确定性、单时刻的IEEE-30节点GFM-ES配置优化原型，主要进展如下:

- 已搭建主脚本`code/scripts/run_single_snapshot_planning.m`，能够完成参数生成、参数加载、网络构建、优化求解、结果打包、结果保存与摘要输出。
- 已实现已知GFL接入节点和候选GFM-ES节点下的规划模型，支持同步机启停、GFM-ES投建、节点功率平衡、线路潮流和机组出力约束。
- 已将经典SCR下限约束和短路电流水平约束嵌入优化模型，用于刻画GFL节点的系统强度需求和故障电流安全边界。
- 已通过阻抗矩阵重构与McCormick线性化约束，将安全约束转化为可由YALMIP与Gurobi求解的混合整数优化模型。
- 已对核心函数进行精简、拆分和注释整理，当前版本以“维持主脚本可跑通、减少冗余功能、保持建模逻辑清晰”为整理原则。

## 运行入口

主运行脚本为:

```text
code/scripts/run_single_snapshot_planning.m
```

运行主脚本时，会先执行:

```text
data/params/generate_single_snapshot_default_params.m
```

该参数脚本会生成:

```text
data/params/single_snapshot_default_params.json
```

随后主脚本调用`load_single_snapshot_case`读取该JSON参数文件，并进入网络构建、优化建模、求解与结果输出流程。

如需在自动化或后台场景中启动较长时间的求解任务，可以使用:

```text
code/scripts/start_single_snapshot_planning_longrun.m
```

## 参数维护

默认参数的源文件是:

```text
data/params/generate_single_snapshot_default_params.m
```

维护参数时，优先修改该脚本，而不是直接修改生成后的JSON文件。主脚本每次运行前都会重新执行参数生成脚本，因此可以避免“修改了参数源脚本但忘记刷新JSON文件”的问题。

## 项目结构

```text
code/
  scripts/        主运行脚本、路径解析与后台启动入口
  functions/      数据加载、网络构建、优化建模、安全约束与结果输出函数
data/
  params/         默认算例参数源脚本及生成后的JSON参数文件
docs/             项目说明与MATLAB环境排错记录
results/          优化运行结果输出目录
```

## 环境说明

本项目依赖MATLAB运行环境，并需要MATPOWER、YALMIP和Gurobi等工具链支持。若从自动化进程或后台任务启动MATLAB时遇到启动失败，可参考:

```text
docs/matlab_environment_note.md
```

该文档只用于环境排错，正常从MATLAB交互界面运行主脚本时通常不需要使用。

当前仓库对应的是完整研究框架中的确定性单时刻建模与求解阶段；后续工作可在此基础上继续扩展多时段UC、GFL-WG不确定性建模以及分布鲁棒GFM-ES配置模型。
