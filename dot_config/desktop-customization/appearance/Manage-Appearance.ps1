[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [ValidateSet('Status','Apply','Restore')][string]$Action='Status',
    [string]$Backup,
    [string]$TargetHome
)
$ErrorActionPreference='Stop'
$profileRoot=if($TargetHome){[IO.Path]::GetFullPath($TargetHome)}else{[Environment]::GetFolderPath('UserProfile')}
$roamingRoot=if($TargetHome){Join-Path $profileRoot 'AppData\Roaming'}else{$env:APPDATA}
$localRoot=if($TargetHome){Join-Path $profileRoot 'AppData\Local'}else{$env:LOCALAPPDATA}
$root=$PSScriptRoot
$palette=Get-Content -LiteralPath (Join-Path $root 'palette.json') -Raw|ConvertFrom-Json
$wezterm=Join-Path $profileRoot '.config\wezterm'
$code=Join-Path $roamingRoot 'Code\User\settings.json'
$terminal=Join-Path $localRoot 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$allowed=@($code,$terminal,(Join-Path $wezterm 'themes\cold-grey.toml'),(Join-Path $wezterm 'theme'),(Join-Path $wezterm 'active_scheme.toml'))
function Hash($path){if(Test-Path -LiteralPath $path -PathType Leaf){return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash};return $null}
function Write-Utf8($path,$content){[void][IO.Directory]::CreateDirectory((Split-Path $path));[IO.File]::WriteAllText($path,$content,(New-Object Text.UTF8Encoding($false)))}
function Read-StrictJson($path){
    $raw=[IO.File]::ReadAllText($path)
    $unquoted=[regex]::Replace($raw,'"(?:\\.|[^"\\])*"','""')
    if($unquoted -match '//|/\*'){throw ('JSONC comments require a manual appearance merge: '+$path)}
    return ($raw|ConvertFrom-Json)
}
function Merge-Object($target,$patch){
    foreach($entry in $patch.PSObject.Properties){
        $current=$target.PSObject.Properties[$entry.Name]
        if($current -and $entry.Value -is [pscustomobject] -and $current.Value -is [pscustomobject]){Merge-Object $current.Value $entry.Value}
        elseif($current){$current.Value=$entry.Value}
        else{$target|Add-Member -NotePropertyName $entry.Name -NotePropertyValue $entry.Value}
    }
}
if($Action -eq 'Status'){
    [pscustomobject]@{Palette=$palette.name;CodeConfig=(Test-Path -LiteralPath $code);TerminalConfig=(Test-Path -LiteralPath $terminal);WezTermConfig=(Test-Path -LiteralPath $wezterm);Chrome='Owner-managed standard appearance; excluded from custom adapters.'}
    return
}
if($Action -eq 'Restore'){
    if(!$Backup){throw 'Specify -Backup with an appearance backup directory.'}
    $backupRoot=[IO.Path]::GetFullPath((Join-Path $root 'backup')).TrimEnd('\')+'\'
    $resolved=[IO.Path]::GetFullPath($Backup).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($backupRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Backup must be inside this profile backup directory.'}
    $manifest=Get-Content -LiteralPath (Join-Path $resolved 'manifest.json') -Raw|ConvertFrom-Json
    $seen=@{}
    foreach($f in $manifest){
        if($f.Path -notin $allowed -or $seen.ContainsKey($f.Path)){throw 'Unexpected or duplicate restore target.'}
        if($f.Index -isnot [int] -or $f.Index -lt 0 -or $f.Index -ge $allowed.Count){throw 'Invalid backup file index.'}
        $seen[$f.Path]=$true
        if((Hash $f.Path) -ne $f.AppliedSHA256){throw ('File changed after applying the theme; compare manually: '+$f.Path)}
        if($f.Existed -and (Hash (Join-Path $resolved ($f.Index.ToString()+'.old'))) -ne $f.BeforeSHA256){throw 'Backup checksum mismatch.'}
    }
    if(!$PSCmdlet.ShouldProcess('Saved appearance files','Restore')){return}
    foreach($f in $manifest){
        if($f.Existed){Copy-Item -LiteralPath (Join-Path $resolved ($f.Index.ToString()+'.old')) -Destination $f.Path -Force}
        elseif(Test-Path -LiteralPath $f.Path){Remove-Item -LiteralPath $f.Path}
    }
    Write-Output 'Previous appearance restored; application processes were not restarted.'
    return
}
$writes=New-Object 'Collections.Generic.List[object]'
function Queue($path,$content){if([IO.File]::Exists($path) -and [IO.File]::ReadAllText($path) -ceq $content){return};$writes.Add([pscustomobject]@{Path=$path;Content=$content;BeforeSHA256=(Hash $path)})}
if(Test-Path -LiteralPath $code){
    # Abort on unsupported JSONC instead of erasing comments or unrelated settings.
    $settings=Read-StrictJson $code
    $patch=Get-Content -LiteralPath (Join-Path $root 'vscode.json') -Raw|ConvertFrom-Json
    Merge-Object $settings $patch
    Queue $code (($settings|ConvertTo-Json -Depth 100)+"`n")
}
if(Test-Path -LiteralPath $terminal){
    $settings=Read-StrictJson $terminal
    $scheme=Get-Content -LiteralPath (Join-Path $root 'windows-terminal.json') -Raw|ConvertFrom-Json
    Merge-Object $settings ([pscustomobject]@{theme='dark';profiles=[pscustomobject]@{defaults=[pscustomobject]@{colorScheme=$palette.name;opacity=88;useAcrylic=$true;font=[pscustomobject]@{face=$palette.fonts.code;size=10}}}})
    foreach($item in $settings.profiles.list){if($item.colorScheme -eq 'Catppuccin Macchiato'){$item.colorScheme=$palette.name}}
    $schemes=@($settings.schemes|Where-Object name -NE $palette.name)+@($scheme)
    if($settings.PSObject.Properties['schemes']){$settings.schemes=$schemes}else{$settings|Add-Member -NotePropertyName schemes -NotePropertyValue $schemes}
    Queue $terminal (($settings|ConvertTo-Json -Depth 100)+"`n")
}
if(Test-Path -LiteralPath $wezterm -PathType Container){
    Queue $allowed[2] ([IO.File]::ReadAllText((Join-Path $root 'wezterm.toml')))
    Queue $allowed[3] ($palette.name+"`n")
    Queue $allowed[4] ('theme = "'+$palette.name+'"'+"`n")
}
if(!$writes.Count){Write-Output 'Appearance is already current; no files changed.';return}
if(!$PSCmdlet.ShouldProcess(($writes.Path -join ', '),('Apply '+$palette.name))){return}
$saved=Join-Path $root ('backup\'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
[void][IO.Directory]::CreateDirectory($saved)
$manifest=New-Object 'Collections.Generic.List[object]'
foreach($w in $writes){
    if((Hash $w.Path) -ne $w.BeforeSHA256){throw ('Configuration changed during preparation: '+$w.Path)}
    $index=$manifest.Count;$existed=Test-Path -LiteralPath $w.Path -PathType Leaf
    if($existed){Copy-Item -LiteralPath $w.Path -Destination (Join-Path $saved ($index.ToString()+'.old'));if((Hash (Join-Path $saved ($index.ToString()+'.old'))) -ne $w.BeforeSHA256){throw 'Backup verification failed'}}
    $manifest.Add([pscustomobject]@{Index=$index;Path=$w.Path;Existed=$existed;BeforeSHA256=$w.BeforeSHA256;AppliedSHA256=$w.BeforeSHA256})
}
# Save recovery information before the first write and after every completed write.
$manifest|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $saved 'manifest.json') -Encoding UTF8
for($i=0;$i -lt $writes.Count;$i++){
    if((Hash $writes[$i].Path) -ne $writes[$i].BeforeSHA256){throw ('Configuration changed before writing: '+$writes[$i].Path)}
    Write-Utf8 $writes[$i].Path $writes[$i].Content
    $manifest[$i].AppliedSHA256=Hash $writes[$i].Path
    $manifest|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $saved 'manifest.json') -Encoding UTF8
}
[pscustomobject]@{Applied=$palette.name;ChangedFiles=$writes.Count;Backup=$saved;ProcessesRestarted=0;Chrome='Owner-managed standard appearance; no browser preferences changed.'}
