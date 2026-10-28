$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$private=Join-Path $root 'private'
$marker=Join-Path $private 'snapshot.json'
if(Test-Path -LiteralPath $marker){Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json|Select-Object createdAt,backup|ConvertTo-Json;return}
$backup=Join-Path $private ([DateTime]::Now.ToString('yyyyMMdd-HHmmss'))
[IO.Directory]::CreateDirectory($backup)|Out-Null
$profileRoot=[Environment]::GetFolderPath('UserProfile')
$startup=[Environment]::GetFolderPath('Startup')
$paths=@{
 'yasb-config.yaml'=(Join-Path $profileRoot '.config\yasb\config.yaml');
 'yasb-styles.css'=(Join-Path $profileRoot '.config\yasb\styles.css');
 'komorebi.json'=(Join-Path $profileRoot 'komorebi.json');
 'whkdrc'=(Join-Path $profileRoot '.config\whkdrc');
 'win-hotkeys.ahk'=(Join-Path $profileRoot '.config\autohotkey\mydockfinder-hotkeys.ahk');
 'mydock-config.ini'='C:\Program Files (x86)\Steam\steamapps\common\MyDockFinder\config.ini';
 'launcher-state.json'=(Join-Path (Split-Path $root -Parent) 'script-launcher\runtime\state.json')
}
$records=@()
foreach($key in $paths.Keys){$path=$paths[$key];$exists=Test-Path -LiteralPath $path;$saved=Join-Path $backup $key;if($exists){Copy-Item -LiteralPath $path -Destination $saved};$records+=@{original=$path;backup=$saved;existed=$exists;sha256=if($exists){(Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash}else{$null}}}
foreach($name in @('MyDockFinder.lnk','Finder Widgets.lnk','yasb.cmd','YASB Catppuccin.lnk')){
    $path=Join-Path $startup $name;$exists=Test-Path -LiteralPath $path;$saved=Join-Path $backup $name
    if($exists){Copy-Item -LiteralPath $path -Destination $saved}
    $records+=@{original=$path;backup=$saved;existed=$exists;sha256=if($exists){(Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash}else{$null}}
}
$launchpad=Join-Path $profileRoot '.config\yasb\launchpad'
if(Test-Path -LiteralPath $launchpad){Copy-Item -LiteralPath $launchpad -Destination (Join-Path $backup 'launchpad') -Recurse}
$reg='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$key=Get-Item -LiteralPath $reg
$dockRun=@($key.GetValueNames()|Where-Object {$key.GetValue($_) -is [string] -and $key.GetValue($_) -match 'MyDockFinder|Dock_64\.exe'}|ForEach-Object {@{name=$_;value=$key.GetValue($_)}})
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
$snapshot=@{createdAt=[DateTimeOffset]::Now.ToString('o');backup=$backup;files=$records;dockRun=$dockRun;running=@(Get-Process -Name Dock_64,FinderWidgets,yasb -ErrorAction SilentlyContinue|Where-Object SessionId -EQ $session|Select-Object -ExpandProperty ProcessName);launchpadExisted=(Test-Path -LiteralPath $launchpad)}
$snapshot|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $marker -Encoding utf8
$records|ForEach-Object {if($_.existed -and (Get-FileHash -LiteralPath $_.original -Algorithm SHA256).Hash -ne $_.sha256){throw 'Snapshot verification failed'}}
[pscustomobject]@{createdAt=$snapshot.createdAt;backup=$backup;files=$records.Count;sha256Verified=$true}|ConvertTo-Json
