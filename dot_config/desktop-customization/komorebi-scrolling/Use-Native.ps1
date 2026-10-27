[CmdletBinding(SupportsShouldProcess=$true)]
param([ValidateSet('Independent','Stable')][string]$Mode='Independent')
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$runtime=Join-Path $root 'runtime'
$flag=Join-Path $runtime 'native-profile.json'
$support=Join-Path (Split-Path -Parent $root) 'komorebi-support\Start-DesktopWM.ps1'
$stock=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'scoop\apps\komorebi\current\komorebic.exe'
$client=$stock
$native=Join-Path $runtime 'native'
if($Mode -eq 'Independent'){
    $info=Get-Content -LiteralPath (Join-Path $native 'build-info.json') -Raw|ConvertFrom-Json
    foreach($file in @('komorebi.exe','komorebic.exe')){
        if((Get-FileHash -LiteralPath (Join-Path $native $file) -Algorithm SHA256).Hash -ine $info.hashes.$file){throw "Native build hash mismatch: $file"}
    }
    $client=Join-Path $native 'komorebic.exe'
}
function Invoke-Client([string[]]$Arguments){
    $p=New-Object Diagnostics.Process
    $p.StartInfo=New-Object Diagnostics.ProcessStartInfo($client,($Arguments -join ' '))
    $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
    $p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
    $p.StartInfo.StandardOutputEncoding=[Text.Encoding]::UTF8
    try{
        [void]$p.Start();$output=$p.StandardOutput.ReadToEndAsync();$errorOutput=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit(4000)){try{$p.Kill()}catch{};throw 'komorebi request timed out; only the short-lived client was stopped.'}
        if($p.ExitCode -ne 0){throw ('komorebi request failed: '+($Arguments -join ' '))}
        return $output.Result
    }finally{$p.Dispose()}
}
try{$state=(Invoke-Client @('state')) -join "`n"|ConvertFrom-Json}catch{if($Mode -eq 'Independent'){throw};$state=$null}
if($state -and @($state.monitors.elements).Count -ne 1 -and $Mode -eq 'Independent'){throw 'This trial is limited to one monitor.'}
if($state.is_paused -and $Mode -eq 'Independent'){throw 'Resume komorebi before switching builds.'}
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
$allowed=@((Join-Path (Split-Path $stock) 'komorebi.exe'),(Join-Path $native 'komorebi.exe'))
$owners=@(Get-Process komorebi -ErrorAction SilentlyContinue|Where-Object SessionId -eq $session)
if($owners.Count -gt 1 -or ($owners.Count -eq 1 -and $owners[0].Path -notin $allowed) -or ($Mode -eq 'Independent' -and $owners.Count -ne 1)){throw 'Unexpected komorebi owner; nothing changed.'}
if(-not $PSCmdlet.ShouldProcess('komorebi only; keep windows/workspaces using native session restore',"Switch to $Mode build")){return}
[IO.Directory]::CreateDirectory($runtime)|Out-Null
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
[IO.File]::WriteAllText((Join-Path $runtime ("before-native-$stamp.json")),($state|ConvertTo-Json -Depth 60),(New-Object Text.UTF8Encoding($false)))
$prior=if(Test-Path -LiteralPath $flag){[IO.File]::ReadAllText($flag)}else{$null}
function Set-Flag($Text){
    if($null -eq $Text){if(Test-Path -LiteralPath $flag){Remove-Item -LiteralPath $flag}}
    else{[IO.File]::WriteAllText($flag,$Text,(New-Object Text.UTF8Encoding($false)))}
}
try{
    if($Mode -eq 'Independent'){
        $base=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'komorebi.json'
        $config=Get-Content -LiteralPath $base -Raw|ConvertFrom-Json
        $workspace=$config.monitors[0].workspaces[0]
        $workspace.layout='Scrolling'
        $workspace|Add-Member -NotePropertyName layout_options -NotePropertyValue ([pscustomobject]@{scrolling=[pscustomobject]@{columns=2;fixed_column_width=$true;center_focused_column=$false; width_steps=@(0.382,0.5,0.618)}}) -Force
        $workspace|Add-Member -NotePropertyName work_area_offset -NotePropertyValue ([pscustomobject]@{left=180;top=0;right=360;bottom=0}) -Force
        $config|Add-Member -NotePropertyName animation -NotePropertyValue ([pscustomobject]@{enabled=@{movement=$true};duration=@{movement=90};style=@{movement='EaseOutSine'};fps=60}) -Force
        [IO.File]::WriteAllText((Join-Path $runtime 'native-config.json'),($config|ConvertTo-Json -Depth 40),(New-Object Text.UTF8Encoding($false)))
        Set-Flag '{"enabled":true}'
    }else{Set-Flag $null}
    & $support -Restart -PreserveState
    $after=(Invoke-Client @('state')) -join "`n"|ConvertFrom-Json
    if($Mode -eq 'Independent'){
        if(-not $after.monitors.elements[0].workspaces.elements[0].layout_options.scrolling.fixed_column_width){throw 'Independent widths were not activated.'}
    }
    Write-Output "Active build: $Mode. Base komorebi.json unchanged; windows stay open."
}catch{
    $failure=$_
    if($Mode -eq 'Stable'){throw $failure} # Never re-enable a broken trial during emergency return.
    Set-Flag $prior
    try{& $support -Restart -PreserveState|Out-Null}catch{Write-Warning 'Automatic build rollback failed. Use the saved standard desktop launcher.'}
    throw $failure
}
