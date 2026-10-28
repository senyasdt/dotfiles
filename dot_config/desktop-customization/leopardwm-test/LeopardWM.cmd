@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Use-WindowManager.ps1" -Mode Leopard
if errorlevel 1 pause
