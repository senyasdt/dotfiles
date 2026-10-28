param([Parameter(Mandatory=$true)][string]$Text,
    [Parameter(Mandatory=$true)][string]$BridgeRoot)
# Pure transformation shared by first activation and later theme refreshes.
$pattern='(?m)^      - workspaces\r?\n      - layout\r?$'
$matchCount=[regex]::Matches($Text,$pattern).Count
$selected=[regex]::Matches($Text,'(?m)^      - leopard_status\r?$').Count
if($selected -eq 1 -and $matchCount -eq 0){
    if([regex]::Matches($Text,'(?m)^  leopard_status:\r?$').Count -ne 1){throw 'Missing or duplicate LeopardWM widget definition.'}
    return $Text
}
if($matchCount -ne 1 -or $selected -ne 0 -or $Text -match '(?m)^  leopard_status:'){throw 'Unrecognized YASB workspace block; config left unchanged.'}
$short=(New-Object -ComObject Scripting.FileSystemObject).GetFolder($BridgeRoot).ShortPath
if($short.Contains(' ')){throw 'YASB requires a helper path without spaces.'}
$snippet=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'yasb-widget.yaml'))
return [regex]::Replace($Text,$pattern,'      - leopard_status')+"`n"+$snippet.Replace('__BRIDGE__',$BridgeRoot).Replace('__BRIDGE_CMD__',$short)
