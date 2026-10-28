[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [ValidateSet('Apply','Export','Transform')][string]$Action='Apply',
    [string]$CatalogPath=(Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config\yasb\launchpad\apps.json'),
    [string]$LayoutPath=(Join-Path $PSScriptRoot 'launchpad-layout.json'),
    [object[]]$Apps
)
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($false)
function Title-Key([string]$title){return ($title.Trim() -replace '\s+',' ').ToLowerInvariant()}
function Family-Key([string]$title){
    $key=Title-Key $title
    if($key -match '^(blender|zbrush|python|idle|kicad|pcb editor|schematic editor|drawing sheet editor|gerber viewer|image converter|calculator tools)\b'){
        return ($key -replace '\b\d+\.\d+(?:\.\d+)*\b','<version>')
    }
    return $key
}
function Read-Json([string]$path){return (Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json)}
function Write-Atomic([string]$path,[string]$text,[byte[]]$expected){
    $parent=Split-Path $path -Parent
    [IO.Directory]::CreateDirectory($parent)|Out-Null
    $temp=Join-Path $parent ([IO.Path]::GetRandomFileName())
    try{
        [IO.File]::WriteAllText($temp,$text,$utf8)
        if(Test-Path -LiteralPath $path){
            if([Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -cne [Convert]::ToBase64String($expected)){throw 'File changed during preparation; left untouched'}
            $backupDir=Join-Path $PSScriptRoot 'private\launchpad-layout-backups'
            [IO.Directory]::CreateDirectory($backupDir)|Out-Null
            $backup=Join-Path $backupDir ((Get-Date -Format 'yyyyMMdd-HHmmssfff')+'-'+[IO.Path]::GetFileName($path))
            [IO.File]::Replace($temp,$path,$backup)
        }else{[IO.File]::Move($temp,$path)}
    }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp}}
}
function Map-Apps($catalog,$layout){
    if($layout.version -ne 1 -or ($null -eq $layout.defaultGroup) -or !$layout.entries){throw 'Invalid Launchpad layout'}
    $exact=@{};$families=@{}
    foreach($entry in $layout.entries){
        if(!$entry.title -or $null -eq $entry.group){throw 'Layout entries require title and group'}
        $key=Title-Key $entry.title
        if($exact.ContainsKey($key)){throw "Duplicate layout title: $($entry.title)"}
        $exact[$key]=$entry
        $family=Family-Key $entry.title
        if(!$families.ContainsKey($family)){$families[$family]=@()}
        $families[$family]+=$entry
    }
    $mapped=foreach($item in $catalog){
        if(!$item.title -or $null -eq $item.id){throw 'Invalid application catalog entry'}
        $entry=$exact[(Title-Key $item.title)]
        if(!$entry){
            $candidates=@($families[(Family-Key $item.title)]|Where-Object {$null -ne $_})
            $groups=@($candidates|Select-Object -ExpandProperty group -Unique)
            # Never guess when saved versions belong to different folders.
            if($groups.Count -eq 1){$entry=$candidates|Sort-Object order|Select-Object -First 1}
        }
        $copy=[ordered]@{}
        if($item -is [System.Collections.IDictionary]){
            foreach($key in $item.Keys){$copy[$key]=$item[$key]}
        }else{foreach($property in $item.PSObject.Properties){$copy[$property.Name]=$property.Value}}
        $copy['group']=if($entry){[string]$entry.group}elseif($item.group){[string]$item.group}else{[string]$layout.defaultGroup}
        [pscustomobject]@{rank=if($entry){[int]$entry.order}else{[int]::MaxValue};item=[pscustomobject]$copy}
    }
    foreach($row in @($mapped|Sort-Object rank,@{Expression={$_.item.title}})){$row.item}
}
if($Action -eq 'Export'){
    $catalog=@(Read-Json $CatalogPath)
    if(!$catalog.Count){throw 'Empty catalog; refusing to overwrite saved layout'}
    $seen=@{};$order=0
    $entries=foreach($item in $catalog){
        $key=Title-Key $item.title
        if(!$key -or $seen.ContainsKey($key)){throw 'Catalog contains empty or duplicate titles'}
        $seen[$key]=$true
        [ordered]@{title=[string]$item.title;group=[string]$item.group;order=$order++}
    }
    $layout=[ordered]@{version=1;defaultGroup='';entries=@($entries)}
    $old=if(Test-Path -LiteralPath $LayoutPath){[IO.File]::ReadAllBytes($LayoutPath)}else{[byte[]]@()}
    if($PSCmdlet.ShouldProcess($LayoutPath,'Save portable folder layout')){Write-Atomic $LayoutPath ($layout|ConvertTo-Json -Depth 8) $old}
    return
}
$layout=Read-Json $LayoutPath
if($Action -eq 'Transform'){
    if($null -eq $Apps){throw 'Transform requires Apps'}
    Map-Apps $Apps $layout
    return
}
$original=[IO.File]::ReadAllBytes($CatalogPath)
$catalog=@(Read-Json $CatalogPath)
$mapped=@(Map-Apps $catalog $layout)
if($mapped.Count -ne $catalog.Count){throw 'Entry count mismatch; left untouched'}
$json=ConvertTo-Json -InputObject $mapped -Depth 20
if($PSCmdlet.ShouldProcess($CatalogPath,'Restore application groups and order')){Write-Atomic $CatalogPath $json $original}
