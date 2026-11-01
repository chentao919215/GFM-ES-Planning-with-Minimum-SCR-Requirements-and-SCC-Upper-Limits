# 装备级初始化、整定与验证

本模块提供单机GFL、GFM模型的初始化、控制器整定、端口与状态验证，以及设备理论特性绘图。该模块用于补充验证，复现Manuscript中的规划算例及Fig. 4–10无需运行本模块。环境依赖与运行准备见[项目主说明](../README.md)。

**本文中的路径均相对于项目根目录，以下MATLAB命令也在项目根目录下执行。**

## 1. 模型与初始化

设备级只维护以下两个平均模型，均位于`simulink/models/`：

| 模型 | 控制结构 | 初始化入口 |
|------|----------|------------|
| `Grid_Following_Inverters.slx` | PLL、功率外环、电流内环、LVRT附加无功与无功优先限流 | `initialize_gfl_model` |
| `Grid_Forming_Inverters.slx`   | 下垂、电压外环、电流内环、虚拟阻抗触发与锁存、恢复退出及重新武装 | `initialize_gfm_model` |

两个初始化脚本分别集中展示参数输入、派生量计算、一致性检查和参数发布，当前设计设置关闭打印和绘图，不清理调用方工作区。GFL显式构造LCL与设计输入，直接调用电流环函数；GFM原始物理参数和设计设置由`get_gfm_parameter_inputs.m`提供，初始化脚本先派生实际L2，再依次调用内外环函数。整定中间量保留在函数工作区，不使用脚本调用或工作区覆盖变量传参。设备控制验证使用60 MVA、38.5 kV设备基准；系统规划使用100 MVA、135 kV系统基准及30 MW/60 MWh储能模块。设备模型用于检验标幺端口特性和控制逻辑，不是IEEE-30系统的时域模型。GFM残余电抗与虚拟电抗由系统参数JSON换算回设备基准。

GFL与GFM的abc/dq电流均为峰值量。`I_base_rms`表示额定线电流有效值，`I_base_peak=sqrt(2)*I_base_rms`用于dq电流；GFL模型直接使用的`I_base`接口等于`I_base_peak`，GFM仅发布明确的有效值与峰值基准。GFL验证同时从瞬时三相电流计算有效值，独立核对两种电流标幺值。比较设备验证结果时，应核对归档中的参数快照。

## 2. 控制器整定

三个函数位于`code/functions/equipment/tuning/`，统一采用给定Kp和目标交越频率、计算Ki、校核后返回PI的方式，没有默认物理参数、目标或设计选项。调用方须提供LCL的`L1/R_L1/Cf/R_C/L2/R_L2/f`字段（SI单位）及全部设计字段；目标频率不等同于完整Simulink模型的闭环带宽。第一输出为控制器参数，第二输出`Diagnostics`保存对象、闭环、极点和裕度等结果。打印与绘图由显式输入开关控制；相位裕度下限也是调用方给定的验收要求，不是固定Kp后仍能独立保证的整定目标。

| 函数 | 输入 | 当前初始化采用的设计输入 |
|------|------|------|
| `tune_gfl_current_loop` | `LCL, Design`              | 95 Hz、Kp=5；在GFL初始化脚本中维护 |
| `tune_gfm_current_loop` | `LCL, Design`              | 200 Hz、Kp=5；在GFM参数入口中维护 |
| `tune_gfm_voltage_loop` | `LCL, CurrentLoop, Design` | 48.6 Hz、Kp=0.013；使用上一步实际电流PI |

设计输入中的`MinimumPhaseMarginDeg`当前显式取35度，`ShowRGAPlots/ShowValidationPlots/Verbose`显式关闭；GFM还明确给出前馈和dq解耦配置。Ki按标称d轴通道在目标频率处的单位开环幅值条件计算，电压环另外检查同一实际LCL的十阶闭环。缺少输入、Kp不可解、裕度不足或闭环不稳定时直接报错，不回退到固定PI。当前GFM电压设计沿用Kp=0.013，将目标设为已校核的48.6 Hz，所得Ki约0.009242；50 Hz/Kp=0.013的组合不能通过实际LCL校核。旧归档中的Ki=0.01应按其参数快照解释。

GFM的L2由初始化脚本按`X_res_device_pu*Z_base/(2*pi*f0)`派生，当前约3.931790 mH，并同时用于整定、完整LCL校核与仿真，不再保留0.6 mH的标称副本。十阶模型不包含外网、下垂、虚拟阻抗投切及PWM/测量延迟的全部动态，仍须结合Simulink工况验证。例如，初始化后可用相同输入取得完整诊断：

```matlab
initialize_gfl_model;
[CL_Check, Current_Diagnostics] = tune_gfl_current_loop(GFL_LCL, GFL_Current_Design);
initialize_gfm_model;
[VL_Check, Voltage_Diagnostics] = tune_gfm_voltage_loop( ...
    GFM_LCL, GFM_CL, GFM_Inherited.VoltageLoopDesign);
```

## 3. 验证入口

