@echo off
setlocal
set "FM2_SKIP_INTRO=1"
set "FM2_CONTENT_ROOT=%~dp0content-packages"
set "FM2_BUILD=%~dp0fm2\out\build\win-amd64-release"

if not exist "%FM2_BUILD%\fm2.exe" (
  echo FM2 has not been built. Follow the build instructions in README.md.
  exit /b 1
)

if not exist "%~dp0extracted\default.xex" (
  echo Missing extracted\default.xex. Supply files from your own legal disc dump.
  exit /b 1
)

cd /d "%FM2_BUILD%"
fm2.exe --game_data_root="%~dp0extracted"
