param([switch]$Restart,[switch]$Stop)
$ErrorActionPreference='Stop'
$profileRoot=[Environment]::GetFolderPath('UserProfile')
$desktopRoot=Split-Path $PSScriptRoot -Parent
$runtime=Join-Path $desktopRoot 'komorebi-runtime'
$data=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'komorebi'
function Resolve-Binary([string]$Name,[string]$Package) {
    $scoop=Join-Path $profileRoot ('scoop\apps\'+$Package+'\current\'+$Name+'.exe')
    if(Test-Path -LiteralPath $scoop){return $scoop}
    $command=Get-Command ($Name+'.exe') -ErrorAction SilentlyContinue
    if($command){return $command.Source}
    throw ('Missing executable: '+$Name)
}
$exe=Resolve-Binary 'komorebi' 'komorebi'
$client=Resolve-Binary 'komorebic' 'komorebi'
$whkd=Resolve-Binary 'whkd' 'whkd'
$settingsPath=Join-Path $PSScriptRoot 'settings.json'
$useJunction=$false
if(Test-Path -LiteralPath $settingsPath){$useJunction=[bool]((Get-Content -LiteralPath $settingsPath -Raw|ConvertFrom-Json).runtimeJunction)}
$config=Join-Path $profileRoot 'komorebi.json'
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
$env:PATH=(Join-Path $profileRoot 'scoop\shims')+';'+$env:PATH
function Local-Processes([string]$Name) { return @(Get-Process -Name $Name -ErrorAction SilentlyContinue | Where-Object SessionId -EQ $session) }
function Query-Index {
    $result=& $client query focused-workspace-index 2>&1
    if($LASTEXITCODE -ne 0){ throw 'Komorebi is running but IPC is unavailable. Existing processes were left intact.' }
    return [int]($result | Select-Object -Last 1)
}
try {
    foreach($required in @($exe,$client,$whkd,$config)) { if(-not(Test-Path -LiteralPath $required)){throw ('Missing required file: '+$required)} }
    if($useJunction){
    [void][IO.Directory]::CreateDirectory($runtime)
    if(Test-Path -LiteralPath $data) {
        $item=Get-Item -LiteralPath $data -Force
        if($item.LinkType -ne 'Junction' -or [IO.Path]::GetFullPath([string]$item.Target) -ine [IO.Path]::GetFullPath($runtime)) {
            throw 'The komorebi data directory no longer points to its repaired runtime folder. It was left unchanged.'
        }
    } else { New-Item -ItemType Junction -Path $data -Target $runtime -ErrorAction Stop | Out-Null }
    } else { $runtime=$data }
    if(($Restart -or $Stop) -and (Local-Processes 'komorebi').Count) {
        & $client stop --whkd
        if($LASTEXITCODE -ne 0){throw 'Graceful stop failed; no forced termination performed.'}
        $deadline=[DateTime]::UtcNow.AddSeconds(5)
        while((Local-Processes 'komorebi').Count -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
        if((Local-Processes 'komorebi').Count){throw 'Komorebi has not finished stopping.'}
    }
    if($Stop){ Write-Output 'Komorebi stopped.'; return }
    if(-not(Local-Processes 'komorebi').Count) {
        $arguments='--config "'+$config+'" --clean-state'
        $daemon=Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -WorkingDirectory $profileRoot -RedirectStandardOutput (Join-Path $PSScriptRoot 'daemon-stdout.log') -RedirectStandardError (Join-Path $PSScriptRoot 'daemon-stderr.log') -PassThru
        $deadline=[DateTime]::UtcNow.AddSeconds(8)
        $ready=$false
        do {
            if($daemon.HasExited){throw ('Komorebi exited; see '+(Join-Path $PSScriptRoot 'daemon-stderr.log'))}
            try { $index=Query-Index; $ready=$true } catch { Start-Sleep -Milliseconds 150 }
        } while(-not $ready -and [DateTime]::UtcNow -lt $deadline)
        if(-not $ready){throw 'Komorebi did not become ready within 8 seconds.'}
    } else { $index=Query-Index }
    if(-not(Local-Processes 'whkd').Count) { Start-Process -FilePath $whkd -WindowStyle Hidden -WorkingDirectory $profileRoot }
    [pscustomobject]@{Running=$true;FocusedWorkspace=$index+1;HotkeysRunning=[bool](Local-Processes 'whkd').Count;Runtime=$runtime}
} catch {
    Add-Content -LiteralPath (Join-Path $PSScriptRoot 'startup-errors.log') -Value ('{0:o} {1}' -f [DateTimeOffset]::Now,$_.Exception.Message)
    throw
}
