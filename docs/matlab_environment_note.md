# MATLAB环境说明

本文档用于记录MATLAB在自动化或后台进程中启动失败时的环境变量检查方法。正常从MATLAB交互界面运行主脚本时，通常不需要使用本说明。

## 适用场景

如果MATLAB不是从桌面交互界面启动，而是由Codex、MCP、后台任务或其他自动化进程调用，Windows用户环境变量可能不完整，或指向了错误的用户目录。此时MATLAB可能在启动阶段失败，即使项目代码本身没有问题。

重点检查以下环境变量是否指向当前Windows用户:

```text
USERNAME
USERPROFILE
APPDATA
LOCALAPPDATA
TEMP
TMP
```

## PowerShell模板

可以先在PowerShell中重置这些变量，再测试MATLAB是否能够启动:

```powershell
$env:USERNAME = [Environment]::UserName
$env:USERPROFILE = [Environment]::GetFolderPath("UserProfile")
$env:APPDATA = [Environment]::GetFolderPath("ApplicationData")
$env:LOCALAPPDATA = [Environment]::GetFolderPath("LocalApplicationData")
$env:TEMP = [System.IO.Path]::GetTempPath().TrimEnd('\')
$env:TMP = $env:TEMP

matlab -batch "disp(version)"
```

如果本机MATLAB可执行文件不在系统路径中，需要改用本机实际的MATLAB路径。
