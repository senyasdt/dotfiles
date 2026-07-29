@echo off
setlocal

set "AHK_EXE=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
set "AHK_MAIN=%USERPROFILE%\.config\autohotkey\creative_macropad.ahk"
set "AHK_TEXT_REPLACEMENTS=%USERPROFILE%\.config\autohotkey\zmk-text-replacements.ahk"
set "LOGDIR=%USERPROFILE%\.config"
set "LOGFILE=%LOGDIR%\autohotkey-startup.log"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
echo [%date% %time%] Starting AutoHotkey script>>"%LOGFILE%"

if not exist "%AHK_EXE%" (
  echo [%date% %time%] ERROR: AutoHotkey64.exe not found at "%AHK_EXE%">>"%LOGFILE%"
  exit /b 1
)

if exist "%AHK_MAIN%" (
  start "" "%AHK_EXE%" "%AHK_MAIN%"
  echo [%date% %time%] Started creative_macropad.ahk>>"%LOGFILE%"
) else (
  echo [%date% %time%] WARN: missing "%AHK_MAIN%">>"%LOGFILE%"
)

if exist "%AHK_TEXT_REPLACEMENTS%" (
  start "" "%AHK_EXE%" "%AHK_TEXT_REPLACEMENTS%"
  echo [%date% %time%] Started zmk-text-replacements.ahk>>"%LOGFILE%"
) else (
  echo [%date% %time%] WARN: missing "%AHK_TEXT_REPLACEMENTS%">>"%LOGFILE%"
)

exit /b 0
