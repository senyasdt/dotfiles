@echo off
setlocal
set "EXE=%LOCALAPPDATA%\Programs\zmk-yasb\zmk-helperd.exe"
set "CONFIG=%APPDATA%\zmk-yasb\config.json"
set "LOGDIR=%USERPROFILE%\.config"
set "LOGFILE=%LOGDIR%\zmk-helperd-startup.log"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
echo [%date% %time%] Starting zmk-helperd>>"%LOGFILE%"
if not exist "%EXE%" (
  echo [%date% %time%] ERROR: zmk-helperd.exe not found at "%EXE%">>"%LOGFILE%"
  exit /b 1
)
start "" /MIN "%EXE%" -config "%CONFIG%"
echo [%date% %time%] zmk-helperd launch requested>>"%LOGFILE%"
exit /b 0
