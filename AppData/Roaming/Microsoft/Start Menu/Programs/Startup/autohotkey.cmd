@echo off
setlocal

set "AHK_EXE=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
set "AHK_UNIVERSAL=%USERPROFILE%\.config\autohotkey\creative_macropad_universal.ahk"
set "AHK_ZBRUSH=%USERPROFILE%\.config\autohotkey\zbrush_macropad.ahk"
set "LOGDIR=%USERPROFILE%\.config"
set "LOGFILE=%LOGDIR%\autohotkey-startup.log"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
echo [%date% %time%] Starting AutoHotkey scripts>>"%LOGFILE%"

if not exist "%AHK_EXE%" (
  echo [%date% %time%] ERROR: AutoHotkey64.exe not found at "%AHK_EXE%">>"%LOGFILE%"
  exit /b 1
)

if exist "%AHK_UNIVERSAL%" (
  start "" "%AHK_EXE%" "%AHK_UNIVERSAL%"
  echo [%date% %time%] Started creative_macropad_universal.ahk>>"%LOGFILE%"
) else (
  echo [%date% %time%] WARN: missing "%AHK_UNIVERSAL%">>"%LOGFILE%"
)

if exist "%AHK_ZBRUSH%" (
  start "" "%AHK_EXE%" "%AHK_ZBRUSH%"
  echo [%date% %time%] Started zbrush_macropad.ahk>>"%LOGFILE%"
) else (
  echo [%date% %time%] WARN: missing "%AHK_ZBRUSH%">>"%LOGFILE%"
)

exit /b 0
