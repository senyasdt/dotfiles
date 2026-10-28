param(
    [string]$CatalogPath=(Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config\yasb\launchpad\apps.json'),
    [string]$ReportDirectory
)
$ErrorActionPreference='Stop'
# Read-only static validation: never launch a shortcut, resolve an MSI product,
# fetch a URL, probe UNC shares, or modify the live catalog / Start menu.
if(!$ReportDirectory){$ReportDirectory=Join-Path $PSScriptRoot ('private\launchpad-audit-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))}
$catalog=[IO.Path]::GetFullPath($CatalogPath)
$report=[IO.Path]::GetFullPath($ReportDirectory)
if(!(Test-Path -LiteralPath $catalog -PathType Leaf)){throw 'Catalog does not exist'}
[IO.Directory]::CreateDirectory($report)|Out-Null
$bytes=[IO.File]::ReadAllBytes($catalog)
$sha=[Security.Cryptography.SHA256]::Create()
try{$originalHash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')}finally{$sha.Dispose()}
$backup=Join-Path $report 'apps-before.json'
if(Test-Path -LiteralPath $backup){throw 'Choose a new report directory; snapshot already exists'}
[IO.File]::WriteAllBytes($backup,$bytes)
$apps=ConvertFrom-Json -InputObject ([Text.Encoding]::UTF8.GetString($bytes))
if($apps -isnot [Array]){throw 'Expected a JSON array'}
$wsh=New-Object -ComObject WScript.Shell
$shell=New-Object -ComObject Shell.Application
$namespace=$shell.NameSpace('shell:AppsFolder')
$registered=@{}
if($namespace){foreach($item in $namespace.Items()){
    foreach($key in @([string]$item.Path,[string]$item.ExtendedProperty('System.AppUserModel.ID'))){if($key){$registered[$key]=$true}}
}}
$steamRoots=New-Object 'System.Collections.Generic.List[string]'
foreach($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')){
    if(Test-Path -LiteralPath $key){$reg=Get-ItemProperty -LiteralPath $key;foreach($name in @('SteamPath','InstallPath')){if($reg.$name -and [IO.Directory]::Exists([string]$reg.$name)){if(!$steamRoots.Contains([string]$reg.$name)){$steamRoots.Add([string]$reg.$name)}}}}
}
foreach($root in @($steamRoots.ToArray())){
    $libraryFile=Join-Path $root 'steamapps\libraryfolders.vdf'
    if([IO.File]::Exists($libraryFile)){
        $libraryText=[IO.File]::ReadAllText($libraryFile)
        foreach($match in [regex]::Matches($libraryText,'"path"\s+"([^"]+)"')){
            $path=$match.Groups[1].Value.Replace('\\','\')
            if(!$path.StartsWith('\\') -and [IO.Directory]::Exists($path) -and !$steamRoots.Contains($path)){$steamRoots.Add($path)}
        }
    }
}
function Check-Target([string]$target,[string]$arguments=''){
    $target=[Environment]::ExpandEnvironmentVariables($target).Trim().Trim('"')
    $result=[ordered]@{status='review';reason='unsupported-target';target=$target;arguments=$arguments;canonical=''}
    if(!$target){$result.reason='empty-target';return $result}
    if($target.StartsWith('\\')){$result.reason='network-target-not-probed';return $result}
    if($target -match '%[^%]+%'){$result.reason='unexpanded-environment-variable';return $result}
    if($target -match '^(?i)(shell:|::)'){
        $result.reason='virtual-shell-target';return $result
    }
    $gameMatch=[regex]::Match(($target+' '+$arguments),'(?i)(?:-applaunch\s+|steam://(?:run|rungameid)/)(\d+)')
    if($target -match '^[a-zA-Z]:[\\/]'){
        $result.canonical=$target.ToLowerInvariant()+'|'+$arguments.Trim()
        if([IO.File]::Exists($target) -or [IO.Directory]::Exists($target)){$result.status='valid';$result.reason='local-target-exists'}
        elseif($target -match '(?i)\\Windows\\Installer\\'){$result.reason='possible-advertised-msi-shortcut'}
        elseif(![IO.Directory]::Exists([IO.Path]::GetPathRoot($target))){$result.reason='local-drive-unavailable'}
        else{
            try{[void][IO.File]::GetAttributes($target);$result.status='valid';$result.reason='local-target-exists'}
            catch [UnauthorizedAccessException]{$result.reason='target-access-denied'}
            catch [IO.FileNotFoundException]{$result.status='broken';$result.reason='missing-local-target'}
            catch [IO.DirectoryNotFoundException]{$result.status='broken';$result.reason='missing-local-target'}
            catch{$result.reason='target-inspection-error'}
        }
    }elseif($target -match '^([a-zA-Z][a-zA-Z0-9+.-]*):'){
        $protocol=$Matches[1]
        $result.canonical=$target+'|'+$arguments.Trim()
        if($protocol -in @('http','https')){$result.status='valid';$result.reason='web-url-not-fetched'}
        elseif(Test-Path -LiteralPath ('Registry::HKEY_CLASSES_ROOT\'+$protocol)){
            $protocolKey=Get-Item -LiteralPath ('Registry::HKEY_CLASSES_ROOT\'+$protocol)
            if($null -ne $protocolKey.GetValue('URL Protocol')){$result.status='valid';$result.reason='registered-url-protocol'}
            else{$result.reason='protocol-registration-uncertain'}
        }else{$result.status='broken';$result.reason='unregistered-url-protocol'}
    }
    if($result.status -eq 'valid' -and $gameMatch.Success){
        $gameId=$gameMatch.Groups[1].Value
        if($steamRoots.Count){
            $found=$false
            foreach($root in $steamRoots){if([IO.File]::Exists((Join-Path $root ('steamapps\appmanifest_'+$gameId+'.acf')))){$found=$true;break}}
            if(!$found){$result.status='review';$result.reason='steam-game-manifest-not-found'}
            else{$result.reason='steam-game-manifest-exists'}
        }else{$result.status='review';$result.reason='steam-libraries-not-found'}
    }
    return $result
}
$results=New-Object 'System.Collections.Generic.List[object]'
$number=0
foreach($app in $apps){
    $number++
    $path=[string]$app.path
    $row=[ordered]@{index=$number;id=$app.id;title=[string]$app.title;group=[string]$app.group;path=$path;kind='';status='review';reason='unsupported-entry';target='';arguments='';canonical='';suggestedPath='';suggestedStatus='';duplicateOf=$null;iconExists=$false;damagedTitle=$false}
    $row.iconExists=[IO.File]::Exists([string]$app.icon)
    $row.damagedTitle=([string]$app.title).Contains([string][char]0xFFFD)
    try{
        if($path -match '^(?i)explorer\.exe\s+shell:AppsFolder\\(.*)$'){
            $payload=$Matches[1];$row.kind='AppsFolder';$row.target=$payload
            if($payload -match '^(?:[a-zA-Z]:[\\/]|[a-zA-Z][a-zA-Z0-9+.-]*://)'){
                $candidate=Check-Target $payload
                # AppsFolder can accept legacy path / URL parsing names. A strange
                # string alone is not proof that ShellExecute will fail.
                $parsed=if($namespace){$namespace.ParseName($payload)}else{$null}
                $row.status='review';$row.reason=if($parsed){'legacy-appsfolder-path-resolves'}else{'legacy-appsfolder-path-unresolved'}
                $row.suggestedPath=$payload;$row.suggestedStatus=$candidate.status
                $row.canonical=$candidate.canonical
            }elseif($registered.ContainsKey($payload)){
                $row.status='valid';$row.reason='registered-app-id';$row.canonical='app-id|'+$payload.ToLowerInvariant()
            }else{
                $parsed=if($namespace){$namespace.ParseName($payload)}else{$null}
                if($parsed){$row.status='valid';$row.reason='shell-app-id-resolves';$row.canonical='app-id|'+$payload.ToLowerInvariant()}
                else{$row.status='broken';$row.reason='app-id-not-registered'}
            }
        }elseif($path -match '^(?i)explorer\.exe\s+shell:AppsFolder$'){
            $row.kind='SystemLibrary';$row.status='valid';$row.reason='system-app-library';$row.canonical='system-app-library'
        }elseif($path -match '(?i)\.lnk$'){
            $row.kind='Shortcut'
            if($path.StartsWith('\\')){$row.reason='network-shortcut-not-probed'}
            elseif(![IO.File]::Exists($path)){$row.status='broken';$row.reason='missing-shortcut'}
            else{
                $link=$wsh.CreateShortcut($path)
                $check=Check-Target ([string]$link.TargetPath) ([string]$link.Arguments)
                foreach($key in @('status','reason','target','arguments','canonical')){$row[$key]=$check[$key]}
                if($row.reason -in @('empty-target','virtual-shell-target')){
                    $folder=$shell.NameSpace([IO.Path]::GetDirectoryName($path))
                    $item=if($folder){$folder.ParseName([IO.Path]::GetFileName($path))}else{$null}
                    $appId=if($item){[string]$item.ExtendedProperty('System.AppUserModel.ID')}else{''}
                    if($appId -and $registered.ContainsKey($appId)){$row.status='valid';$row.reason='shortcut-to-registered-app-id';$row.canonical='app-id|'+$appId.ToLowerInvariant()}
                    elseif($item){
                        $parsing=[string]$item.ExtendedProperty('System.Link.TargetParsingPath')
                        if($parsing){
                            $check=Check-Target $parsing ([string]$link.Arguments)
                            foreach($key in @('status','reason','target','arguments','canonical')){$row[$key]=$check[$key]}
                        }
                    }
                }
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject($link)
            }
        }else{
            $row.kind='Direct'
            $check=Check-Target $path
            foreach($key in @('status','reason','target','arguments','canonical')){$row[$key]=$check[$key]}
        }
    }catch{$row.status='review';$row.reason='inspection-error';$row.target=$_.Exception.GetType().Name}
    $results.Add([pscustomobject]$row)
    if(($number % 100) -eq 0){Write-Output ('Checked '+$number+' entries')}
}
# Duplicate checks are informational; never remove entries in different groups.
$seen=@{}
foreach($row in $results){
    if($row.canonical){
        if($seen.ContainsKey($row.canonical)){$row.duplicateOf=$seen[$row.canonical]}
        else{$seen[$row.canonical]=$row.id}
    }
}
$currentHash=(Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash
$summary=[ordered]@{createdAt=[DateTimeOffset]::Now.ToString('o');catalog=$catalog;catalogHash=$originalHash;catalogChangedDuringAudit=($currentHash -ne $originalHash);total=$results.Count;valid=@($results|Where-Object status -EQ 'valid').Count;broken=@($results|Where-Object status -EQ 'broken').Count;review=@($results|Where-Object status -EQ 'review').Count;duplicates=@($results|Where-Object {$null -ne $_.duplicateOf}).Count;damagedTitles=@($results|Where-Object damagedTitle).Count;missingIcons=@($results|Where-Object {!$_.iconExists}).Count;steamLibraries=$steamRoots.Count;registeredAppIds=$registered.Count}
$utf8=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $report 'audit.json'),(ConvertTo-Json -InputObject @{summary=$summary;entries=@($results.ToArray())} -Depth 8),$utf8)
$results|Export-Csv -LiteralPath (Join-Path $report 'audit.csv') -NoTypeInformation -Encoding UTF8
ConvertTo-Json -InputObject $summary -Depth 4
