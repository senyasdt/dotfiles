@echo off
setlocal

set "KOMOREBI_START=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\komorebi.cmd"
set "YASB_START=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\yasb.cmd"
set "VIAL_HELPER_START=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\vial-helperd.cmd"
set "AHK_START=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\autohotkey.cmd"
set "LOGDIR=%USERPROFILE%\.config"
set "LOGFILE=%LOGDIR%\start-daemons.log"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
echo [%date% %time%] Starting desktop daemons>>"%LOGFILE%"

if exist "%VIAL_HELPER_START%" (
  call "%VIAL_HELPER_START%"
  echo [%date% %time%] Started vial-helper stack with code %ERRORLEVEL%>>"%LOGFILE%"
) else (
  echo [%date% %time%] WARN: vial-helper startup script not found at "%VIAL_HELPER_START%">>"%LOGFILE%"
)

if exist "%AHK_START%" (
  call "%AHK_START%"
  echo [%date% %time%] Started AutoHotkey stack with code %ERRORLEVEL%>>"%LOGFILE%"
) else (
  echo [%date% %time%] WARN: AutoHotkey startup script not found at "%AHK_START%">>"%LOGFILE%"
)

if exist "%KOMOREBI_START%" (
  call "%KOMOREBI_START%"
  echo [%date% %time%] Started komorebi stack with code %ERRORLEVEL%>>"%LOGFILE%"
) else (
  echo [%date% %time%] WARN: komorebi startup script not found at "%KOMOREBI_START%">>"%LOGFILE%"
)

if exist "%YASB_START%" (
  call "%YASB_START%"
  echo [%date% %time%] Started YASB with code %ERRORLEVEL%>>"%LOGFILE%"
) else (
  echo [%date% %time%] WARN: YASB startup script not found at "%YASB_START%">>"%LOGFILE%"
)

exit /b 0
