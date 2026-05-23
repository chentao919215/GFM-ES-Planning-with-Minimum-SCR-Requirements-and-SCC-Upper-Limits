# MATLAB environment reminder

When running MATLAB from this Codex workspace, set the temporary user
environment variables to match the actual sandbox account first.

The current MATLAB executable is:

```powershell
D:\matlab\r2024b\bin\matlab.exe
```

Use this prefix before MATLAB commands:

```powershell
$env:USERNAME='CodexSandboxOffline'
$env:USERPROFILE='C:\Users\CodexSandboxOffline'
$env:APPDATA='C:\Users\CodexSandboxOffline\AppData\Roaming'
$env:LOCALAPPDATA='C:\Users\CodexSandboxOffline\AppData\Local'
$env:TEMP='C:\Users\CodexSandboxOffline\AppData\Local\Temp'
$env:TMP='C:\Users\CodexSandboxOffline\AppData\Local\Temp'
```

Example:

```powershell
$env:USERNAME='CodexSandboxOffline'; $env:USERPROFILE='C:\Users\CodexSandboxOffline'; $env:APPDATA='C:\Users\CodexSandboxOffline\AppData\Roaming'; $env:LOCALAPPDATA='C:\Users\CodexSandboxOffline\AppData\Local'; $env:TEMP='C:\Users\CodexSandboxOffline\AppData\Local\Temp'; $env:TMP='C:\Users\CodexSandboxOffline\AppData\Local\Temp'; matlab -batch "disp(version)"
```

Reason: the process runs as `laptop-eorqogg9\codexsandboxoffline`, while
the default inherited variables may point to `C:\Users\AnYe`. MATLAB R2024b
can fail at startup with `System Error: File system inconsistency` when
these paths are mismatched.
