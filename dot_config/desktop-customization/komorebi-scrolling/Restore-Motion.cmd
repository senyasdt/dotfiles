@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Use-SmoothMotion.ps1" -Mode Previous
if errorlevel 1 pause
