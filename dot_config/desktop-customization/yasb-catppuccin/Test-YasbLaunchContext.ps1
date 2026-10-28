param(
    [string]$LauncherPath,
    [Parameter(Mandatory=$true)][string]$TestRoot
)
$ErrorActionPreference='Stop'
if(!$LauncherPath){$LauncherPath=Join-Path $PSScriptRoot 'Start-Yasb.ps1'}
$suite=Join-Path $TestRoot ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $suite -Force|Out-Null

function Test-Case([string]$Name,[string]$Selection,[bool]$ClientMissing,[string]$ExpectedError){
    $caseRoot=Join-Path $suite $Name
    $profile=Join-Path $caseRoot 'yasb-catppuccin'
    $state=Join-Path $caseRoot 'leopardwm-test\runtime'
    New-Item -ItemType Directory -Path $profile,$state -Force|Out-Null
    $launcher=Join-Path $profile 'Start-Yasb.ps1'
    Copy-Item -LiteralPath $LauncherPath -Destination $launcher
    if($Selection){[IO.File]::WriteAllText((Join-Path $state 'selection.json'),$Selection)}
    # Stub only executable existence and process creation. Run the actual
    # launcher with -CheckOnly; no real programs or IPC calls are launched.
    function Test-Path {
        param([string]$LiteralPath)
        if($LiteralPath.EndsWith('\YASB\yasb.exe',[StringComparison]::OrdinalIgnoreCase)){return $true}
        if($LiteralPath.EndsWith('\komorebi\current\komorebic.exe',[StringComparison]::OrdinalIgnoreCase)){return !$ClientMissing}
        Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath
    }
    function New-Object {
        param([Parameter(Position=0)][string]$TypeName)
        if($TypeName -eq 'Diagnostics.Process'){throw 'KomorebiProbeRequested'}
        Microsoft.PowerShell.Utility\New-Object -TypeName $TypeName
    }
    $failure=$null
    try{& $launcher -CheckOnly}catch{$failure=$_.Exception.Message}
    if($ExpectedError){
        if(!$failure -or $failure -notmatch $ExpectedError){throw ($Name+': expected '+$ExpectedError+', got '+$failure)}
    }elseif($failure){throw ($Name+': '+$failure)}
    Write-Output ('PASS: '+$Name)
}

Test-Case 'LeopardNoKomorebiClient' '{"enabled":true}' $true ''
Test-Case 'LeopardNoKomorebiIpc' '{"enabled":true}' $false ''
Test-Case 'KomorebiStillChecksIpc' '{"enabled":false}' $false 'KomorebiProbeRequested'
Test-Case 'NoSelectionStillChecksIpc' '' $false 'KomorebiProbeRequested'
Test-Case 'KomorebiMissingClient' '{"enabled":false}' $true 'managed Scoop komorebic'
Test-Case 'MalformedSelectionFailsClosed' '{invalid' $false 'JSON|Invalid object'
