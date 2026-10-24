@echo off
powershell.exe -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "%USERPROFILE%\.config\desktop-customization\script-launcher\Manage.ps1" -Action Enable
exit /b %ERRORLEVEL%
