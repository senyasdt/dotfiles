@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Switch-Layout.ps1" -Mode Scrolling
if errorlevel 1 pause
