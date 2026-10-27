param([switch]$Restart,[switch]$Stop,[switch]$PreserveState)
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
# Optional local trial bundle. Absent flag leaves the standard Scoop binaries/config.
$trialRoot=Join-Path $desktopRoot 'komorebi-scrolling\runtime'
$trialFlag=Join-Path $trialRoot 'native-profile.json'
if((Test-Path -LiteralPath $trialFlag) -and (Get-Content -LiteralPath $trialFlag -Raw|ConvertFrom-Json).enabled){
    $native=Join-Path $trialRoot 'native'
    $build=Get-Content -LiteralPath (Join-Path $native 'build-info.json') -Raw|ConvertFrom-Json
    foreach($file in @('komorebi.exe','komorebic.exe')){
        if((Get-FileHash -LiteralPath (Join-Path $native $file) -Algorithm SHA256).Hash -ine $build.hashes.$file){throw "Trial binary hash mismatch: $file"}
    }
    $exe=Join-Path $native 'komorebi.exe'
    $client=Join-Path $native 'komorebic.exe'
    $config=Join-Path $trialRoot 'native-config.json'
    $PreserveState=$true
}

$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
$env:PATH=(Join-Path $profileRoot 'scoop\shims')+';'+$env:PATH
function Local-Processes([string]$Name) { return @(Get-Process -Name $Name -ErrorAction SilentlyContinue | Where-Object SessionId -EQ $session) }
function Invoke-Client([string]$Arguments,[int]$Timeout=4000) {
    $p=New-Object Diagnostics.Process
    $p.StartInfo=New-Object Diagnostics.ProcessStartInfo($client,$Arguments)
    $p.StartInfo.UseShellExecute=$false
    $p.StartInfo.CreateNoWindow=$true
    $p.StartInfo.RedirectStandardOutput=$true
    $p.StartInfo.RedirectStandardError=$true
    try {
        [void]$p.Start()
        $output=$p.StandardOutput.ReadToEndAsync()
        $errorOutput=$p.StandardError.ReadToEndAsync()
        if(!$p.WaitForExit($Timeout)){
            # Only this short-lived client is terminated, never the daemon.
            try{$p.Kill()}catch{}
            throw 'Komorebi control request timed out; daemon left intact.'
        }
        if($p.ExitCode -ne 0){throw ('Komorebi control request failed: '+$errorOutput.Result.Trim())}
        return $output.Result.Trim()
    } finally {$p.Dispose()}
}
function Query-Index {
    return [int](Invoke-Client 'query focused-workspace-index')
}
$mutex=New-Object Threading.Mutex($false,'Local\Druzh.DesktopWM')
$locked=$false
function Repair-IpcJunction {
    if(!$useJunction){throw 'IPC junction repair is not enabled on this machine.'}
    # Check all sessions: never rename the IPC path of a running daemon.
    if(Get-Process -Name komorebi -ErrorAction SilentlyContinue){throw 'A komorebi process exists; IPC link left intact.'}
    $item=Get-Item -LiteralPath $data -Force
    if($item.LinkType -ne 'Junction' -or [IO.Path]::GetFullPath([string]$item.Target) -ine [IO.Path]::GetFullPath($runtime)){
        throw 'Unexpected IPC path; left intact.'
    }
    $saved=$data+'-link-before-repair-'+[Guid]::NewGuid().ToString('N')
    # Rename the link itself, keeping its target and all runtime data untouched.
    [IO.Directory]::Move($data,$saved)
    try {
        if(Test-Path -LiteralPath $data){throw 'IPC path was recreated concurrently; left intact.'}
        New-Item -ItemType Junction -Path $data -Target $runtime -ErrorAction Stop | Out-Null
    } catch {
        if(!(Test-Path -LiteralPath $data)){[IO.Directory]::Move($saved,$data)}
        throw
    }
    Add-Content -LiteralPath (Join-Path $PSScriptRoot 'startup-errors.log') -Value ('{0:o} Recreated verified IPC junction after bind error 10048; previous link: {1}' -f [DateTimeOffset]::Now,$saved)
}
try {
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(!$locked){throw 'Another komorebi start/stop operation is still running.'}
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
        Invoke-Client 'stop --whkd' | Out-Null
        $deadline=[DateTime]::UtcNow.AddSeconds(5)
        while((Local-Processes 'komorebi').Count -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
        if((Local-Processes 'komorebi').Count){throw 'Komorebi has not finished stopping.'}
    }
    if($Stop){ Write-Output 'Komorebi stopped.'; return }
    if(-not(Local-Processes 'komorebi').Count) {
        for($attempt=0;$attempt -lt 2;$attempt++){
        $arguments='--config "'+$config+'"'
        if(-not $PreserveState){$arguments+=' --clean-state'}
        $daemon=Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -WorkingDirectory $profileRoot -RedirectStandardOutput (Join-Path $PSScriptRoot 'daemon-stdout.log') -RedirectStandardError (Join-Path $PSScriptRoot 'daemon-stderr.log') -PassThru
        $deadline=[DateTime]::UtcNow.AddSeconds(8)
        $ready=$false
        do {
            if($daemon.HasExited){break}
            try { $index=Query-Index; $ready=$true } catch { Start-Sleep -Milliseconds 150 }
        } while(-not $ready -and [DateTime]::UtcNow -lt $deadline)
        if($ready){$daemon.Dispose();break}
        $exited=$daemon.HasExited
        $daemon.Dispose()
        $diagnostic=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'daemon-stderr.log') -Raw -ErrorAction SilentlyContinue
        if($attempt -eq 0 -and $exited -and $useJunction -and $diagnostic -match 'os error 10048'){
            Add-Content -LiteralPath (Join-Path $PSScriptRoot 'startup-errors.log') -Value $diagnostic
            Repair-IpcJunction
            continue
        }
        if($exited){throw ('Komorebi exited; see '+(Join-Path $PSScriptRoot 'daemon-stderr.log'))}
        throw 'Komorebi did not become ready within 8 seconds; daemon left intact.'
        }
    } else { $index=Query-Index }
    if(-not(Local-Processes 'whkd').Count) {
        $keys=Start-Process -FilePath $whkd -WindowStyle Hidden -WorkingDirectory $profileRoot -PassThru
        try{if($keys.WaitForExit(500)){throw ('whkd exited with code '+$keys.ExitCode)}}finally{$keys.Dispose()}
    }
    [pscustomobject]@{Running=$true;FocusedWorkspace=$index+1;HotkeysRunning=[bool](Local-Processes 'whkd').Count;Runtime=$runtime}
} catch {
    Add-Content -LiteralPath (Join-Path $PSScriptRoot 'startup-errors.log') -Value ('{0:o} {1}' -f [DateTimeOffset]::Now,$_.Exception.Message)
    throw
} finally {if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
