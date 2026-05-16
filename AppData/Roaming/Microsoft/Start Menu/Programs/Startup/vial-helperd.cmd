@echo off
setlocal

set "LAUNCHER=%LOCALAPPDATA%\Programs\vial-helper\run-hidden.ps1"
set "LOGDIR=%USERPROFILE%\.config"
set "LOGFILE=%LOGDIR%\vial-helperd-startup.log"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
echo [%date% %time%] Starting vial-helperd>>"%LOGFILE%"

if not exist "%LAUNCHER%" (
  echo [%date% %time%] ERROR: launcher not found at "%LAUNCHER%">>"%LOGFILE%"
  exit /b 1
)

start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%LAUNCHER%"
echo [%date% %time%] vial-helperd launch requested>>"%LOGFILE%"
exit /b 0
