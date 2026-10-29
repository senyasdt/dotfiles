$ErrorActionPreference='Stop'
$executable=Join-Path $PSScriptRoot 'TechnicalAltGrLayoutGuard.exe'
if(-not(Test-Path -LiteralPath $executable)){throw 'Build the optional keyboard layout guard first (desktop.ps1 -IncludeLayoutGuard).'}
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
function Get-SessionGuards { @(Get-Process -Name TechnicalAltGrLayoutGuard -ErrorAction SilentlyContinue | Where-Object {$_.SessionId -eq $session}) }
$running=Get-SessionGuards
if(@($running|Where-Object {$_.Path -ine $executable}).Count){throw 'Keyboard layout guard is running from another folder; stop that copy explicitly before migrating.'}
if(-not $running.Count){
    Start-Process -FilePath $executable -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
    Start-Sleep -Milliseconds 300
}
if(-not @(Get-SessionGuards|Where-Object {$_.Path -ieq $executable}).Count){throw 'Keyboard layout guard did not remain running; check status.txt and events.log.'}
