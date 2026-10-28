[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [ValidateSet('Status','StartAll','StopAll','RestartAll','AhkEnable','AhkDisable','AhkRestart','AhkResume','KomorebiStart','KomorebiStop','KomorebiRestart','VialStart','VialStop','VialRestart','ZmkStart','ZmkStop','ZmkRestart','OpenVial','ChatGPTRender','ChatGPTSoftwareStart','ChatGPTNormalStart','ScrollOne','ScrollTwo','ScrollBsp','ScrollSmooth','ScrollInstant','ScrollTrial','ScrollStrip','ScrollPrevious','WmLeopard','WmKomorebi','LeopardOverview')]
    [string]$Action='Status', [switch]$Notify
)
$ErrorActionPreference='Stop'
$profileRoot=[Environment]::GetFolderPath('UserProfile')
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
$settingsFile=Join-Path $PSScriptRoot 'settings.json'
$settings=if(Test-Path -LiteralPath $settingsFile){Get-Content -LiteralPath $settingsFile -Raw|ConvertFrom-Json}else{[pscustomobject]@{}}
function Setting($key,$fallback){$v=$settings.PSObject.Properties[$key];if($v -and $v.Value){[Environment]::ExpandEnvironmentVariables([string]$v.Value)}else{$fallback}}
$launcher=Join-Path (Setting 'scriptLauncherRoot' (Join-Path $profileRoot '.config\desktop-customization\script-launcher')) 'ScriptLauncher.exe'
$wm=Join-Path (Setting 'komorebiSupportRoot' (Join-Path $profileRoot '.config\desktop-customization\komorebi-support')) 'Start-DesktopWM.ps1'
$vial=Join-Path $env:LOCALAPPDATA 'Programs\vial-helper\vial-helperd.exe'
$zmk=Join-Path $env:LOCALAPPDATA 'Programs\zmk-yasb\zmk-helperd.exe'
$safeVial=Join-Path $profileRoot '.config\vial\scripts\open_vial_safely.ps1'
function Exact-Processes($path) {
    $name=[IO.Path]::GetFileNameWithoutExtension($path)
    $all=@(Get-Process -Name $name -ErrorAction SilentlyContinue|Where-Object SessionId -EQ $session)
    if(@($all|Where-Object {$_.Path -ine $path}).Count){throw "Another $name owner is running; left untouched."}
    return @($all|Where-Object {$_.Path -ieq $path})
}
function Wait-Client($path,$arguments) {
    $p=Start-Process -FilePath $path -ArgumentList $arguments -WindowStyle Hidden -PassThru
    try {if(!$p.WaitForExit(12000)){throw "Control request timed out: $path"};$p.Refresh();if($p.ExitCode -ne 0){throw "Control request failed: $path ($($p.ExitCode))"}} finally {$p.Dispose()}
}
function Ahk($operation) {
    if(!(Test-Path -LiteralPath $launcher)){throw 'ScriptLauncher is not installed.'}
    if(!(Exact-Processes $launcher).Count){
        Wait-Client $launcher '--check'
        Start-Process -FilePath $launcher -WorkingDirectory (Split-Path $launcher) -WindowStyle Hidden
        $deadline=[DateTime]::UtcNow.AddSeconds(5)
        do {Start-Sleep -Milliseconds 100;$ready=(Exact-Processes $launcher).Count} while(!$ready -and [DateTime]::UtcNow -lt $deadline)
        if(!$ready){throw 'ScriptLauncher did not start.'}
    }
    # Only the guard may start AHK; this controller never launches interpreters.
    Wait-Client $launcher ('--'+$operation)
}
function Wm($operation) {
    $trial=Join-Path (Split-Path $PSScriptRoot) 'leopardwm-test'
    $flag=Join-Path $trial 'runtime\selection.json'
    if((Test-Path -LiteralPath $flag) -and ([IO.File]::ReadAllText($flag)|ConvertFrom-Json).enabled){
        & (Join-Path $trial 'Use-WindowManager.ps1') -Mode Leopard -Operation $operation -Confirm:$false
        return
    }
    if(!(Test-Path -LiteralPath $wm)){throw 'The current komorebi support launcher is missing.'}
    if($operation -eq 'Stop'){& $wm -Stop|Out-Null}elseif($operation -eq 'Restart'){& $wm -Restart|Out-Null}else{& $wm|Out-Null}
}
function Scrolling($mode) {
    $flag=Join-Path (Split-Path $PSScriptRoot) 'leopardwm-test\runtime\selection.json'
    if((Test-Path -LiteralPath $flag) -and ([IO.File]::ReadAllText($flag)|ConvertFrom-Json).enabled){throw 'LeopardWM is selected. Use Window manager (test) > Return to komorebi before changing komorebi layouts.'}
    $scrollRoot=Join-Path (Split-Path -Parent $PSScriptRoot) 'komorebi-scrolling'
    if($mode -in @('Trial','Strip','Previous')){
        & (Join-Path $scrollRoot 'Use-SmoothMotion.ps1') -Mode $mode -Confirm:$false
    }elseif($mode -in @('Smooth','Instant')){
        & (Join-Path $scrollRoot 'Set-Motion.ps1') -Mode $mode -Confirm:$false
    }elseif($mode -eq 'Bsp'){
        & (Join-Path $scrollRoot 'Switch-Layout.ps1') -Mode Bsp -Confirm:$false
    }else{
        $columns=if($mode -eq 'One'){1}else{2}
        & (Join-Path $scrollRoot 'Switch-Layout.ps1') -Mode Scrolling -Columns $columns -Peek 0 -Confirm:$false
    }
}
function Vial-IsOpen {
    $gate=$null
    try{$gate=[Threading.Mutex]::OpenExisting('Local\Druzh.VialSafeOpen');return $true}catch [Threading.WaitHandleCannotBeOpenedException] {return [bool](Get-Process Vial -ErrorAction SilentlyContinue|Where-Object SessionId -EQ $session)}finally{if($gate){$gate.Dispose()}}
}
function Hid($name,$operation) {
    $path=if($name -eq 'Vial'){$vial}else{$zmk}
    if($name -eq 'Vial' -and (Vial-IsOpen)){throw 'Vial is open. Close its editor before controlling the HID helper.'}
    $owned=@(Exact-Processes $path)
    if($operation -ne 'Start'){
        foreach($p in $owned){$p.Kill();if(!$p.WaitForExit(3000)){throw "$name helper did not stop."}}
        $owned=@()
    }
    if($operation -eq 'Stop'){return}
    if($owned.Count -gt 1){throw "Duplicate $name helpers detected. Use Restart to consolidate them."}
    if($owned.Count){return}
    if(!(Test-Path -LiteralPath $path)){throw "$name HID helper is not installed."}
    $arguments='--command run'
    if($name -eq 'Zmk'){
        $config=Join-Path $env:APPDATA 'zmk-yasb\config.json'
        if(!(Test-Path -LiteralPath $config)){throw 'ZMK config.json is missing.'}
        $arguments='-config "'+$config+'"'
    }
    $p=Start-Process -FilePath $path -ArgumentList $arguments -WorkingDirectory (Split-Path $path) -WindowStyle Hidden -PassThru
    if($p.WaitForExit(400)){throw "$name helper exited at startup (code $($p.ExitCode))."}
}
function Write-ServiceEvent([string]$phase,[string]$component='', $failure=$null) {
    # Only user-triggered actions are recorded. Status polling stays read-only.
    # Logging failures must never interrupt service control or AHK protection.
    try {
        $runtime=Join-Path $PSScriptRoot 'runtime'
        [void][IO.Directory]::CreateDirectory($runtime)
        $log=Join-Path $runtime 'services.jsonl'
        if((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -ge 262144){
            Copy-Item -LiteralPath $log -Destination ($log+'.1') -Force
            [IO.File]::WriteAllText($log,'')
        }
        $processes=@{}
        foreach($name in @('yasb','komorebi','whkd','DesktopBridge','ScriptLauncher','ChatGPT')){
            $processes[$name]=@(Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object SessionId -EQ $session | ForEach-Object Id)
        }
        $entry=[ordered]@{at=[DateTimeOffset]::Now.ToString('o');action=$Action;phase=$phase;component=$component;processes=$processes}
        # No command lines, config contents or arbitrary error text in this log.
        if($failure){$entry.errorType=$failure.GetType().FullName;$entry.hresult=$failure.HResult}
        [IO.File]::AppendAllText($log,($entry|ConvertTo-Json -Depth 5 -Compress)+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    } catch {}
}
if($Action -eq 'Status'){
    [pscustomobject]@{ScriptLauncher=@(Exact-Processes $launcher).Count;Vial=@(Exact-Processes $vial).Count;Zmk=@(Exact-Processes $zmk).Count;Komorebi=@(Get-Process komorebi -ErrorAction SilentlyContinue|Where-Object SessionId -EQ $session).Count;Whkd=@(Get-Process whkd -ErrorAction SilentlyContinue|Where-Object SessionId -EQ $session).Count}
    return
}
$target=if($Action -eq 'ChatGPTRender'){'ChatGPT GPU subprocess (main window stays running)'}elseif($Action -like 'ChatGPT*Start'){'ChatGPT (only after the user has closed it)'}else{'Current desktop helpers (YASB stays running)'}
if(!$PSCmdlet.ShouldProcess($target,$Action)){return}
$mutex=New-Object Threading.Mutex($false,'Local\Druzh.DesktopServices');$locked=$false
try {
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(!$locked){throw 'Another helper operation is still running.'}
    Write-ServiceEvent 'begin'
    $failures=New-Object 'Collections.Generic.List[string]'
    function Attempt($label,[scriptblock]$operation){
        Write-ServiceEvent 'component-begin' $label
        try{& $operation;Write-ServiceEvent 'component-complete' $label}catch{Write-ServiceEvent 'component-failed' $label $_.Exception;$failures.Add($label+': '+$_.Exception.Message)}
    }
    switch -Regex ($Action) {
        '^Wm(Leopard|Komorebi)$' {& (Join-Path (Split-Path $PSScriptRoot) 'leopardwm-test\Use-WindowManager.ps1') -Mode $Matches[1] -Confirm:$false;break}
        '^LeopardOverview$' {
            $trial=Join-Path (Split-Path $PSScriptRoot) 'leopardwm-test'
            $release=[IO.File]::ReadAllText((Join-Path $trial 'runtime\release.json'))|ConvertFrom-Json
            Wait-Client (Join-Path $trial ('runtime\'+$release.directory+'\lwm.exe')) 'toggle-overview';break
        }
        '^StartAll$' {Attempt 'AHK' {Ahk 'resume'};Attempt 'Komorebi' {Wm 'Start'};Attempt 'Vial' {Hid 'Vial' 'Start'};Attempt 'ZMK' {Hid 'Zmk' 'Start'};break}
        '^StopAll$' {Attempt 'AHK' {Ahk 'pause'};Attempt 'Komorebi' {Wm 'Stop'};Attempt 'Vial' {Hid 'Vial' 'Stop'};Attempt 'ZMK' {Hid 'Zmk' 'Stop'};break}
        '^RestartAll$' {Attempt 'AHK' {Ahk 'restart-all'};Attempt 'Komorebi' {Wm 'Restart'};Attempt 'Vial' {Hid 'Vial' 'Restart'};Attempt 'ZMK' {Hid 'Zmk' 'Restart'};break}
        '^AhkEnable$' {Ahk 'resume';Ahk 'enable-all';break}
        '^AhkDisable$' {Ahk 'disable-all';break}
        '^AhkRestart$' {Ahk 'restart-all';break}
        '^AhkResume$' {Ahk 'resume';break}
        '^Scroll(One|Two|Bsp|Smooth|Instant|Trial|Strip|Previous)$' {Scrolling $Matches[1];break}
        '^Komorebi(Start|Stop|Restart)$' {Wm $Matches[1];break}
        '^(Vial|Zmk)(Start|Stop|Restart)$' {Hid $Matches[1] $Matches[2];break}
        '^ChatGPTRender$' {& (Join-Path $PSScriptRoot 'Repair-ChatGPTRendering.ps1') -Confirm:$false;break}
        '^ChatGPT(Software|Normal)Start$' {
            $mode=if($Matches[1] -eq 'Software'){'Software'}else{'Default'}
            & (Join-Path $PSScriptRoot 'Start-ChatGPTRenderMode.ps1') -Mode $mode -Confirm:$false
            break
        }
        '^OpenVial$' {
            if(!(Test-Path -LiteralPath $safeVial)){throw 'The safe Vial launcher is missing.'}
            Start-Process powershell.exe -ArgumentList ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$safeVial+'" -Notify') -WindowStyle Hidden
            break
        }
    }
    if($failures.Count){throw ($failures -join "`n")}
    Write-ServiceEvent 'complete'
    Write-Output ('Completed: '+$Action)
} catch {
    Write-ServiceEvent 'failed' '' $_.Exception
    # The operation has finished (including its rollback). A notification may
    # stay open behind another window; it must not keep every menu action locked.
    if($locked){$mutex.ReleaseMutex();$locked=$false}
    if($Notify){Add-Type -AssemblyName System.Windows.Forms;[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Desktop helpers','OK','Warning')}
    throw
} finally {if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
