@echo off
setlocal
cd /d "%~dp0"
set "FM2_SKIP_INTRO=1"
python "I:\Projects\rexglue-heal\rexheal.py"
pause
