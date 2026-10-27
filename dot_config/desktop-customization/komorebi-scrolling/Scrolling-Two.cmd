@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Switch-Layout.ps1" -Mode Scrolling -Columns 2 -Peek 180
if errorlevel 1 pause
