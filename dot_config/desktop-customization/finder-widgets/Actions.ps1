param(
    [ValidateSet('AhkStart','AhkStop','AhkRestart','VialStart','VialStop','VialRestart','ZmkStart','ZmkStop','ZmkRestart','KomorebiStart','KomorebiStop','KomorebiRestart')]
    [string]$Action
)
$ErrorActionPreference = 'Stop'
$profileRoot = [Environment]::GetFolderPath('UserProfile')
$startup = [Environment]::GetFolderPath('Startup')
$currentSession = [Diagnostics.Process]::GetCurrentProcess().SessionId
function Stop-SessionProcesses([string[]]$Names) {
    Get-Process -Name $Names -ErrorAction SilentlyContinue | Where-Object SessionId -EQ $currentSession | Stop-Process -Force
}
function Start-Cmd([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing launcher: $Path" }
    Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + (Join-Path $profileRoot '.config\run-hidden.vbs') + '" "' + $Path + '"') -WindowStyle Hidden
}
try {
    switch -Regex ($Action) {
        '^Ahk' {
            $manager=Join-Path (Split-Path $PSScriptRoot -Parent) 'script-launcher\Manage.ps1'
            $operation=if($Action -eq 'AhkStop'){'Disable'}elseif($Action -eq 'AhkRestart'){'Restart'}else{'Enable'}
            & $manager -Action $operation
        }
        '^Vial' {
            if ($Action -ne 'VialStart') { Stop-SessionProcesses @('vial-helperd') }
            if ($Action -ne 'VialStop') { Start-Cmd (Join-Path $startup 'vial-helperd.cmd') }
        }
        '^Zmk' {
            if ($Action -ne 'ZmkStart') { Stop-SessionProcesses @('zmk-helperd') }
            if ($Action -ne 'ZmkStop') { Start-Cmd (Join-Path $startup 'zmk-helperd.cmd') }
        }
        '^Komorebi' {
            $launcher = Join-Path (Split-Path $PSScriptRoot -Parent) 'komorebi-support\Start-DesktopWM.ps1'
            if ($Action -eq 'KomorebiStop') { & $launcher -Stop }
            elseif ($Action -eq 'KomorebiRestart') { & $launcher -Restart }
            else { & $launcher }
        }
    }
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Finder Widgets', 'OK', 'Warning')
    exit 1
}
