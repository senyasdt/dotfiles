@echo off
setlocal
call "%USERPROFILE%\.config\stop-autohotkey.cmd"
"%USERPROFILE%\scoop\apps\komorebi\current\komorebic.exe" stop --whkd
if errorlevel 1 exit /b %ERRORLEVEL%
taskkill /F /IM vial-helperd.exe >nul 2>&1
taskkill /F /IM zmk-helperd.exe >nul 2>&1
exit /b 0
