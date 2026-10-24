param([ValidateSet('Build','Apply','Start','Stop','RestoreCurrent','RestorePreDock','Status','ImportApps')][string]$Action='Status')
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$profileRoot=[Environment]::GetFolderPath('UserProfile')
$startup=[Environment]::GetFolderPath('Startup')
$yasbRoot=Join-Path $profileRoot '.config\yasb'
$bridge=Join-Path $root 'DesktopBridge.exe'
$yasb=Join-Path $env:ProgramFiles 'YASB\yasb.exe'
$cli=Join-Path $env:ProgramFiles 'YASB\yasbc.exe'
$settingsFile=Join-Path $root 'settings.json'
$settings=if(Test-Path -LiteralPath $settingsFile){Get-Content -LiteralPath $settingsFile -Raw|ConvertFrom-Json}else{[pscustomobject]@{}}
function Setting($key,$fallback){$v=$settings.PSObject.Properties[$key];if($v -and $v.Value){[Environment]::ExpandEnvironmentVariables([string]$v.Value)}else{$fallback}}
$launcher=Setting 'scriptLauncherRoot' (Join-Path $profileRoot '.config\desktop-customization\script-launcher')
$finder=Setting 'finderWidgetsRoot' (Join-Path $profileRoot '.config\desktop-customization\finder-widgets')
$preDock=Setting 'preDockBackup' (Join-Path (Split-Path $root -Parent) 'backup-20261024')
$dock=Setting 'myDockExecutable' 'C:\Program Files (x86)\Steam\steamapps\common\MyDockFinder\Dock_64.exe'
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
function Write-Utf8($path,$content){[IO.File]::WriteAllText($path,$content,(New-Object Text.UTF8Encoding($false)))}
function Expand-Template($file){
    $shortRoot=(New-Object -ComObject Scripting.FileSystemObject).GetFolder($root).ShortPath
    if($shortRoot.Contains(' ')){throw 'YASB 2.0.0 requires a helper path without spaces. Choose a different profile directory.'}
    [Environment]::ExpandEnvironmentVariables([IO.File]::ReadAllText($file).Replace('__BRIDGE_CMD__',$shortRoot).Replace('__BRIDGE__',$root).Replace('__LAUNCHER__',$launcher).Replace('__USERPROFILE__',$profileRoot))
}
function Run-Wait($exe,$arguments,[int]$seconds=12){
    $p=Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
    if(!$p.WaitForExit($seconds*1000)){throw "Timed out: $exe"};$p.Refresh();if($p.ExitCode -ne 0){throw "Command failed ($($p.ExitCode)): $exe"}
}
function Owned-Processes($name,$path){@(Get-Process -Name $name -ErrorAction SilentlyContinue|Where-Object {$_.SessionId -eq $session -and $_.Path -ieq $path})}
function Stop-Bridge {
    if(Test-Path -LiteralPath $bridge){Run-Wait $bridge '--stop';$deadline=[DateTime]::UtcNow.AddSeconds(8);while((Owned-Processes 'DesktopBridge' $bridge).Count -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 200};if((Owned-Processes 'DesktopBridge' $bridge).Count){throw 'Desktop bridge did not stop safely'}}
}
function Stop-Yasb {
    $allowed=@($yasb,(Join-Path $env:LOCALAPPDATA 'YASB-patched\yasb.exe'))
    $running=@(Get-Process -Name yasb -ErrorAction SilentlyContinue|Where-Object SessionId -EQ $session)
    if(@($running|Where-Object {$_.Path -notin $allowed}).Count){throw 'Unknown YASB build is running; left untouched'}
    if($running.Count){try{Run-Wait $cli 'stop' 8}catch{Write-Warning 'YASB did not answer its CLI; stopping the verified local instance'};Start-Sleep -Milliseconds 600;Get-Process -Name yasb -ErrorAction SilentlyContinue|Where-Object {$_.SessionId -eq $session -and $_.Path -in $allowed}|Stop-Process -Force}
}
function Stop-Dock {
    Owned-Processes 'Dock_64' $dock|Stop-Process -Force
    $finderExe=Join-Path $finder 'FinderWidgets.exe';if(Test-Path -LiteralPath $finderExe){Run-Wait $finderExe '--stop'}
}
function Snapshot {
    & (Join-Path $root 'Snapshot.ps1')|Out-Null
    $s=Get-Content -LiteralPath (Join-Path $root 'private\snapshot.json') -Raw|ConvertFrom-Json
    foreach($f in $s.files){if($f.existed -and (Get-FileHash -LiteralPath $f.backup -Algorithm SHA256).Hash -ne $f.sha256){throw "Backup hash mismatch: $($f.backup)"}}
    return $s
}
function Theme-Environment($theme){
    $path=Join-Path $root 'private\theme-environment.json'
    if(!(Test-Path -LiteralPath $path)){Write-Utf8 $path (@{previous=[Environment]::GetEnvironmentVariable('WINDOWS_DESKTOP_THEME','User');previousBar=[Environment]::GetEnvironmentVariable('WINDOWS_DESKTOP_BAR','User')}|ConvertTo-Json)}
    [Environment]::SetEnvironmentVariable('WINDOWS_DESKTOP_THEME',$theme,'User')
    $env:WINDOWS_DESKTOP_THEME=$theme
    [Environment]::SetEnvironmentVariable('WINDOWS_DESKTOP_BAR','yasb','User');$env:WINDOWS_DESKTOP_BAR='yasb'
}
function Restore-ThemeEnvironment {
    $path=Join-Path $root 'private\theme-environment.json'
    if(Test-Path -LiteralPath $path){$saved=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json;$previous=$saved.previous;[Environment]::SetEnvironmentVariable('WINDOWS_DESKTOP_THEME',$previous,'User');$env:WINDOWS_DESKTOP_THEME=$previous;if($saved.PSObject.Properties['previousBar']){[Environment]::SetEnvironmentVariable('WINDOWS_DESKTOP_BAR',$saved.previousBar,'User');$env:WINDOWS_DESKTOP_BAR=$saved.previousBar}}
}
function Restore-File($snapshot,$name){
    $f=@($snapshot.files|Where-Object { [IO.Path]::GetFileName($_.backup) -eq $name })
    if($f.Count -ne 1){throw "Missing snapshot record: $name"}
    if($f[0].existed){Copy-Item -LiteralPath $f[0].backup -Destination $f[0].original -Force}
    elseif(Test-Path -LiteralPath $f[0].original){Remove-Item -LiteralPath $f[0].original}
}
function Restore-Startup($snapshot){foreach($name in @('MyDockFinder.lnk','Finder Widgets.lnk','yasb.cmd','YASB Catppuccin.lnk')){Restore-File $snapshot $name};foreach($v in $snapshot.dockRun){Set-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $v.name -Value $v.value}}
function Restart-WinHelper {if(Test-Path -LiteralPath (Join-Path $launcher 'ScriptLauncher.exe')){Run-Wait (Join-Path $launcher 'ScriptLauncher.exe') '--restart mydockfinder-hotkeys.ahk'}}
function Mode($value){[IO.Directory]::CreateDirectory((Join-Path $root 'runtime'))|Out-Null;Write-Utf8 (Join-Path $root 'runtime\profile.json') (@{mode=$value;updatedAt=[DateTimeOffset]::Now.ToString('o')}|ConvertTo-Json)}
function Start-Profile {
    if(!(Test-Path -LiteralPath $yasb)){throw 'Install YASB 2.0.0 first'}
    if(!(Test-Path -LiteralPath $bridge)){throw 'Run -Action Build first'}
    if(!(Owned-Processes 'yasb' $yasb).Count){Start-Process -FilePath $yasb -WorkingDirectory (Split-Path $yasb) -WindowStyle Hidden}
    if(!(Owned-Processes 'DesktopBridge' $bridge).Count){Start-Process -FilePath $bridge -WorkingDirectory $root -WindowStyle Hidden}
}
function Restore-Current {
    $s=Snapshot;Stop-Bridge;Stop-Yasb;Stop-Dock
    foreach($name in @('yasb-config.yaml','yasb-styles.css','win-hotkeys.ahk','mydock-config.ini')){Restore-File $s $name}
    # Keep komorebi IPC, BSP, current AHK game rules and manual states intact.
    Restore-Startup $s
    if($s.launchpadExisted){Get-ChildItem -LiteralPath (Join-Path $s.backup 'launchpad')|ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $yasbRoot 'launchpad') -Recurse -Force}}
    elseif(Test-Path -LiteralPath (Join-Path $yasbRoot 'launchpad\apps.json')){Remove-Item -LiteralPath (Join-Path $yasbRoot 'launchpad\apps.json')}
    Restart-WinHelper
    if('yasb' -in $s.running){Start-Process -FilePath $yasb -WorkingDirectory (Split-Path $yasb) -WindowStyle Hidden}
    if('Dock_64' -in $s.running){Start-Process -FilePath $dock -WorkingDirectory (Split-Path $dock) -WindowStyle Hidden}
    if('FinderWidgets' -in $s.running){Start-Process -FilePath (Join-Path $finder 'FinderWidgets.exe') -WorkingDirectory $finder -WindowStyle Hidden}
    Restore-ThemeEnvironment;Mode 'previous';Write-Output 'Restored the desktop from before the Catppuccin experiment.'
}
if($Action -eq 'Build'){
    $resumeYasb=(Owned-Processes 'yasb' $yasb).Count -gt 0
    $resumeBridge=(Owned-Processes 'DesktopBridge' $bridge).Count -gt 0
    # Custom widgets launch short-lived readers from this executable. Stop the
    # readers' owner before replacing it, then restore the original run state.
    Stop-Yasb;Stop-Bridge
    try{
        & (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll ('/out:'+$bridge) (Join-Path $root 'DesktopBridge.cs') (Join-Path $root 'KomorebiFeed.cs')
        if($LASTEXITCODE -ne 0){throw 'Build failed'};Run-Wait $bridge '--test';Write-Output 'Build and dock policy checks passed.'
    }finally{if($resumeYasb){Start-Process -FilePath $yasb -WorkingDirectory (Split-Path $yasb) -WindowStyle Hidden};if($resumeBridge){Start-Process -FilePath $bridge -WorkingDirectory $root -WindowStyle Hidden}}
    return
}
if($Action -eq 'Stop'){Stop-Bridge;return}
if($Action -eq 'Start'){Start-Profile;return}
if($Action -eq 'ImportApps'){& (Join-Path $root 'Import-Apps.ps1') -Refresh;return}
if($Action -eq 'RestoreCurrent'){Restore-Current;return}
if($Action -eq 'RestorePreDock'){
    if(!(Test-Path -LiteralPath (Join-Path $root 'config-predock.yaml'))){throw 'No pre-MyDockFinder layout supplied; use RestoreCurrent'}
    $s=Snapshot;Stop-Bridge;Stop-Yasb;Stop-Dock
    Copy-Item -LiteralPath (Join-Path $root 'styles-predock.css') -Destination (Join-Path $yasbRoot 'styles.css') -Force
    Write-Utf8 (Join-Path $yasbRoot 'config.yaml') (Expand-Template (Join-Path $root 'config-predock.yaml'))
    # The old layout is restored; the broken legacy daemon/startup chain is not.
    Restore-File $s 'win-hotkeys.ahk'
    foreach($name in @('MyDockFinder.lnk','Finder Widgets.lnk','yasb.cmd','YASB Catppuccin.lnk')){ $p=Join-Path $startup $name;if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p} }
    if(!(Test-Path -LiteralPath (Join-Path $startup 'Desktop Session.lnk'))){$shell=New-Object -ComObject WScript.Shell;$lnk=$shell.CreateShortcut((Join-Path $startup 'YASB Catppuccin.lnk'));$lnk.TargetPath=$yasb;$lnk.WorkingDirectory=Split-Path $yasb;$lnk.Description='Previous YASB panel';$lnk.Save()}
    foreach($v in $s.dockRun){Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $v.name -ErrorAction SilentlyContinue}
    Theme-Environment 'classic';Restart-WinHelper;Run-Wait $bridge '--show-taskbar';Start-Process -FilePath $yasb -WorkingDirectory (Split-Path $yasb) -WindowStyle Hidden;Mode 'predock';Write-Output 'Restored the old YASB layout and native taskbar. IPC fixes and AHK game rules retained.';return
}
if($Action -eq 'Apply'){
    $s=Snapshot
    if(!(Test-Path -LiteralPath $bridge)){& $PSCommandPath -Action Build}
    if(!(Test-Path -LiteralPath (Join-Path $launcher 'ScriptLauncher.exe'))){throw 'Configure scriptLauncherRoot in settings.json before applying'}
    & (Join-Path $root 'Import-Apps.ps1')|Out-Null
    try{
        Stop-Bridge;Stop-Yasb;Stop-Dock
        Write-Utf8 (Join-Path $yasbRoot 'config.yaml') (Expand-Template (Join-Path $root 'config.yaml'))
        Copy-Item -LiteralPath (Join-Path $root 'styles.css') -Destination (Join-Path $yasbRoot 'styles.css') -Force
        Copy-Item -LiteralPath (Join-Path $root 'win-launchpad.ahk') -Destination (Join-Path $profileRoot '.config\autohotkey\mydockfinder-hotkeys.ahk') -Force
        foreach($name in @('MyDockFinder.lnk','Finder Widgets.lnk','yasb.cmd')){$p=Join-Path $startup $name;if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p}}
        foreach($v in $s.dockRun){Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $v.name -ErrorAction SilentlyContinue}
        if(!(Test-Path -LiteralPath (Join-Path $startup 'Desktop Session.lnk'))){$shell=New-Object -ComObject WScript.Shell;$lnk=$shell.CreateShortcut((Join-Path $startup 'YASB Catppuccin.lnk'));$lnk.TargetPath=Join-Path $env:WINDIR 'System32\wscript.exe';$lnk.Arguments='"'+(Join-Path $root 'Start.vbs')+'"';$lnk.WorkingDirectory=$root;$lnk.Description='YASB Catppuccin and smart dock';$lnk.Save()}
        $shell=New-Object -ComObject WScript.Shell
        Theme-Environment 'catppuccin';Mode 'catppuccin';Start-Profile;Restart-WinHelper
        Start-Sleep -Seconds 5
        if(!(Owned-Processes 'yasb' $yasb).Count -or !(Owned-Processes 'DesktopBridge' $bridge).Count){throw 'Profile health check failed'}
        $dockState=Get-Content -LiteralPath (Join-Path $root 'runtime\dock-status.json') -Raw|ConvertFrom-Json
        if($dockState.docks -lt 1){throw 'YASB did not create its dock. Complete first-run/font setup and retry Apply.'}
        $menu=Join-Path ([Environment]::GetFolderPath('Programs')) 'Desktop Profiles';[IO.Directory]::CreateDirectory($menu)|Out-Null
        foreach($entry in @(@('Catppuccin','Apply'),@('Restore previous desktop','RestoreCurrent'),@('Restore YASB before MyDockFinder','RestorePreDock'))){$link=$shell.CreateShortcut((Join-Path $menu ($entry[0]+'.lnk')));$link.TargetPath=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe';$link.Arguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Action '+$entry[1];$link.WorkingDirectory=$root;$link.Save()}
        Write-Output 'Catppuccin profile active. Rollback: Restore Previous.cmd / Restore Before MyDock.cmd.'
    }catch{$failure=$_;try{Restore-Current}catch{Write-Warning $_};throw $failure};return
}
[pscustomobject]@{root=$root;profile=if(Test-Path -LiteralPath (Join-Path $root 'runtime\profile.json')){Get-Content -LiteralPath (Join-Path $root 'runtime\profile.json') -Raw|ConvertFrom-Json}else{$null};yasb=@(Owned-Processes 'yasb' $yasb|Select-Object Id,Path);bridge=@(Owned-Processes 'DesktopBridge' $bridge|Select-Object Id,Path);snapshot=(Test-Path -LiteralPath (Join-Path $root 'private\snapshot.json'))}|ConvertTo-Json -Depth 6
