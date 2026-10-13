@echo off
setlocal
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 is required. Install it before opening FM2 Settings.
  pause
  exit /b 1
)
start "" pwsh.exe -NoProfile -STA -WindowStyle Hidden -File "%~dp0tools\Launch-Graphical.ps1" %*
