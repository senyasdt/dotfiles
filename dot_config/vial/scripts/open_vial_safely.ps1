#Requires -Version 5.1

$ErrorActionPreference = "Stop"

# ============================================================
# Paths
# ============================================================

$DaemonExe = Join-Path $env:LOCALAPPDATA "Programs\vial-helper\vial-helperd.exe"

$StartupDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
$DaemonVbs  = Join-Path $StartupDir "vial-helperd.vbs"

$VialHelperDir = Join-Path $env:APPDATA "vial-helper"
$RefreshFlag   = Join-Path $VialHelperDir "refresh-layout.flag"


# ============================================================
# Find Vial
# ============================================================

$VialCandidates = @(
    @(
        (Join-Path $env:LOCALAPPDATA "Programs\Vial\Vial.exe"),
        (Join-Path $env:ProgramFiles "Vial\Vial.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Vial\Vial.exe"),
        (Join-Path $env:LOCALAPPDATA "Vial\Vial.exe")
    ) | Where-Object { $_ -and (Test-Path $_) }
)

if ($VialCandidates.Count -eq 0) {
    throw "Vial.exe was not found. Add its path to VialCandidates in open_vial_safely.ps1."
}

$VialExe = $VialCandidates[0]


# ============================================================
# Validate daemon
# ============================================================

if (-not (Test-Path $DaemonExe)) {
    throw "vial-helperd.exe was not found: $DaemonExe"
}


# ============================================================
# Stop running daemon before opening Vial
# ============================================================

Get-Process "vial-helperd" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

Start-Sleep -Milliseconds 500


# ============================================================
# Open Vial and wait until exit
# ============================================================

$VialProcess = Start-Process `
    -FilePath $VialExe `
    -PassThru

$VialProcess.WaitForExit()

Start-Sleep -Milliseconds 700


# ============================================================
# Restart daemon hidden
# ============================================================

if (Test-Path $DaemonVbs) {
    Start-Process `
        -FilePath "wscript.exe" `
        -ArgumentList "`"$DaemonVbs`"" `
        -WindowStyle Hidden
}
else {
    Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList @(
            "-NoProfile",
            "-WindowStyle", "Hidden",
            "-Command",
            "& `"$DaemonExe`" --command run"
        ) `
        -WindowStyle Hidden
}

Start-Sleep -Seconds 1


# ============================================================
# Request fresh layout snapshot
# ============================================================

if (-not (Test-Path $VialHelperDir)) {
    New-Item -ItemType Directory -Path $VialHelperDir -Force | Out-Null
}

New-Item `
    -ItemType File `
    -Path $RefreshFlag `
    -Force |
    Out-Null
