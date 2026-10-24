@echo off
setlocal
call "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\vial-helperd.cmd"
call "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\zmk-helperd.cmd"
call "%USERPROFILE%\.config\start-autohotkey.cmd"
powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%USERPROFILE%\.config\desktop-customization\komorebi-support\Start-DesktopWM.ps1"
exit /b %ERRORLEVEL%
