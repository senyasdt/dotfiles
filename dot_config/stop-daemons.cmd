@echo off
setlocal

set "LOGDIR=%USERPROFILE%\.config"
set "LOGFILE=%LOGDIR%\stop-daemons.log"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
echo [%date% %time%] Stopping desktop daemons>>"%LOGFILE%"

for %%P in (yasb.exe komorebi.exe whkd.exe vial-helperd.exe AutoHotkey64.exe AutoHotkey32.exe AutoHotkey.exe) do (
  taskkill /F /IM %%P >nul 2>&1
  echo [%date% %time%] Stop requested for %%P>>"%LOGFILE%"
)

schtasks /End /TN "Vial Layer Daemon" >nul 2>&1
echo [%date% %time%] Stop requested for scheduled task Vial Layer Daemon>>"%LOGFILE%"

exit /b 0
