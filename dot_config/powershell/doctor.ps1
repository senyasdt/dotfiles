$ErrorActionPreference = "Stop"

param(
    [switch]$Fix
)

function Get-ProcessInfo {
    param([Parameter(Mandatory = $true)][string]$Name)

    Get-CimInstance Win32_Process -Filter "Name = '$Name'" -ErrorAction SilentlyContinue
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "==> $Title" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[ok] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[warn] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "[err] $Message" -ForegroundColor Red
}

function Start-VialHelperDaemon {
    param([string]$BinaryPath, [string]$RunnerPath)

    if (Test-Path -LiteralPath $RunnerPath) {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $RunnerPath
        Start-Sleep -Milliseconds 800
    }

    $proc = Get-ProcessInfo -Name "vial-helperd.exe" |
        Where-Object { $_.ExecutablePath -eq $BinaryPath -and $_.CommandLine -match '--command run' }

    if ($proc) {
        return $true
    }

    if (Test-Path -LiteralPath $BinaryPath) {
        Start-Process -FilePath $BinaryPath -ArgumentList "--command run" -WindowStyle Hidden
        Start-Sleep -Seconds 2
    }

    $proc = Get-ProcessInfo -Name "vial-helperd.exe" |
        Where-Object { $_.ExecutablePath -eq $BinaryPath -and $_.CommandLine -match '--command run' }

    return [bool]$proc
}

function Restart-Yasb {
    $yasbPath = "C:\Program Files\YASB\yasb.exe"
    Get-Process yasb -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    if (Test-Path -LiteralPath $yasbPath) {
        Start-Process -FilePath $yasbPath
        Start-Sleep -Seconds 2
        return [bool](Get-Process yasb -ErrorAction SilentlyContinue)
    }

    return $false
}

$helperExe = Join-Path $env:LOCALAPPDATA "Programs\vial-helper\vial-helperd.exe"
$helperRunner = Join-Path $env:LOCALAPPDATA "Programs\vial-helper\run-hidden.ps1"
$helperDir = Join-Path $env:APPDATA "vial-helper"
$statePath = Join-Path $helperDir "state.json"
$layoutPath = Join-Path $helperDir "layout.json"
$yasbConfig = Join-Path $HOME ".config\yasb\config.yaml"
$taskName = "Vial Helper Daemon"

$issues = New-Object System.Collections.Generic.List[string]

Write-Section "Paths"
Write-Host "helper exe   : $helperExe"
Write-Host "runner       : $helperRunner"
Write-Host "state.json   : $statePath"
Write-Host "layout.json  : $layoutPath"
Write-Host "yasb config  : $yasbConfig"

Write-Section "Processes"
$helperProc = Get-ProcessInfo -Name "vial-helperd.exe" |
    Where-Object { $_.ExecutablePath -eq $helperExe -and $_.CommandLine -match '--command run' } |
    Select-Object -First 1
$yasbProc = Get-ProcessInfo -Name "yasb.exe" | Select-Object -First 1

if ($helperProc) {
    Write-Ok "vial-helperd is running (PID $($helperProc.ProcessId))"
}
else {
    Write-Err "vial-helperd is not running"
    $issues.Add("vial-helperd is not running")
}

if ($yasbProc) {
    Write-Ok "yasb is running (PID $($yasbProc.ProcessId))"
}
else {
    Write-Err "yasb is not running"
    $issues.Add("yasb is not running")
}

Write-Section "Autostart"
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    $taskInfo = $task | Get-ScheduledTaskInfo
    Write-Ok "Scheduled Task exists"
    Write-Host "state        : $($task.State)"
    Write-Host "last run     : $($taskInfo.LastRunTime)"
    Write-Host "last result  : $($taskInfo.LastTaskResult)"
}
else {
    Write-Warn "Scheduled Task '$taskName' not found"
    $issues.Add("Scheduled Task '$taskName' not found")
}

Write-Section "Files"
if (Test-Path -LiteralPath $statePath) {
    $stateItem = Get-Item -LiteralPath $statePath
    Write-Ok "state.json exists"
    Write-Host "updated      : $($stateItem.LastWriteTime)"
    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        Write-Host "layer        : $($state.label) (top=$($state.top))"
        Write-Host "effective    : $($state.effective)"
    }
    catch {
        Write-Err "state.json is unreadable: $($_.Exception.Message)"
        $issues.Add("state.json is unreadable")
    }
}
else {
    Write-Err "state.json missing"
    $issues.Add("state.json missing")
}

if (Test-Path -LiteralPath $layoutPath) {
    $layoutItem = Get-Item -LiteralPath $layoutPath
    Write-Ok "layout.json exists"
    Write-Host "updated      : $($layoutItem.LastWriteTime)"
}
else {
    Write-Warn "layout.json missing"
    $issues.Add("layout.json missing")
}

Write-Section "Helper Status"
if (Test-Path -LiteralPath $helperExe) {
    try {
        & $helperExe --command status
        Write-Host "---"
        & $helperExe --command doctor
    }
    catch {
        Write-Err "vial-helper status/doctor failed: $($_.Exception.Message)"
        $issues.Add("vial-helper status/doctor failed")
    }
}
else {
    Write-Err "vial-helperd.exe not found"
    $issues.Add("vial-helperd.exe not found")
}

if ($Fix) {
    Write-Section "Fix"

    $helperStarted = $false
    if (-not $helperProc) {
        if (Start-VialHelperDaemon -BinaryPath $helperExe -RunnerPath $helperRunner) {
            Write-Ok "Started vial-helperd"
            $helperStarted = $true
        }
        else {
            Write-Err "Failed to start vial-helperd"
            $issues.Add("Failed to start vial-helperd")
        }
    }

    if (-not $yasbProc -or $helperStarted) {
        if (Restart-Yasb) {
            Write-Ok "Restarted YASB"
        }
        else {
            Write-Err "Failed to restart YASB"
            $issues.Add("Failed to restart YASB")
        }
    }

    if (Test-Path -LiteralPath $statePath) {
        Write-Host "---"
        Get-Content -LiteralPath $statePath -Raw
    }
}

Write-Section "Result"
if ($issues.Count -eq 0) {
    Write-Ok "No problems detected"
    exit 0
}

$issues | ForEach-Object { Write-Warn $_ }
exit 1
