@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Use-WindowManager.ps1" -Mode Komorebi
if errorlevel 1 pause
