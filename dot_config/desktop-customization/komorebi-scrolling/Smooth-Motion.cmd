@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Use-SmoothMotion.ps1" -Mode Strip
if errorlevel 1 pause
