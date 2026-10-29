$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Sync-Apps.ps1') -FunctionsOnly
$checks=0
function Check($condition,$message){if(!$condition){throw $message};$script:checks++}
function Existing($id,$title,$path='C:\old.lnk',$group='Custom'){
    [pscustomobject]@{id=$id;title=$title;path=$path;icon='keep.png';group=$group;custom='keep extra fields'}
}
function Candidate($title,$path,$key='target|new',$group=''){
    [pscustomobject]@{title=$title;path=$path;keys=@($key);group=$group;valid=$true}
}
$one=Existing 12 'Existing';$two=Existing 2 'Second'
$before=ConvertTo-Json -InputObject @($one,$two) -Depth 8 -Compress
$c=Candidate 'New' 'C:\new.exe'
$r=Merge-Apps @($one,$two) @($c) @{'12'=@('target|existing');'2'=@('target|second')} @()
Check ($r.apps.Count -eq 3 -and $r.added.Count -eq 1) 'New app not added'
Check ($r.apps[0].id -eq 12 -and $r.apps[1].id -eq 2 -and $r.apps[2].id -eq 13) 'IDs or order changed'
Check ((ConvertTo-Json -InputObject @($r.apps[0],$r.apps[1]) -Depth 8 -Compress) -ceq $before) 'Existing properties changed'
$r=Merge-Apps @($one) @((Candidate 'Alias' 'C:\same.exe' 'target|existing')) @{'12'=@('target|existing')} @()
Check ($r.apps.Count -eq 1) 'Alias duplicated same executable'
$r=Merge-Apps @($one) @((Candidate ' EXISTING ' 'C:\new.exe')) @{'12'=@('target|existing')} @()
Check ($r.apps.Count -eq 1 -and $r.repaired.Count -eq 0) 'Live custom launcher replaced'
$r=Merge-Apps @($one) @((Candidate 'Existing' 'C:\new.exe')) @{'12'=@('target|old');'invalid|12'=$true} @()
Check ($r.repaired.Count -eq 1 -and $r.apps[0].path -eq 'C:\new.exe') 'Missing launcher not repaired'
Check ($r.apps[0].group -eq 'Custom' -and $r.apps[0].icon -eq 'keep.png' -and $r.apps[0].custom -eq 'keep extra fields') 'Repair lost customization'
$r=Merge-Apps @($one) @((Candidate 'Existing' 'C:\first.exe'),(Candidate 'Existing' 'C:\second.exe')) @{'12'=@('target|old');'invalid|12'=$true} @()
Check ($r.repaired.Count -eq 1 -and $r.apps[0].path -eq 'C:\first.exe') 'Later alias overwrote first successful repair'
$r=Merge-Apps @() @($c) @{} @('New')
Check ($r.apps.Count -eq 0 -and $r.ignored.Count -eq 1) 'Manual deletion reappeared'
$r=Merge-Apps @($one) @($c,$c) @{'12'=@('target|existing')} @()
Check ($r.apps.Count -eq 2) 'Discovery duplicate added twice'
$r=Merge-Apps @($one) @() @{'12'=@('target|existing')} @()
Check ($r.apps.Count -eq 1 -and $r.repaired.Count -eq 0) 'Unavailable source deleted existing app'
$r=Merge-Apps @() @($c) @{} @()
Check ($r.apps.Count -eq 1 -and $r.apps[0].id -eq 1) 'Empty catalog failed'
$dup=$false;try{Merge-Apps @($one,$one) @() @{} @()|Out-Null}catch{$dup=$true}
Check $dup 'Duplicate IDs accepted'
$nullKey=Candidate 'Packaged' 'explorer.exe shell:AppsFolder\Vendor_App!App';$nullKey.keys+=@($null)
$r=Merge-Apps @() @($nullKey) @{} @()
Check ($r.added.Count -eq 1) 'Optional null identity key rejected'
Check ((Target-Key 'C:\Apps/bin/App.exe') -eq (Target-Key 'c:\apps\bin\app.exe')) 'Path slash aliases differ'
$r=Merge-Apps @() @((Candidate 'Renamed App' 'C:\renamed.lnk' 'target|original')) @{} @('Original App') @('target|original')
Check ($r.apps.Count -eq 0 -and $r.ignored.Count -eq 1) 'Removed app returned under new display name'
$r=Merge-Apps @() @((Candidate 'Different App' 'C:\different.lnk' 'target|different')) @{} @('Original App') @('target|original')
Check ($r.apps.Count -eq 1) 'Unrelated new app suppressed'
"PASS: $checks catalog merge checks"
