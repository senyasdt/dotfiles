[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [ValidateSet('Status','Scrolling','Bsp')][string]$Mode='Status',
    [ValidateRange(1,5)][int]$Columns=2
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
function Read-State {
    return ((Invoke-Client -Arguments @('state')) -join "`n" | ConvertFrom-Json)
}
function Show-Status($State) {
    $monitor=$State.monitors.elements[$State.monitors.focused]
    $workspace=$monitor.workspaces.elements[$monitor.workspaces.focused]
    [pscustomobject]@{
        Monitors=@($State.monitors.elements).Count
        Monitor=[int]$State.monitors.focused+1
        Workspace=[int]$monitor.workspaces.focused+1
        Layout=($workspace.layout | ConvertTo-Json -Compress -Depth 8)
        SavedConfig='Unchanged; runtime layout only'
    }
}
$state=Read-State
if(-not @($state.monitors.elements).Count){throw 'No komorebi monitors found.'}
if($Mode -eq 'Status'){Show-Status $state; return}
if($Mode -eq 'Scrolling' -and @($state.monitors.elements).Count -ne 1){
    throw 'Scrolling is supported on a single monitor only. Nothing was changed. BSP remains available.'
}
$monitorIndex=[int]$state.monitors.focused
$workspaceIndex=[int]$state.monitors.elements[$monitorIndex].workspaces.focused
$target=$Mode.ToLowerInvariant()
$description="Set $target layout"; if($Mode -eq 'Scrolling'){$description+=" with $Columns visible columns"}
if($PSCmdlet.ShouldProcess("monitor $($monitorIndex+1), workspace $($workspaceIndex+1)",$description)) {
    # Explicit indices keep the layout change tied to the workspace selected above.
    Invoke-Client -Arguments @('workspace-layout',"$monitorIndex","$workspaceIndex",$target) | Out-Null
    if($Mode -eq 'Scrolling') {
        try {
            $current=Read-State
            if($current.monitors.focused -ne $monitorIndex -or $current.monitors.elements[$monitorIndex].workspaces.focused -ne $workspaceIndex){
                throw 'Focus changed during switching. Retry without changing workspace.'
            }
            Invoke-Client -Arguments @('scrolling-layout-columns',"$Columns") | Out-Null
        } catch {
            Invoke-Client -Arguments @('workspace-layout',"$monitorIndex","$workspaceIndex",'bsp') | Out-Null
            throw
        }
    }
    $after=Read-State
    $layout=$after.monitors.elements[$monitorIndex].workspaces.elements[$workspaceIndex].layout.Default
    if([string]$layout -ine $target){throw 'komorebi did not report the requested layout. Check Status and use BSP.cmd to return.'}
    Show-Status $after
}
