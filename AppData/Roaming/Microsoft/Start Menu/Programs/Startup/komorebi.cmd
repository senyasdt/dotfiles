@echo off
setlocal

set "SCOOP_SHIMS=%USERPROFILE%\scoop\shims"
set "KOMOREBIC=%USERPROFILE%\scoop\apps\komorebi\current\komorebic.exe"
set "CONFIG=%USERPROFILE%\komorebi.json"
set "LOGDIR=%USERPROFILE%\.config"
set "LOGFILE=%LOGDIR%\komorebi-startup.log"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
echo [%date% %time%] Starting komorebi startup>>"%LOGFILE%"

if not exist "%KOMOREBIC%" (
  echo [%date% %time%] ERROR: komorebic not found at "%KOMOREBIC%">>"%LOGFILE%"
  exit /b 1
)

set "PATH=%SCOOP_SHIMS%;%PATH%"

taskkill /F /IM whkd.exe >nul 2>&1
taskkill /F /IM komorebi.exe >nul 2>&1
timeout /T 1 /NOBREAK >nul

if exist "%CONFIG%" (
  "%KOMOREBIC%" start --whkd --clean-state -c "%CONFIG%" >>"%LOGFILE%" 2>&1
) else (
  "%KOMOREBIC%" start --whkd --clean-state >>"%LOGFILE%" 2>&1
)

echo [%date% %time%] komorebi startup finished with code %ERRORLEVEL%>>"%LOGFILE%"
exit /b %ERRORLEVEL%
