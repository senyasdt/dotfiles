@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Use-Native.ps1" -Mode Stable
if errorlevel 1 pause
