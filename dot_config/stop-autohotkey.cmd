@echo off
setlocal

set "LOGDIR=%USERPROFILE%\.config"
set "LOGFILE=%LOGDIR%\stop-autohotkey.log"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
echo [%date% %time%] Stopping AutoHotkey from YASB>>"%LOGFILE%"

for %%P in (AutoHotkey64.exe AutoHotkey32.exe AutoHotkey.exe) do (
  taskkill /F /IM %%P >nul 2>&1
  echo [%date% %time%] Stop requested for %%P>>"%LOGFILE%"
)

exit /b 0
