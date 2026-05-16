@echo off
setlocal

set "SCOOP_SHIMS=%USERPROFILE%\scoop\shims"
set "KOMOREBI_START=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\komorebi.cmd"
set "VIAL_HELPER_PS=%LOCALAPPDATA%\Programs\vial-helper\run-hidden.ps1"
set "AHK_UNIVERSAL=%USERPROFILE%\.config\autohotkey\creative_macropad_universal.ahk"
set "AHK_ZBRUSH=%USERPROFILE%\.config\autohotkey\zbrush_macropad.ahk"
set "LOGDIR=%USERPROFILE%\.config"
set "LOGFILE=%LOGDIR%\restart-daemons.log"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
echo [%date% %time%] Restarting desktop daemons>>"%LOGFILE%"

set "PATH=%SCOOP_SHIMS%;%PATH%"

for %%P in (komorebi.exe whkd.exe vial-helperd.exe AutoHotkey64.exe AutoHotkey32.exe AutoHotkey.exe) do (
  taskkill /F /IM %%P >nul 2>&1
)

timeout /T 1 /NOBREAK >nul

if exist "%VIAL_HELPER_PS%" (
  start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%VIAL_HELPER_PS%"
  echo [%date% %time%] Started vial-helperd>>"%LOGFILE%"
) else (
  echo [%date% %time%] WARN: vial-helper launcher not found at "%VIAL_HELPER_PS%">>"%LOGFILE%"
)

if exist "%AHK_UNIVERSAL%" (
  start "" "%AHK_UNIVERSAL%"
  echo [%date% %time%] Started creative_macropad_universal.ahk>>"%LOGFILE%"
) else (
  echo [%date% %time%] WARN: missing "%AHK_UNIVERSAL%">>"%LOGFILE%"
)

if exist "%AHK_ZBRUSH%" (
  start "" "%AHK_ZBRUSH%"
  echo [%date% %time%] Started zbrush_macropad.ahk>>"%LOGFILE%"
) else (
  echo [%date% %time%] WARN: missing "%AHK_ZBRUSH%">>"%LOGFILE%"
)

if exist "%KOMOREBI_START%" (
  call "%KOMOREBI_START%"
  echo [%date% %time%] Restarted komorebi stack with code %ERRORLEVEL%>>"%LOGFILE%"
) else (
  echo [%date% %time%] WARN: komorebi startup script not found at "%KOMOREBI_START%">>"%LOGFILE%"
)

exit /b 0
