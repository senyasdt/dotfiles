[CmdletBinding(SupportsShouldProcess=$true)]
param([ValidateSet('Leopard','Komorebi')][string]$Mode='Leopard',
    [ValidateSet('Switch','Start','Stop','Restart','Reload')][string]$Operation='Switch')
$ErrorActionPreference='Stop'
$desktop=Split-Path $PSScriptRoot
$runtime=Join-Path $PSScriptRoot 'runtime'
$flag=Join-Path $runtime 'selection.json'
$bridgeRoot=Join-Path $desktop 'yasb-catppuccin'
$bridge=Join-Path $bridgeRoot 'DesktopBridge.exe'
$support=Join-Path $desktop 'komorebi-support\Start-DesktopWM.ps1'
$native=Join-Path $desktop 'komorebi-scrolling\runtime\native'
$nativeFlag=Join-Path $desktop 'komorebi-scrolling\runtime\native-profile.json'
if(-not (Test-Path -LiteralPath $nativeFlag) -or -not ([IO.File]::ReadAllText($nativeFlag)|ConvertFrom-Json).enabled){
    $native=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'scoop\apps\komorebi\current'
}
$yasb=Join-Path $env:ProgramFiles 'YASB\yasb.exe'
$yasbCli=Join-Path $env:ProgramFiles 'YASB\yasbc.exe'
$barConfig=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config\yasb\config.yaml'
$appConfig=Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'leopardwm\config\config.toml'
$utf8=New-Object Text.UTF8Encoding($false)
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
function Digest($path){$s=[IO.File]::OpenRead($path);$h=[Security.Cryptography.SHA256]::Create();try{return [BitConverter]::ToString($h.ComputeHash($s)).Replace('-','')}finally{$h.Dispose();$s.Dispose()}}
function Read-Json($path){if(Test-Path -LiteralPath $path){[IO.File]::ReadAllText($path)|ConvertFrom-Json}}
function Write-Json($path,$value){[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 80),$utf8)}
$manifest=Read-Json (Join-Path $runtime 'release.json')
if(-not $manifest){throw 'Run Install-LeopardWM.ps1 first.'}
$bin=[IO.Path]::GetFullPath((Join-Path $runtime $manifest.directory))
if(-not $bin.StartsWith(([IO.Path]::GetFullPath($runtime).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected release directory.'}
foreach($file in @('leopardwm.exe','lwm.exe','leopardwm-cli.exe','leopardwm-watchdog.exe')){
    if((Digest (Join-Path $bin $file)) -ine $manifest.hashes.$file){throw "Release hash mismatch: $file"}
}
$controller=Join-Path $runtime 'DesktopBridge.exe'
if((Digest $controller) -ine $manifest.controllerSha256){throw 'Trial controller hash mismatch.'}
$daemon=Join-Path $bin 'leopardwm.exe'
$lwm=Join-Path $bin 'lwm.exe'
$choice=Read-Json $flag
if(-not $PSCmdlet.ShouldProcess('Desktop WM and YASB; application windows stay open',"$Operation $Mode")){return}
# Resolve 8.3 executable paths too; never control an unrelated same-name process.
if(-not ('DruzhWmTrialPath' -as [type])){Add-Type -TypeDefinition @'
using System;using System.Text;using System.Runtime.InteropServices;
public static class DruzhWmTrialPath {
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] public static extern uint GetLongPathName(string p,StringBuilder b,uint n);
}
'@}
function Canonical($path){if(-not $path){return ''};$b=New-Object Text.StringBuilder 32768;if([DruzhWmTrialPath]::GetLongPathName($path,$b,32768)){return $b.ToString()};return [IO.Path]::GetFullPath($path)}
function Owned($path){
    $name=[IO.Path]::GetFileName($path)
    $items=@(Get-CimInstance Win32_Process -Filter ("Name='"+$name+"'")|Where-Object SessionId -eq $session)
    foreach($item in $items){
        if((Canonical $item.ExecutablePath) -ine (Canonical $path)){
            $fresh=Get-CimInstance Win32_Process -Filter ("ProcessId="+$item.ProcessId)
            if(-not $fresh){continue}
            if((Canonical $fresh.ExecutablePath) -ine (Canonical $path)){throw "Unrecognized $name owner; left untouched."}
        };$item
    }
}
function Command($path,[string]$arguments,[int]$timeout=8000){
    $p=New-Object Diagnostics.Process
    $p.StartInfo=New-Object Diagnostics.ProcessStartInfo($path,$arguments)
    $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
    $p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
    $p.StartInfo.StandardOutputEncoding=[Text.Encoding]::UTF8
    $p.StartInfo.EnvironmentVariables['LOCALAPPDATA']=[Environment]::GetFolderPath('LocalApplicationData')
    try{
        [void]$p.Start();$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit($timeout)){try{$p.Kill()}catch{};throw "Control request timed out; daemon left intact: $arguments"}
        if($p.ExitCode -ne 0){throw ($arguments+': '+$err.Result)}
        return $out.Result
    }finally{$p.Dispose()}
}
function Wait-Stopped($path){
    $deadline=[DateTime]::UtcNow.AddSeconds(8)
    while(@(Owned $path).Count -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
    if(@(Owned $path).Count){throw ('Process has not stopped; no second manager will start: '+$path)}
}
function Stop-Leopard {
    $null=Owned (Join-Path $bin 'leopardwm-watchdog.exe')
    if(@(Owned $daemon).Count){Command $lwm 'stop' 25000|Out-Null;Wait-Stopped $daemon}
    Wait-Stopped (Join-Path $bin 'leopardwm-watchdog.exe')
}
function Start-Leopard {
    if(Get-Process komorebi -ErrorAction SilentlyContinue){throw 'Komorebi is still running; LeopardWM was not started.'}
    if(Get-Process whkd -ErrorAction SilentlyContinue){throw 'whkd is still running; conflicting hotkeys were left untouched.'}
    if(-not @(Owned $daemon).Count){
        # The daemon inherits its launching CLI's stdout handles. Do not wait
        # for EOF on redirected output of `run`: readiness is checked separately.
        $p=Start-Process -FilePath $lwm -ArgumentList 'run --no-watchdog --wait-ms 8000' -WindowStyle Hidden -PassThru
        try{if(-not $p.WaitForExit(12000)){throw 'LeopardWM start request timed out; check the daemon before retrying.'};if($p.ExitCode -ne 0){throw 'LeopardWM start request failed.'}}finally{$p.Dispose()}
    }
    Command $lwm 'status' 4000|Out-Null
}
function Stop-Ui {
    if(@(Owned $yasb).Count){Command $yasbCli 'stop' 8000|Out-Null;Wait-Stopped $yasb}
    if(@(Owned $bridge).Count){Command $bridge '--stop' 4000|Out-Null;Wait-Stopped $bridge}
}
function Start-Ui {
    if($resumeYasb){& (Join-Path $bridgeRoot 'Start-Yasb.ps1')}
    if($resumeBridge -and -not @(Owned $bridge).Count){Start-Process -FilePath $bridge -WorkingDirectory $bridgeRoot -WindowStyle Hidden}
}
function Copy-Retry($from,$to){
    [GC]::Collect();[GC]::WaitForPendingFinalizers();$deadline=[DateTime]::UtcNow.AddSeconds(5)
    while($true){try{Copy-Item -LiteralPath $from -Destination $to -Force;return}catch [IO.IOException]{if([DateTime]::UtcNow -ge $deadline){throw};Start-Sleep -Milliseconds 80}}
}
function Restore-Widths($snapshot){
    $before=Read-Json (Join-Path $snapshot 'komorebi-state.json')
    if(-not $before){return}
    $client=Join-Path $native 'komorebic.exe'
    $focused=[int]$before.monitors.elements[0].workspaces.focused
    try{
        $spaces=@($before.monitors.elements[0].workspaces.elements)
        for($i=0;$i -lt $spaces.Count;$i++){
            $old=$spaces[$i]
            if(-not @($old.resize_dimensions|Where-Object {$null -ne $_}).Count){continue}
            $now=((Command $client 'state')|ConvertFrom-Json).monitors.elements[0].workspaces.elements[$i]
            $oldHandles=@($old.containers.elements|ForEach-Object {$_.windows.elements}|ForEach-Object {$_.hwnd}) -join ','
            $newHandles=@($now.containers.elements|ForEach-Object {$_.windows.elements}|ForEach-Object {$_.hwnd}) -join ','
            if($oldHandles -ne $newHandles){Write-Warning "Workspace $($i+1) changed while testing; its old widths were not applied to different windows.";continue}
            $resize=Join-Path $snapshot ("resize-$i.json");Write-Json $resize @($old.resize_dimensions)
            Command $client ("focus-monitor-workspace 0 $i")|Out-Null
            Command $client ('load-resize "'+$resize+'"')|Out-Null
        }
    }finally{Command $client ("focus-monitor-workspace 0 $focused")|Out-Null}
}
function Restore-Bar($snapshot){Copy-Item -LiteralPath (Join-Path $snapshot 'yasb-config.yaml') -Destination $barConfig -Force}
$mutex=New-Object Threading.Mutex($false,'Local\Druzh.WindowManagerTrial');$locked=$false
try{
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(-not $locked){throw 'Another window-manager switch is in progress.'}
    $null=Owned $daemon;$null=Owned $yasb;$null=Owned $bridge
    $resumeYasb=@(Owned $yasb).Count -gt 0;$resumeBridge=@(Owned $bridge).Count -gt 0
    if($Operation -ne 'Switch'){
        if($Mode -ne 'Leopard' -or -not $choice.enabled){throw 'Direct operations require an initialized LeopardWM selection; use LeopardWM.cmd first.'}
        if($Operation -eq 'Reload'){
            $desired=Join-Path $PSScriptRoot 'config.toml'
            if((Digest $desired) -eq (Digest $appConfig)){Write-Output 'LeopardWM config already current.';return}
            $previous=Join-Path $runtime ('config-before-'+[Guid]::NewGuid().ToString('N')+'.toml')
            Copy-Item -LiteralPath $appConfig -Destination $previous
            try{Copy-Item -LiteralPath $desired -Destination $appConfig -Force;Command $lwm 'reload'|Out-Null}
            catch{$failure=$_;Copy-Item -LiteralPath $previous -Destination $appConfig -Force;Command $lwm 'reload'|Out-Null;throw $failure}
            Write-Output 'LeopardWM config reloaded; previous version saved locally.';return
        }
        if($Operation -in @('Stop','Restart')){Stop-Leopard}
        if($Operation -in @('Start','Restart')){Start-Leopard}
        Write-Output "LeopardWM: $Operation";return
    }
    if($Mode -eq 'Leopard' -and $choice.enabled){Start-Leopard;Write-Output 'LeopardWM is already selected.';return}
    if($Mode -eq 'Komorebi' -and -not $choice.enabled -and -not @(Owned $daemon).Count){
        if(-not $choice){Write-Json $flag @{enabled=$false}}
        & $support -PreserveState|Out-Null
        Write-Output 'Komorebi is already selected; current panel and window widths were left in place.';return
    }
    if($Mode -eq 'Leopard'){
        $wm=@(Get-Process komorebi -ErrorAction SilentlyContinue)
        if($wm.Count -gt 1){throw 'Multiple komorebi processes exist; nothing was changed.'}
        $state=$null
        if($wm.Count){
            $client=Join-Path $native 'komorebic.exe';$null=Owned (Join-Path $native 'komorebi.exe')
            $state=(Command $client 'state')|ConvertFrom-Json
            if(@($state.monitors.elements).Count -ne 1){throw 'The switch currently supports one monitor.'}
        }else{
            if(Get-Process whkd -ErrorAction SilentlyContinue){throw 'Stop the existing whkd before first LeopardWM activation.'}
            Add-Type -AssemblyName System.Windows.Forms
            if([Windows.Forms.Screen]::AllScreens.Count -ne 1){throw 'The switch currently supports one monitor.'}
        }
        # Validate the panel before stopping either manager, also on a clean PC.
        $bar=& (Join-Path $PSScriptRoot 'Convert-YasbConfig.ps1') -Text ([IO.File]::ReadAllText($barConfig)) -BridgeRoot $bridgeRoot
        $snapshot=Join-Path $runtime ('before-leopard-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
        [void][IO.Directory]::CreateDirectory($snapshot)
        if($state){Write-Json (Join-Path $snapshot 'komorebi-state.json') $state}
        Copy-Item -LiteralPath $barConfig -Destination (Join-Path $snapshot 'yasb-config.yaml')
        Copy-Item -LiteralPath $bridge -Destination (Join-Path $snapshot 'DesktopBridge.exe')
        if(Test-Path -LiteralPath $appConfig){Copy-Item -LiteralPath $appConfig -Destination (Join-Path $snapshot 'leopard-config.toml')}
        Write-Json $flag @{enabled=$false;restoreDirectory=(Split-Path $snapshot -Leaf)}
        try{
            Stop-Ui
            if($wm.Count){& $support -Stop|Out-Null}
            if(Get-Process komorebi -ErrorAction SilentlyContinue){throw 'Komorebi has not stopped.'}
            Wait-Stopped (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'scoop\apps\whkd\current\whkd.exe')
            [void][IO.Directory]::CreateDirectory((Split-Path $appConfig))
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'config.toml') -Destination $appConfig -Force
            Copy-Retry $controller $bridge
            Write-Json $flag @{enabled=$true;restoreDirectory=(Split-Path $snapshot -Leaf)}
            [IO.File]::WriteAllText($barConfig,$bar,$utf8)
            Start-Leopard
            Start-Ui
        }catch{
            $failure=$_
            # Never restart komorebi unless LeopardWM and its supervisor are gone.
            Stop-Leopard
            Write-Json $flag @{enabled=$false;restoreDirectory=(Split-Path $snapshot -Leaf)}
            Restore-Bar $snapshot
            if(Test-Path -LiteralPath (Join-Path $snapshot 'leopard-config.toml')){Copy-Item -LiteralPath (Join-Path $snapshot 'leopard-config.toml') -Destination $appConfig -Force}
            if($state){& $support -PreserveState|Out-Null;Restore-Widths $snapshot}
            Start-Ui
            throw $failure
        }
    }else{
        if(-not $choice.restoreDirectory){throw 'No saved komorebi session; nothing was changed.'}
        $snapshot=[IO.Path]::GetFullPath((Join-Path $runtime $choice.restoreDirectory))
        if(-not $snapshot.StartsWith(([IO.Path]::GetFullPath($runtime).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected snapshot directory.'}
        Stop-Leopard
        Stop-Ui
        Write-Json $flag @{enabled=$false;restoreDirectory=$choice.restoreDirectory}
        Restore-Bar $snapshot
        if(Test-Path -LiteralPath (Join-Path $snapshot 'leopard-config.toml')){Copy-Item -LiteralPath (Join-Path $snapshot 'leopard-config.toml') -Destination $appConfig -Force}
        & $support -PreserveState|Out-Null
        Restore-Widths $snapshot
        Start-Ui
    }
    Write-Output "Selected window manager: $Mode. Komorebi.cmd restores the saved komorebi session."
}finally{if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
