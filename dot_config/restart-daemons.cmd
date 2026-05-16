@echo off
setlocal

call "%USERPROFILE%\.config\stop-daemons.cmd"
timeout /T 1 /NOBREAK >nul
call "%USERPROFILE%\.config\start-daemons.cmd"
exit /b %ERRORLEVEL%
