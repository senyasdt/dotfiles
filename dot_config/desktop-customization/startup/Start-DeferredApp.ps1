param([Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9-]+$')][string]$Id)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$runtime=Join-Path $root 'runtime'
$config=Get-Content -LiteralPath (Join-Path $runtime 'deferred-apps.json') -Raw|ConvertFrom-Json
$app=@($config|Where-Object id -eq $Id)
if($app.Count -ne 1){throw 'Unknown or duplicate deferred app ID'}
$app=$app[0]
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
$mutex=New-Object Threading.Mutex($false,('Local\Druzh.DeferredApp.'+$Id+'.'+$session))
$locked=$false
try{
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(-not $locked){return}
    $running=@(Get-CimInstance Win32_Process -Filter ("Name='"+$app.processName+"'")|Where-Object SessionId -eq $session)
    if($app.packageFamily){
        $owned=@($running|Where-Object {$_.ExecutablePath -match ('\\WindowsApps\\'+[regex]::Escape(($app.packageFamily -split '_')[0])+'_')})
    }else{$owned=@($running|Where-Object ExecutablePath -IEQ $app.FilePath)}
    if($owned.Count){Add-Content -LiteralPath (Join-Path $runtime 'deferred-startup.log') -Value ((Get-Date -Format o)+' Reused running '+$Id);return}
    if(-not (Test-Path -LiteralPath $app.FilePath)){throw ('Deferred application not installed: '+$Id)}
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$app.FilePath;$info.Arguments=$app.Arguments;$info.WorkingDirectory=$app.WorkingDirectory
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.EnvironmentVariables['USERPROFILE']=[Environment]::GetFolderPath('UserProfile')
    $info.EnvironmentVariables['APPDATA']=[Environment]::GetFolderPath('ApplicationData')
    $info.EnvironmentVariables['LOCALAPPDATA']=[Environment]::GetFolderPath('LocalApplicationData')
    $process=[Diagnostics.Process]::Start($info);$process.Dispose()
    Add-Content -LiteralPath (Join-Path $runtime 'deferred-startup.log') -Value ((Get-Date -Format o)+' Started '+$Id)
}catch{Add-Content -LiteralPath (Join-Path $runtime 'deferred-startup.log') -Value ((Get-Date -Format o)+' '+$Id+': '+$_.Exception.Message);throw}
finally{if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
