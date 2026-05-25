# MATLAB environment reminder

If MATLAB is launched from a non-interactive automation process, make sure
the process environment points to a valid Windows user profile. MATLAB can
fail during startup when `USERNAME`, `USERPROFILE`, `APPDATA`,
`LOCALAPPDATA`, `TEMP`, or `TMP` point to a stale or mismatched account.

Example PowerShell template:

```powershell
$env:USERNAME = [Environment]::UserName
$env:USERPROFILE = [Environment]::GetFolderPath("UserProfile")
$env:APPDATA = [Environment]::GetFolderPath("ApplicationData")
$env:LOCALAPPDATA = [Environment]::GetFolderPath("LocalApplicationData")
$env:TEMP = [System.IO.Path]::GetTempPath().TrimEnd('\')
$env:TMP = $env:TEMP

matlab -batch "disp(version)"
```

Use the MATLAB executable and project paths that match the local machine.
