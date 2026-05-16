@echo off
setlocal

set "YASB_EXE=%ProgramFiles%\YASB\yasb.exe"
set "LOGDIR=%USERPROFILE%\.config"
set "LOGFILE=%LOGDIR%\yasb-startup.log"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
echo [%date% %time%] Starting YASB>>"%LOGFILE%"

if not exist "%YASB_EXE%" (
  echo [%date% %time%] ERROR: yasb.exe not found at "%YASB_EXE%">>"%LOGFILE%"
  exit /b 1
)

tasklist /FI "IMAGENAME eq yasb.exe" 2>nul | find /I "yasb.exe" >nul
if %ERRORLEVEL% EQU 0 (
  echo [%date% %time%] YASB already running>>"%LOGFILE%"
  exit /b 0
)

start "" "%YASB_EXE%"
echo [%date% %time%] YASB launch requested>>"%LOGFILE%"
exit /b 0