| 验证入口 | 用途 |
|----------|------|
| `run_gfl_lvrt_validation`     | 扫描残余电压，比较实测电流、端口等值与独立三相有效值；结果保存后运行`plot_gfl_lvrt_validation`绘图 |
| `run_gfl_scr_boundary_scan`   | 在有限电网阻抗下，按指定仿真窗口的收敛判据搜索SCR边界 |
| `run_gfm_vi_state_validation` | 检查虚拟阻抗触发、锁存、恢复退出与重新武装，并绘图 |
| `run_gfm_vi_port_validation`  | 比较限流端口理论曲线与准稳态仿真点，并绘图 |

GFL的两类验证使用同一个模型。模型默认启用三相电源内部的纯感性电网阻抗，`Lg=Vg^2/(S_base*SCR)/(2*pi*f)`，用于弱网与SCR扫描。LVRT端口验证临时关闭电源内部阻抗，以独立设置端口电压，结束后恢复设置。SCR扫描临时启用内部阻抗，仿真或信号提取错误会立即报错，不会当作失稳样本参与边界搜索。得到的是指定工况、窗口和阈值下的仿真收敛边界，不替代论文采用的SCR安全下限。

GFM保留顶层有限RL电网支路。外部电源默认依次施加1.00、0.30、1.00 p.u.，每段4 s。`GFM_GridSource.CaseA/B/C.SourceVoltage_pu`表示外部电源指令；实测PCC电压受电网阻抗和变流器影响，不能与指令等同。状态验证以实测PCC电压、电流和状态记录验收，并扫描5/10/20 ms的恢复与重新武装确认时间。验收失败会保存检查结果，并由运行入口报告失败。

例如：

```matlab
run_gfl_lvrt_validation;
plot_gfl_lvrt_validation;
run_gfl_scr_boundary_scan;
```

四个验证入口均将本次选项、主验证过程和辅助函数放在同一个文件中。修改脚本顶部的`Validation_Options`后运行，例如将GFL电压子集设置为`struct('Source_Voltages_pu',[0.9 0.6 0.2])`。GFL电压扫描、GFM端口和状态验证支持`Result_Directory`指定数值结果目录。主验证过程保留为文件内局部函数，结束或报错时恢复临时设置；最终结果返回脚本工作区。

## 4. 结果与绘图

数值结果与图件使用以下目录和文件名：

| 验证 | 数值结果 | 图件目录 |
|------|----------|----------|
| GFL LVRT | `results/equipment/GFL/GFL_LVRT_Validation_Result.mat` | `figs/equipment/GFL/` |
| GFM端口  | `results/equipment/GFM/GFM_VI_Port_Characteristic_Validation_Result.mat` | `figs/equipment/GFM/` |
| GFM状态  | `results/equipment/GFM/GFM_VI_State_Validation_Result.mat` | `figs/equipment/GFM/` |

SCR边界扫描结果保留在脚本工作区。SG仅绘制理论特性，不生成数值结果归档。七个设备绘图入口如下，均仅保存FIG，图中文字使用英文，配色与Manuscript图件一致：

| 设备 | 绘图入口 | 内容 |
|------|----------|------|
| GFL | `plot_gfl_lvrt_characteristic`         | LVRT附加无功电流分段特性 |
| GFL | `plot_gfl_lvrt_validation`             | 从LVRT数值归档绘制端口验证图 |
| GFM | `plot_gfm_vi_limited`                  | 虚拟阻抗限流的两状态端口理论曲线 |
| GFM | `plot_gfm_vi_unlimited`                | 未限流端口理论曲线及低电压外推 |
| GFM | `run_gfm_vi_port_plot`                 | 从端口数值归档重新绘图 |
| GFM | `run_gfm_vi_state_plot`                | 从状态数值归档重新绘图 |
| SG  | `plot_sg_short_circuit_characteristic` | 初始对称短路电流理论曲线，写入`figs/equipment/SG/` |

GFM验证入口与独立绘图入口共用端口、状态绘图函数；状态图从当前`ValidationResult.SelectedResult.Data`读取电压、电流，并使用`SelectedResult.Transitions`中的已记录跃迁时刻和方向，重新绘图不需要运行Simulink。状态绘图函数只返回图窗句柄。理论图与端口验证共用`calculate_gfm_port_current.m`。旧目录中的历史结果和图件保留原位，新入口不回退读取旧路径或旧信号格式；需要当前归档时重新运行验证。

## 5. 模型回调与生成目录

两份模型的`InitFcn`已保存添加函数路径并调用`initialize_equipment_model_from_callback`的代码，模型名、设备族与初始化脚本的对应关系直接在该函数中维护。初始化脚本将设备族和参数变量清单登记到基础工作区。首次运行、切换设备族或模型变量缺失时执行初始化脚本；同族参数完整时保留扫描中的显式工况覆盖。修改参数源后，重新执行对应初始化入口，再运行模型。新增模型或调整回调规则时，同步维护该函数中的映射及模型的`InitFcn`。缓存与代码生成文件写入`simulink/artifacts/`。

公共Simulink支持部分保留两个文件：

| 文件 | 职责 |
|------|------|
| `initialize_equipment_model_from_callback.m` | 模型映射、运行前检查参数、按需初始化并准备生成目录 |
| `configure_simulink_file_generation.m`       | 缓存与代码生成目录的统一配置 |

目录配置函数保留单参数调用，默认返回用于恢复原配置的清理对象；验证局部函数保留该对象直至结束。模型回调使用`configure_simulink_file_generation(Project_Root,'persistent')`，让直接运行模型时的目录配置持续有效。
