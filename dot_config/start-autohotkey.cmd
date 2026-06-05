@echo off
setlocal

set "AHK_START=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\autohotkey.cmd"
set "LOGDIR=%USERPROFILE%\.config"
set "LOGFILE=%LOGDIR%\start-autohotkey.log"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
echo [%date% %time%] Starting AutoHotkey from YASB>>"%LOGFILE%"

if exist "%AHK_START%" (
  call "%AHK_START%"
  echo [%date% %time%] Started AutoHotkey stack with code %ERRORLEVEL%>>"%LOGFILE%"
) else (
  echo [%date% %time%] WARN: AutoHotkey startup script not found at "%AHK_START%">>"%LOGFILE%"
)

exit /b 0
