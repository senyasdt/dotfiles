[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [ValidateSet('Status','Scrolling','Bsp')][string]$Mode='Status',
    [ValidateRange(1,5)][int]$Columns=2,
    [ValidateRange(0,400)][int]$Peek=0
)
$ErrorActionPreference='Stop'
$command=Get-Command komorebic.exe -ErrorAction SilentlyContinue
$client=if($command){$command.Source}else{Join-Path ([Environment]::GetFolderPath('UserProfile')) 'scoop\apps\komorebi\current\komorebic.exe'}
if(-not(Test-Path -LiteralPath $client)){throw 'komorebic.exe was not found. Start the existing desktop session first.'}
function Invoke-Client([string[]]$Arguments) {
    $result=& $client @Arguments 2>&1
    if($LASTEXITCODE -ne 0){throw ('komorebic failed: '+($Arguments -join ' ')+'. No process restart or config replacement was attempted.')}
    return $result
}
function Read-State { return ((Invoke-Client -Arguments @('state')) -join "`n" | ConvertFrom-Json) }
function Show-Status($State) {
    $monitor=$State.monitors.elements[$State.monitors.focused]
    $workspace=$monitor.workspaces.elements[$monitor.workspaces.focused]
    [pscustomobject]@{
        Monitors=@($State.monitors.elements).Count
        Monitor=[int]$State.monitors.focused+1
        Workspace=[int]$monitor.workspaces.focused+1
        Layout=($workspace.layout | ConvertTo-Json -Compress -Depth 8)
        LayoutOptions=($workspace.layout_options | ConvertTo-Json -Compress -Depth 8)
        WorkAreaOffset=($workspace.work_area_offset | ConvertTo-Json -Compress)
        SavedConfig='Unchanged; runtime layout only'
    }
}
function Offset-OrZero($Offset) {
    if($null -eq $Offset){return [pscustomobject]@{left=0;top=0;right=0;bottom=0}}
    return [pscustomobject]@{left=[int]$Offset.left;top=[int]$Offset.top;right=[int]$Offset.right;bottom=[int]$Offset.bottom}
}
function Set-Offset($Offset) {
    $v=Offset-OrZero $Offset
    Invoke-Client -Arguments @('workspace-work-area-offset',"$monitorIndex","$workspaceIndex","$($v.left)","$($v.top)","$($v.right)","$($v.bottom)") | Out-Null
}
function Save-History {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $historyPath)) | Out-Null
    $temp=$historyPath+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($temp,($history | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
    if(Test-Path -LiteralPath $historyPath){[IO.File]::Replace($temp,$historyPath,[NullString]::Value)}else{[IO.File]::Move($temp,$historyPath)}
}
$state=Read-State
if(-not @($state.monitors.elements).Count){throw 'No komorebi monitors found.'}
if($Mode -eq 'Status'){Show-Status $state; return}
if($Mode -eq 'Scrolling' -and @($state.monitors.elements).Count -ne 1){throw 'Scrolling is supported on a single monitor only. Nothing was changed. BSP remains available.'}
$monitorIndex=[int]$state.monitors.focused
$monitor=$state.monitors.elements[$monitorIndex]
$workspaceIndex=[int]$monitor.workspaces.focused
$workspace=$monitor.workspaces.elements[$workspaceIndex]
$target=$Mode.ToLowerInvariant()
$description="Set $target layout";if($Mode -eq 'Scrolling'){$description+=" with $Columns visible columns and $Peek px side previews"}
if(-not $PSCmdlet.ShouldProcess("monitor $($monitorIndex+1), workspace $($workspaceIndex+1)",$description)){return}
# Runtime only; never store machine-specific journal in the managed source.
$historyPath=Join-Path $PSScriptRoot 'runtime\layout-offsets.json'
$history=@{}
if(Test-Path -LiteralPath $historyPath){$loaded=Get-Content -LiteralPath $historyPath -Raw|ConvertFrom-Json;foreach($p in $loaded.PSObject.Properties){$history[$p.Name]=$p.Value}}
$identity=if($monitor.device_id){[string]$monitor.device_id}elseif($monitor.name){[string]$monitor.name}else{"monitor-$monitorIndex"}
$key=$identity+'|'+$workspaceIndex
$original=$workspace.work_area_offset
if($null -eq $original){$original=$monitor.work_area_offset}
if($null -eq $original){$original=$state.work_area_offset}
$original=Offset-OrZero $original
if($Mode -eq 'Scrolling' -and $Peek -gt 0 -and -not $history.ContainsKey($key)){
    $history[$key]=[pscustomobject]@{offset=$original}
    Save-History
}
try {
    # Explicit indices keep offset/layout changes on the initially selected workspace.
    if($Mode -eq 'Scrolling' -and $Peek -gt 0){
        $peekOffset=[pscustomobject]@{left=$original.left+$Peek;top=$original.top;right=$original.right+2*$Peek;bottom=$original.bottom}
        # Repeated application starts from the saved baseline, not the preview offset.
        $base=Offset-OrZero $history[$key].offset
        $peekOffset.left=$base.left+$Peek;$peekOffset.right=$base.right+2*$Peek
        $peekOffset.top=$base.top;$peekOffset.bottom=$base.bottom
        Set-Offset $peekOffset
    }elseif($history.ContainsKey($key)){Set-Offset $history[$key].offset}
    Invoke-Client -Arguments @('workspace-layout',"$monitorIndex","$workspaceIndex",$target) | Out-Null
    if($Mode -eq 'Scrolling'){
        $current=Read-State
        if($current.monitors.focused -ne $monitorIndex -or $current.monitors.elements[$monitorIndex].workspaces.focused -ne $workspaceIndex){throw 'Focus changed during switching. Retry without changing workspace.'}
        Invoke-Client -Arguments @('scrolling-layout-columns',"$Columns") | Out-Null
    }
    $after=Read-State
    if([string]$after.monitors.elements[$monitorIndex].workspaces.elements[$workspaceIndex].layout.Default -ine $target){throw 'komorebi did not report the requested layout.'}
    if(($Mode -eq 'Bsp' -or $Peek -eq 0) -and $history.ContainsKey($key)){$history.Remove($key);Save-History}
    Show-Status $after
}catch{
    # A failed preview returns its target to BSP and its saved effective offsets.
    if($history.ContainsKey($key)){Set-Offset $history[$key].offset}
    Invoke-Client -Arguments @('workspace-layout',"$monitorIndex","$workspaceIndex",'bsp') | Out-Null
    if($history.ContainsKey($key)){$history.Remove($key);Save-History}
    throw
}
