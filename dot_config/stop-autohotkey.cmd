@echo off
powershell.exe -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "%USERPROFILE%\.config\desktop-customization\script-launcher\Manage.ps1" -Action Disable
exit /b %ERRORLEVEL%
