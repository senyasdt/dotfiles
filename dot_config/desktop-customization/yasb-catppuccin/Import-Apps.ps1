param([string]$Destination=(Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config\yasb\launchpad'),[switch]$Refresh)
$ErrorActionPreference='Stop'
# Shell icon COM interop and System.Drawing use the Windows .NET Framework host.
if($PSVersionTable.PSEdition -eq 'Core'){
    $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-Destination',$Destination)
    if($Refresh){$arguments+='-Refresh'}
    & (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') @arguments
    if($LASTEXITCODE -ne 0){throw 'Windows application importer failed'}
    return
}
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
if(-not ('AppIcons' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'AppIcons.cs') -ReferencedAssemblies System.Drawing}
$file=Join-Path $Destination 'apps.json'
if((Test-Path -LiteralPath $file) -and !$Refresh){return}
$original=if(Test-Path -LiteralPath $file){[IO.File]::ReadAllBytes($file)}else{$null}
[IO.Directory]::CreateDirectory((Join-Path $Destination 'icons'))|Out-Null
$shell=New-Object -ComObject Shell.Application
$wsh=New-Object -ComObject WScript.Shell
$entries=New-Object 'System.Collections.Generic.List[object]'
$seen=@{}
$id=0
function Add-App([string]$title,[string]$path,[string]$target){
    if(!$title -or !$path){return}
    $key=$title.Trim().ToLowerInvariant()
    if($seen.ContainsKey($key)){return};$seen[$key]=$true
    $script:id++
    $iconPath=Join-Path $Destination ("icons\app-{0}.png" -f $script:id)
    $parsingName=if($path.StartsWith('explorer.exe shell:AppsFolder\')){$path.Substring(13)}else{$path}
    if(![AppIcons]::Save($parsingName,$iconPath)){
        $icon=$null
        try {if($target -and (Test-Path -LiteralPath $target -PathType Leaf)){$icon=[Drawing.Icon]::ExtractAssociatedIcon($target)}}catch{}
        if(!$icon){$icon=[Drawing.SystemIcons]::Application.Clone()}
        $bitmap=$icon.ToBitmap();try{$bitmap.Save($iconPath,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose();$icon.Dispose()}
    }
    $entries.Add([ordered]@{id=$script:id;title=$title.Trim();path=$path;icon=$iconPath;group=''})
}
foreach($folder in @([Environment]::GetFolderPath('Programs'),[Environment]::GetFolderPath('CommonPrograms'))){
    if(Test-Path -LiteralPath $folder){foreach($f in Get-ChildItem -LiteralPath $folder -Filter *.lnk -Recurse -File -ErrorAction SilentlyContinue|Sort-Object BaseName){
        $shortcut=$wsh.CreateShortcut($f.FullName);Add-App $f.BaseName $f.FullName ([Environment]::ExpandEnvironmentVariables($shortcut.TargetPath))
    }}
}
# AppsFolder includes packaged applications and registered desktop apps.
$apps=$shell.NameSpace('shell:AppsFolder')
foreach($item in $apps.Items()){Add-App $item.Name ('explorer.exe shell:AppsFolder\'+$item.Path) ''}
# Keep the native library reachable even if an application has no Start-menu entry.
Add-App 'Все приложения Windows' 'explorer.exe shell:AppsFolder' "$env:WINDIR\explorer.exe"
if(!$entries.Count){throw 'No applications found; existing catalog left untouched'}
# Preserve every discovered launcher; apply the portable grouping before publishing.
$grouped=@(& (Join-Path $PSScriptRoot 'Launchpad-Layout.ps1') -Action Transform -Apps $entries.ToArray())
if($grouped.Count -ne $entries.Count){throw 'Layout changed entry count; existing catalog left untouched'}
$json=ConvertTo-Json -InputObject $grouped -Depth 20
$temp=Join-Path $Destination ([IO.Path]::GetRandomFileName())
try{
    [IO.File]::WriteAllText($temp,$json,(New-Object Text.UTF8Encoding($false)))
    if($null -ne $original){
        if([Convert]::ToBase64String([IO.File]::ReadAllBytes($file)) -cne [Convert]::ToBase64String($original)){throw 'Catalog changed during import; left untouched'}
        $backupDir=Join-Path $PSScriptRoot 'private\launchpad-import-backups'
        [IO.Directory]::CreateDirectory($backupDir)|Out-Null
        $backup=Join-Path $backupDir ((Get-Date -Format 'yyyyMMdd-HHmmssfff')+'-apps.json')
        [IO.File]::Replace($temp,$file,$backup)
    }else{[IO.File]::Move($temp,$file)}
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp}}
[pscustomobject]@{applications=$entries.Count;catalog=$file}
