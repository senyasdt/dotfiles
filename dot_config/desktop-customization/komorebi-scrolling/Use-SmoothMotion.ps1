[CmdletBinding(SupportsShouldProcess=$true)]
param([ValidateSet('Trial','Previous')][string]$Mode='Trial')
$ErrorActionPreference='Stop'
$runtime=Join-Path $PSScriptRoot 'runtime'
$desktop=Split-Path $PSScriptRoot
$bridgeRoot=Join-Path $desktop 'yasb-catppuccin'
$native=Join-Path $runtime 'native'
$manifestPath=Join-Path $runtime 'motion-bundles.json'
$profilePath=Join-Path $runtime 'motion-profile.json'
$configPath=Join-Path $runtime 'native-config.json'
$support=Join-Path $desktop 'komorebi-support\Start-DesktopWM.ps1'
$utf8=New-Object Text.UTF8Encoding($false)
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
if(-not(Test-Path -LiteralPath $manifestPath)){throw 'No motion trial has been staged. The current desktop was left unchanged.'}
$bundles=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$selected=$bundles.$Mode
if(-not $selected){throw 'The requested motion bundle is missing.'}
$bundle=[IO.Path]::GetFullPath((Join-Path $runtime $selected.directory))
if(-not $bundle.StartsWith(([IO.Path]::GetFullPath($runtime).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Motion bundle must be inside the local runtime directory.'}
$files=@('komorebi.exe','komorebic.exe','build-info.json','DesktopBridge.exe')
function Digest([string]$path){
    $stream=[IO.File]::OpenRead($path)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$sha.Dispose();$stream.Dispose()}
}
foreach($file in $files){
    $path=Join-Path $bundle $file
    if(-not(Test-Path -LiteralPath $path) -or (Digest $path) -ine $selected.hashes.$file){throw "Motion bundle hash mismatch: $file"}
}
$flag=Get-Content -LiteralPath (Join-Path $runtime 'native-profile.json') -Raw | ConvertFrom-Json
if(-not $flag.enabled){throw 'Enable independent columns first; this switch never changes the stock komorebi installation.'}
function Canonical-Path([string]$path){
    if(-not $path){return ''}
    if(-not ('DruzhMotionPath' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class DruzhMotionPath {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
    public static extern uint GetLongPathName(string path, StringBuilder buffer, uint length);
}
'@
    }
    $buffer=New-Object Text.StringBuilder 32768
    if([DruzhMotionPath]::GetLongPathName($path,$buffer,32768)) {return $buffer.ToString()}
    return [IO.Path]::GetFullPath($path)
}
function Owners([string]$name,[string]$expected){
    # WMI exposes the executable path without opening a newly starting client's
    # MainModule (Get-Process.Path can temporarily be empty for YASB --read calls).
    $items=@(Get-CimInstance Win32_Process -Filter ("Name='"+$name+".exe'") | Where-Object SessionId -eq $session)
    foreach($item in $items){
        if((Canonical-Path $item.ExecutablePath) -ine (Canonical-Path $expected)){
            $fresh=Get-CimInstance Win32_Process -Filter ("ProcessId="+$item.ProcessId)
            if(-not $fresh){continue}
            if((Canonical-Path $fresh.ExecutablePath) -ine (Canonical-Path $expected)){throw "Unexpected $name owner at PID $($item.ProcessId); left untouched."}
        }
        $item
    }
}
$bridge=Join-Path $bridgeRoot 'DesktopBridge.exe'
function Bridge-Daemons {
    return @(Get-CimInstance Win32_Process -Filter "Name='DesktopBridge.exe'" | Where-Object {
        $_.SessionId -eq $session -and (Canonical-Path $_.ExecutablePath) -ieq (Canonical-Path $bridge) -and $_.CommandLine -notmatch '\s--'
    })
}
if(-not $PSCmdlet.ShouldProcess('Experimental komorebi and DesktopBridge; windows stay open',"Switch movement to $Mode")){return}
$wmOwners=@(Owners 'komorebi' (Join-Path $native 'komorebi.exe'))
if($wmOwners.Count -gt 1){throw 'Multiple komorebi processes; nothing changed.'}
$null=Owners 'DesktopBridge' $bridge
$bridgeOwners=@(Bridge-Daemons)
Write-Verbose "Before switch: $($wmOwners.Count) komorebi and $($bridgeOwners.Count) bridge daemon(s)."
$mutex=New-Object Threading.Mutex($false,'Local\Druzh.MotionTrial')
$locked=$false
function Write-Json($path,$value){[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 60),$utf8)}
function Wm-Client([string]$arguments){
    $p=New-Object Diagnostics.Process
    $p.StartInfo=New-Object Diagnostics.ProcessStartInfo((Join-Path $native 'komorebic.exe'),$arguments)
    $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
    $p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
    $p.StartInfo.StandardOutputEncoding=[Text.Encoding]::UTF8
    try{
        [void]$p.Start();$output=$p.StandardOutput.ReadToEndAsync();$errorOutput=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit(4000)){try{$p.Kill()}catch{};throw 'Komorebi control request timed out.'}
        if($p.ExitCode -ne 0){throw ('Komorebi control request failed: '+$errorOutput.Result)}
        return $output.Result
    }finally{$p.Dispose()}
}
function Handles($workspace){
    return (@($workspace.containers.elements|ForEach-Object {$_.windows.elements}|ForEach-Object {[long]$_.hwnd}) -join ',')
}
function Restore-Widths($saved){
    if(-not $saved){return}
    $focused=[int]$saved.monitors.elements[0].workspaces.focused
    try{
        $spaces=@($saved.monitors.elements[0].workspaces.elements)
        for($i=0;$i -lt $spaces.Count;$i++){
            $old=$spaces[$i]
            if(-not @($old.resize_dimensions|Where-Object {$null -ne $_}).Count){continue}
            $current=(Wm-Client 'state')|ConvertFrom-Json
            $now=$current.monitors.elements[0].workspaces.elements[$i]
            if((Handles $old) -cne (Handles $now)){throw "Window order changed in workspace $($i+1); refusing to apply widths to different windows."}
            $path=Join-Path $recovery ("resize-workspace-$i.json")
            Write-Json $path @($old.resize_dimensions)
            Wm-Client ("focus-monitor-workspace 0 $i")|Out-Null
            Wm-Client ('load-resize "'+$path+'"')|Out-Null
            $check=((Wm-Client 'state')|ConvertFrom-Json).monitors.elements[0].workspaces.elements[$i]
            if(($check.resize_dimensions|ConvertTo-Json -Compress -Depth 8) -cne ($old.resize_dimensions|ConvertTo-Json -Compress -Depth 8)){throw 'Column width restoration failed.'}
        }
    }finally{Wm-Client ("focus-monitor-workspace 0 $focused")|Out-Null}
}
function Stop-Bridge {
    if(@(Owners 'DesktopBridge' $bridge).Count){
        $p=Start-Process -FilePath $bridge -ArgumentList '--stop' -WindowStyle Hidden -PassThru
        try{if(-not $p.WaitForExit(3000)){throw 'Bridge stop request timed out.'}}finally{$p.Dispose()}
        $limit=[DateTime]::UtcNow.AddSeconds(5)
        while(@(Bridge-Daemons).Count -and [DateTime]::UtcNow -lt $limit){Start-Sleep -Milliseconds 80}
        if(@(Bridge-Daemons).Count){throw 'DesktopBridge daemon did not stop.'}
    }
}
function Copy-Bundle($from){
    foreach($file in @('komorebi.exe','komorebic.exe','build-info.json')){Copy-Item -LiteralPath (Join-Path $from $file) -Destination (Join-Path $native $file) -Force}
    # YASB may still run brief --read clients after the daemon has stopped.
    # Wait for the executable file to unlock; never treat these clients as a daemon.
    $copyLimit=[DateTime]::UtcNow.AddSeconds(5)
    while($true){
        try{Copy-Item -LiteralPath (Join-Path $from 'DesktopBridge.exe') -Destination $bridge -Force;break}
        catch [IO.IOException]{if([DateTime]::UtcNow -ge $copyLimit){throw};Start-Sleep -Milliseconds 40}
    }
}
function Start-Bridge {
    if($bridgeOwners.Count -and -not @(Bridge-Daemons).Count){
        Start-Process -FilePath $bridge -WorkingDirectory $bridgeRoot -WindowStyle Hidden
        Start-Sleep -Milliseconds 500
        if(-not @(Bridge-Daemons).Count){throw 'DesktopBridge did not stay running.'}
    }
}
try{
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(-not $locked){throw 'Another movement switch is in progress.'}
    $savedState=if($wmOwners.Count){(Wm-Client 'state')|ConvertFrom-Json}else{$null}
    if($savedState -and @($savedState.monitors.elements).Count -ne 1){throw 'This movement trial supports one monitor only.'}
    # Private per-switch recovery snapshot; never overwrites the original Previous bundle.
    $recovery=Join-Path $runtime ('motion-switch-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    [IO.Directory]::CreateDirectory($recovery)|Out-Null
    if($savedState){Write-Json (Join-Path $recovery 'before-state.json') $savedState}
    foreach($file in @('komorebi.exe','komorebic.exe','build-info.json')){Copy-Item -LiteralPath (Join-Path $native $file) -Destination $recovery}
    Copy-Item -LiteralPath $bridge -Destination $recovery
    $priorConfig=[IO.File]::ReadAllText($configPath)
    $priorProfile=if(Test-Path -LiteralPath $profilePath){[IO.File]::ReadAllText($profilePath)}else{$null}
    [IO.File]::WriteAllText((Join-Path $recovery 'native-config.json'),$priorConfig,$utf8)
    if($priorProfile){[IO.File]::WriteAllText((Join-Path $recovery 'motion-profile.json'),$priorProfile,$utf8)}
    $stopped=$false
    try{
        Stop-Bridge
        & $support -Stop | Out-Null
        $stopped=$true
        Copy-Bundle $bundle
        $config=$priorConfig|ConvertFrom-Json
        $config|Add-Member -NotePropertyName animation -NotePropertyValue $selected.animation -Force
        Write-Json $configPath $config
        Write-Json $profilePath ([ordered]@{mode=$Mode;duration=[int]$selected.animation.duration.movement})
        & $support -PreserveState | Out-Null
        Restore-Widths $savedState
        Start-Bridge
        Write-Output "Movement profile: $Mode. Restore-Motion.cmd returns the previous build and 90 ms wheel behaviour."
    }catch{
        $failure=$_
        if($stopped){
            try{
                Stop-Bridge
                & $support -Stop | Out-Null
                Copy-Bundle $recovery
                [IO.File]::WriteAllText($configPath,$priorConfig,$utf8)
                if($null -eq $priorProfile){if(Test-Path -LiteralPath $profilePath){Remove-Item -LiteralPath $profilePath}}
                else{[IO.File]::WriteAllText($profilePath,$priorProfile,$utf8)}
                & $support -PreserveState | Out-Null
                Restore-Widths $savedState
                Start-Bridge
            }catch{Write-Warning "Automatic recovery failed. Saved bundle: $recovery"}
        }else{Start-Bridge}
        throw $failure
    }
}finally{if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
