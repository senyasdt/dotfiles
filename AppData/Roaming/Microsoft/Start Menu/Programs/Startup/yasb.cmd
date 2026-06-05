@echo off
setlocal

set "SCOOP_SHIMS=%USERPROFILE%\scoop\shims"
set "KOMOREBIC=%USERPROFILE%\scoop\apps\komorebi\current\komorebic.exe"
set "YASB_EXE=%ProgramFiles%\YASB\yasb.exe"
set "LOGDIR=%USERPROFILE%\.config"
set "LOGFILE=%LOGDIR%\yasb-startup.log"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
echo [%date% %time%] Starting YASB>>"%LOGFILE%"

set "PATH=%SCOOP_SHIMS%;%PATH%"

if not exist "%YASB_EXE%" (
  echo [%date% %time%] ERROR: yasb.exe not found at "%YASB_EXE%">>"%LOGFILE%"
  exit /b 1
)

tasklist /FI "IMAGENAME eq yasb.exe" 2>nul | find /I "yasb.exe" >nul
if %ERRORLEVEL% EQU 0 (
  echo [%date% %time%] YASB already running>>"%LOGFILE%"
  exit /b 0
)

if exist "%KOMOREBIC%" (
  call :wait_for_komorebi
) else (
  echo [%date% %time%] WARN: komorebic not found at "%KOMOREBIC%", starting YASB without readiness check>>"%LOGFILE%"
)

:launch_yasb
start "" "%YASB_EXE%"
echo [%date% %time%] YASB launch requested>>"%LOGFILE%"
exit /b 0

:wait_for_komorebi
setlocal EnableDelayedExpansion
for /L %%I in (1,1,15) do (
  "%KOMOREBIC%" state >nul 2>&1
  if !ERRORLEVEL! EQU 0 (
    echo [%date% %time%] Komorebi is ready for YASB>>"%LOGFILE%"
    endlocal & exit /b 0
  )
  timeout /T 1 /NOBREAK >nul
)
echo [%date% %time%] WARN: komorebi was not ready before YASB launch>>"%LOGFILE%"
endlocal & exit /b 0
