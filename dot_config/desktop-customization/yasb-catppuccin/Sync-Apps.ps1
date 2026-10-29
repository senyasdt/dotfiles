param(
    [string]$Destination=(Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config\yasb\launchpad'),
    [switch]$Preview,
    [switch]$FunctionsOnly
)
$ErrorActionPreference='Stop'

function App-Key([string]$text) { return ($text.Trim() -replace '\s+',' ').ToLowerInvariant() }
function Target-Key([string]$text) { return (App-Key $text).Replace('/','\') }
function Merge-Apps($Current,$Candidates,$Identities,$PreviouslySeen,$PreviouslySeenKeys=@()) {
    $result=New-Object 'System.Collections.Generic.List[object]'
    $keys=@{};$titles=@{};$previous=@{};$added=@();$repaired=@();$ignored=@()
    foreach($title in $PreviouslySeen){$previous[(App-Key $title)]=$true}
    $previousKeys=@{};foreach($key in $PreviouslySeenKeys){if($key){$previousKeys[$key]=$true}}
    $maxId=0
    foreach($app in $Current){
        if(!$app.title -or $null -eq $app.id){throw 'Invalid catalog entry'}
        if($result | Where-Object id -eq $app.id){throw 'Duplicate catalog ID'}
        $result.Add($app);$maxId=[Math]::Max($maxId,[int]$app.id)
        $titles[(App-Key $app.title)]=$app
        foreach($key in $Identities[[string]$app.id]){$keys[$key]=$true}
    }
    foreach($candidate in $Candidates){
        $title=App-Key $candidate.title
        $matched=@($candidate.keys | Where-Object {$_ -and $keys.ContainsKey($_)}).Count -gt 0
        if($titles.ContainsKey($title)){
            $existing=$titles[$title]
            # Only repair a missing launcher. Never replace a live custom command.
            if($candidate.path -ne $existing.path -and $candidate.valid -and $Identities[('invalid|'+$existing.id)]){
                $copy=[ordered]@{};foreach($p in $existing.PSObject.Properties){$copy[$p.Name]=$p.Value}
                $copy.path=$candidate.path
                $replacement=[pscustomobject]$copy
                $index=$result.IndexOf($existing);$result[$index]=$replacement;$titles[$title]=$replacement
                $Identities[('invalid|'+$existing.id)]=$false
                $repaired+=@($replacement)
            }
            foreach($key in $candidate.keys){if($key){$keys[$key]=$true}}
            continue
        }
        if($matched){continue}
        # A previously discovered title absent from the catalog was removed in YASB.
        if($previous.ContainsKey($title) -or @($candidate.keys | Where-Object {$_ -and $previousKeys.ContainsKey($_)}).Count){$ignored+=@($candidate.title);continue}
        $maxId++
        $app=[pscustomobject][ordered]@{id=$maxId;title=$candidate.title;path=$candidate.path;icon='';group=$candidate.group}
        $result.Add($app);$added+=@($app);$titles[$title]=$app
        foreach($key in $candidate.keys){if($key){$keys[$key]=$true}}
    }
    [pscustomobject]@{apps=@($result.ToArray());added=@($added);repaired=@($repaired);ignored=@($ignored)}
}
if($FunctionsOnly){return}
if($PSVersionTable.PSEdition -eq 'Core'){
    $arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-Destination',$Destination)
    if($Preview){$arguments+='-Preview'}
    & (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') @arguments
    if($LASTEXITCODE -ne 0){throw 'Launchpad sync failed'}
    return
}
$mutex=New-Object Threading.Mutex($false,('Local\Druzh.LaunchpadSync.'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$locked=$false
try {
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(!$locked){return}
    $file=Join-Path $Destination 'apps.json'
    $stateDir=Join-Path $Destination 'auto-sync'
    $stateFile=Join-Path $stateDir 'state.json'
    $original=if([IO.File]::Exists($file)){[IO.File]::ReadAllBytes($file)}else{$null}
    $current=@()
    if($null -ne $original){$current=ConvertFrom-Json -InputObject ([Text.Encoding]::UTF8.GetString($original))}
    if($null -ne $original -and $current -isnot [Array]){throw 'Expected catalog array; left untouched'}
    $state=if([IO.File]::Exists($stateFile)){ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($stateFile))}else{$null}
    $wsh=New-Object -ComObject WScript.Shell
    $shell=New-Object -ComObject Shell.Application
    $candidates=New-Object 'System.Collections.Generic.List[object]'
    $discoveryErrors=New-Object 'System.Collections.Generic.List[string]'
    function Launcher-Keys([string]$path){
        $keys=@('path|'+(App-Key $path))
        if($path -match '(?i)\.lnk$' -and [IO.File]::Exists($path)){
            $link=$wsh.CreateShortcut($path)
            if($link.TargetPath){$keys+=('target|'+(Target-Key $link.TargetPath)+'|'+$link.Arguments.Trim())}
        }elseif($path -match '^(?i)explorer\.exe\s+shell:AppsFolder\\(.+)$'){
            $keys+=('app|'+(App-Key $Matches[1]))
        }elseif($path -match '^(?i)steam://(?:run|rungameid)/(\d+)'){
            $keys+=('steam|'+$Matches[1])
        }elseif([IO.File]::Exists($path)){$keys+=('target|'+(Target-Key $path)+'|')}
        return $keys
    }
    function Add-Candidate([string]$title,[string]$path,[string]$target,[string]$group='', [string[]]$extraKeys=@()){
        if(!$title -or !$path){return}
        if($title -match '(?i)^uninstall\b|^unins\d|деинсталл|^удалени|^справка|^help\b|documentation|release notes|readme|website|^support$|^RustDesk Tray$'){return}
        if($target -and ![IO.File]::Exists($target)){return}
        $candidates.Add([pscustomobject]@{title=$title.Trim();path=$path;target=$target;group=$group;keys=@(Launcher-Keys $path)+$extraKeys;valid=$true})
    }
    # Start menu (without Startup), both desktops. Never import documents or web links.
    foreach($folder in @([Environment]::GetFolderPath('Programs'),[Environment]::GetFolderPath('CommonPrograms'),[Environment]::GetFolderPath('DesktopDirectory'),[Environment]::GetFolderPath('CommonDesktopDirectory'))){
        if(!$folder -or ![IO.Directory]::Exists($folder)){continue}
        foreach($f in Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -Recurse -File -ErrorAction Stop | Sort-Object FullName){
            if($f.DirectoryName -match '(?i)\\Startup(?:\\|$)'){continue}
            try{
                $link=$wsh.CreateShortcut($f.FullName);$target=[Environment]::ExpandEnvironmentVariables([string]$link.TargetPath)
                if($target -match '(?i)\.(exe|com|bat|cmd|ps1)$' -and $link.Arguments -notmatch '(?i)--?uninstall|^/x\s'){
                    Add-Candidate $f.BaseName $f.FullName $target
                }
            }catch{$discoveryErrors.Add('Shortcut: '+$f.Name)}
        }
    }
    $namespace=$shell.NameSpace('shell:AppsFolder')
    if(!$namespace){throw 'AppsFolder unavailable; catalog left untouched'}
    foreach($item in $namespace.Items()){
        try{
            $appId=[string]$item.ExtendedProperty('System.AppUserModel.ID');if(!$appId){$appId=[string]$item.Path}
            $target=[string]$item.ExtendedProperty('System.Link.TargetParsingPath')
            $arguments=[string]$item.ExtendedProperty('System.Link.Arguments')
            if($appId -match '^[a-zA-Z][a-zA-Z0-9+.-]*://'){continue}
            if($target -and ($target -notmatch '(?i)\.exe$' -or ![IO.File]::Exists($target))){continue}
            if(!$target -and $appId -notmatch '^[^\\/:]+_[^\\/:]+![^\\]+$'){continue}
            if($arguments -match '(?i)--?uninstall|^/x\s'){continue}
            $keys=if($target){@('target|'+(Target-Key $target)+'|'+$arguments.Trim())}else{@()}
            Add-Candidate ([string]$item.Name) ('explorer.exe shell:AppsFolder\'+$appId) $target '' $keys
        }catch{$discoveryErrors.Add('AppsFolder item')}
    }
    # Installed Steam games may have no Start-menu or desktop shortcut at all.
    $steamRoots=New-Object 'System.Collections.Generic.List[string]'
    foreach($regPath in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')){
        if(Test-Path -LiteralPath $regPath){$reg=Get-ItemProperty -LiteralPath $regPath;foreach($property in @('SteamPath','InstallPath')){if($reg.$property -and [IO.Directory]::Exists($reg.$property) -and !$steamRoots.Contains($reg.$property)){$steamRoots.Add($reg.$property)}}}
    }
    foreach($root in @($steamRoots.ToArray())){
        $library=Join-Path $root 'steamapps\libraryfolders.vdf'
        if([IO.File]::Exists($library)){foreach($match in [regex]::Matches([IO.File]::ReadAllText($library),'"path"\s+"([^"]+)"')){
            $path=$match.Groups[1].Value.Replace('\\','\')
            if(!$path.StartsWith('\\') -and [IO.Directory]::Exists($path) -and !$steamRoots.Contains($path)){$steamRoots.Add($path)}
        }}
    }
    foreach($root in $steamRoots){
        $steamapps=Join-Path $root 'steamapps';if(![IO.Directory]::Exists($steamapps)){continue}
        foreach($manifest in Get-ChildItem -LiteralPath $steamapps -Filter 'appmanifest_*.acf' -File){
            $text=[IO.File]::ReadAllText($manifest.FullName)
            $id=[regex]::Match($text,'"appid"\s+"(\d+)"').Groups[1].Value
            $title=[regex]::Match($text,'"name"\s+"([^"]+)"').Groups[1].Value
            $dir=[regex]::Match($text,'"installdir"\s+"([^"]+)"').Groups[1].Value
            if(!$id -or !$dir -or $id -eq '228980' -or $title -match '(?i)redistribut|dedicated server|Steamworks'){continue}
            if([IO.Directory]::Exists((Join-Path $steamapps ('common\'+$dir)))){
                $steamKeys=@(('steam|'+$id),('app|steam://rungameid/'+$id),('app|steam://run/'+$id))
                Add-Candidate $title ('steam://rungameid/'+$id) '' 'Игры' $steamKeys
            }
        }
    }
    # Conservative registry fallback: only an existing executable explicitly used
    # as the product icon, never an uninstall command or a guessed folder scan.
    foreach($regRoot in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')){
        if(!(Test-Path -LiteralPath $regRoot)){continue}
        foreach($key in Get-ChildItem -LiteralPath $regRoot){
            $reg=Get-ItemProperty -LiteralPath $key.PSPath
            if(!$reg.DisplayName -or $reg.SystemComponent -or $reg.ParentKeyName -or $key.PSChildName -like 'Steam App *'){continue}
            if($reg.DisplayName -match '(?i)driver|драйвер|runtime|redistribut|SDK|Software Development Kit|update|service|plugin|Git LFS|command.line|Кнопки сервисов'){continue}
            $target=([Environment]::ExpandEnvironmentVariables([string]$reg.DisplayIcon) -replace ',\s*-?\d+\s*$','').Trim('"').Replace('/','\')
            if(!$target -or $target.StartsWith('\\') -or $target -notmatch '(?i)\.exe$' -or $target -match '(?i)\\(?:unins[^\\]*|msiexec)\.exe$|setup|installer|\\Package Cache\\'){continue}
            if(![IO.File]::Exists($target)){continue}
            if(@($candidates | Where-Object { $_.target -and (Target-Key $_.target) -eq (Target-Key $target) }).Count){continue}
            $title=([string]$reg.DisplayName -replace '(?i)[,\s]+(?:версия\s+|version\s+|v)?\d+\.\d+(?:\.\d+)*.*$','').Trim()
            $group=if($target -match '(?i)\\(?:EA Games|Games)\\'){'Игры'}else{''}
            Add-Candidate $title $target $target $group @('target|'+(Target-Key $target)+'|')
        }
    }
    # Explicit portable launchers for products with no registered shortcut/icon.
    $extra=Join-Path $PSScriptRoot 'launchpad-extra.json'
    if([IO.File]::Exists($extra)){foreach($entry in (ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($extra)))){
        $path=[Environment]::ExpandEnvironmentVariables($entry.path.Replace('__DESKTOP__',(Split-Path $PSScriptRoot -Parent)))
        Add-Candidate $entry.title $path $path $entry.group
    }}
    Add-Candidate 'Все приложения Windows' 'explorer.exe shell:AppsFolder' (Join-Path $env:WINDIR 'explorer.exe')
    $identities=@{}
    foreach($app in $current){
        $identities[[string]$app.id]=@(Launcher-Keys $app.path)
        if($app.path -match '^[a-zA-Z]:\\.+\.(?i:lnk|exe|com|bat|cmd|ps1)$'){
            $invalid=![IO.File]::Exists($app.path)
            if(!$invalid -and $app.path -match '(?i)\.lnk$'){
                $target=$wsh.CreateShortcut($app.path).TargetPath
                if($target -match '^[a-zA-Z]:\\'){$invalid=![IO.File]::Exists($target) -and ![IO.Directory]::Exists($target)}
            }
            if($invalid){$identities[('invalid|'+$app.id)]=$true}
        }
    }
    $merged=Merge-Apps $current $candidates.ToArray() $identities @($state.seenTitles) @($state.seenKeys)
    $summary=[ordered]@{time=[DateTimeOffset]::Now.ToString('o');before=@($current).Count;after=$merged.apps.Count;added=@($merged.added | ForEach-Object {$_.title});repaired=@($merged.repaired | ForEach-Object {$_.title});ignored=@($merged.ignored);discoveryErrors=@($discoveryErrors.ToArray());preview=[bool]$Preview}
    if($Preview){ConvertTo-Json -InputObject $summary -Depth 6;return}
    if($discoveryErrors.Count){Write-Warning 'Some launchers could not be inspected; details are in auto-sync/state.json. Existing entries are retained.'}
    [void][IO.Directory]::CreateDirectory($stateDir)
    [void][IO.Directory]::CreateDirectory((Join-Path $Destination 'icons'))
    $utf8=New-Object Text.UTF8Encoding($false)
    if($merged.added.Count -or $merged.repaired.Count){
        Add-Type -AssemblyName System.Drawing
        if(!('AppIcons' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'AppIcons.cs') -ReferencedAssemblies System.Drawing}
        foreach($app in $merged.added){
            # New random names cannot overwrite an icon still used by YASB.
            $icon=Join-Path $Destination ('icons\sync-'+[Guid]::NewGuid().ToString('N')+'.png')
            $candidate=$candidates | Where-Object title -eq $app.title | Select-Object -First 1
            $parsing=if($candidate.target){$candidate.target}elseif($candidate.path.StartsWith('explorer.exe ')){$candidate.path.Substring(13)}else{$candidate.path}
            if(![AppIcons]::Save($parsing,$icon)){
                $bitmap=[Drawing.SystemIcons]::Application.ToBitmap();try{$bitmap.Save($icon,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
            }
            $app.icon=$icon
        }
        if($null -eq $original){$merged.apps=@(& (Join-Path $PSScriptRoot 'Launchpad-Layout.ps1') -Action Transform -Apps $merged.apps)}
        $temp=Join-Path $Destination ([IO.Path]::GetRandomFileName())
        try{
            [IO.File]::WriteAllText($temp,(ConvertTo-Json -InputObject @($merged.apps) -Depth 30),$utf8)
            if($null -ne $original){
                if([Convert]::ToBase64String([IO.File]::ReadAllBytes($file)) -cne [Convert]::ToBase64String($original)){throw 'Catalog changed during sync; retry on next run'}
                $backup=Join-Path $stateDir ((Get-Date -Format 'yyyyMMdd-HHmmssfff')+'-apps.json')
                [IO.File]::Replace($temp,$file,$backup)
            }else{[IO.File]::Move($temp,$file)}
        }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
    }
    # Persist only after a successful/no-op catalog update. Keep deleted titles
    # even while their application is temporarily uninstalled or disk is offline.
    $seen=@(@($state.seenTitles)+@($candidates.title) | Where-Object {$_} | Sort-Object -Unique)
    $seenKeys=@(@($state.seenKeys)+@($candidates | ForEach-Object {$_.keys}) | Where-Object {$_} | Sort-Object -Unique)
    $stateTemp=Join-Path $stateDir ([IO.Path]::GetRandomFileName())
    try{
        [IO.File]::WriteAllText($stateTemp,(ConvertTo-Json -InputObject @{version=2;seenTitles=$seen;seenKeys=$seenKeys;lastRun=$summary} -Depth 8),$utf8)
        if([IO.File]::Exists($stateFile)){
            [IO.File]::Replace($stateTemp,$stateFile,(Join-Path $stateDir 'state.previous.json'))
        }else{[IO.File]::Move($stateTemp,$stateFile)}
    }finally{if([IO.File]::Exists($stateTemp)){[IO.File]::Delete($stateTemp)}}
    Get-ChildItem -LiteralPath $stateDir -Filter '*-apps.json' -File | Sort-Object Name -Descending | Select-Object -Skip 10 | ForEach-Object {[IO.File]::Delete($_.FullName)}
    ConvertTo-Json -InputObject $summary -Depth 6
}finally{if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
