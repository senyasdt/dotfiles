@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Use-SmoothMotion.ps1" -Mode Trial
if errorlevel 1 pause
