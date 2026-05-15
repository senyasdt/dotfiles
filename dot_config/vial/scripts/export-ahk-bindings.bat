@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "EXPORT_SCRIPT=%SCRIPT_DIR%export_ahk_bindings.py"
set "AHK_DIR=%USERPROFILE%\.config\autohotkey"

echo.
echo ========================================
echo  Vial Helper - AHK bindings export
echo ========================================
echo.

if not exist "%EXPORT_SCRIPT%" (
    echo [ERROR] Export script was not found:
    echo %EXPORT_SCRIPT%
    echo.
    pause
    exit /b 1
)

if not exist "%AHK_DIR%" (
    echo [ERROR] AutoHotkey config directory was not found:
    echo %AHK_DIR%
    echo.
    pause
    exit /b 1
)

where python >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Python was not found in PATH.
    echo.
    pause
    exit /b 1
)

echo Source AHK directory:
echo   %AHK_DIR%
echo.

python "%EXPORT_SCRIPT%" "%AHK_DIR%"
if errorlevel 1 (
    echo.
    echo [ERROR] AHK bindings export failed.
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================
echo  Export complete
echo ========================================
echo.
echo Output:
echo   %APPDATA%\vial-helper\ahk_bindings.json
echo.
pause
