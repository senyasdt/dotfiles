@echo off
setlocal

set "LOGDIR=%USERPROFILE%\.config"
set "LOGFILE=%LOGDIR%\stop-daemons.log"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
echo [%date% %time%] Stopping desktop daemons>>"%LOGFILE%"

for %%P in (komorebi.exe whkd.exe vial-helperd.exe AutoHotkey64.exe AutoHotkey32.exe AutoHotkey.exe) do (
  taskkill /F /IM %%P >nul 2>&1
  echo [%date% %time%] Stop requested for %%P>>"%LOGFILE%"
)

exit /b 0
