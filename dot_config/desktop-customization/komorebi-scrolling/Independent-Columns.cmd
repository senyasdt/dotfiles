@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Use-Native.ps1" -Mode Independent
if errorlevel 1 pause
