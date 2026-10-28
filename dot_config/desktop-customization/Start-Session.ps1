$ErrorActionPreference='Stop'
# Use the user's real profile, independent of an inherited bootstrap environment.
$env:USERPROFILE=[Environment]::GetFolderPath('UserProfile')
$env:APPDATA=[Environment]::GetFolderPath('ApplicationData')
$env:LOCALAPPDATA=[Environment]::GetFolderPath('LocalApplicationData')
$runtime=Join-Path $PSScriptRoot 'runtime'
[IO.Directory]::CreateDirectory($runtime)|Out-Null
$log=Join-Path $runtime 'session-startup.log'
function Log($message){Add-Content -LiteralPath $log -Value ((Get-Date -Format o)+' '+$message)}
$mutex=New-Object Threading.Mutex($false,('Local\Druzh.DesktopSession.'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$locked=$false
try{
try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
if(-not $locked){return}
if((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 65536){Move-Item -LiteralPath $log -Destination ($log+'.1') -Force}
Log 'Starting desktop session.'
$settings=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'desktop.json') -Raw|ConvertFrom-Json
if($settings.bar -notin @('none','yasb')){throw 'Unknown bar in desktop.json'}
$errors=@()
function Start-Component($name,[scriptblock]$action){
    for($attempt=1;$attempt -le 3;$attempt++){
        try{& $action|Out-Null;Log ($name+' ready.');return}
        catch{
            Log ($name+' attempt '+$attempt+': '+$_.Exception.Message)
            if($attempt -eq 3){throw}
            Start-Sleep -Seconds 2
        }
    }
}
$theme=[Environment]::GetEnvironmentVariable('WINDOWS_DESKTOP_THEME','User')
if(-not $theme){$theme=$settings.theme}
$themeRoot=Join-Path $PSScriptRoot 'yasb-catppuccin'
$themeState=Join-Path $themeRoot 'runtime\profile.json'
$catppuccin=$false
if($theme -eq 'catppuccin' -and (Test-Path -LiteralPath $themeState)){
    try{$catppuccin=(Get-Content -LiteralPath $themeState -Raw|ConvertFrom-Json).mode -eq 'catppuccin'}catch{$errors+=$_.Exception.Message}
}
# Each component is idempotent; one failed dependency must not stop AHK protection.
if($settings.startAhk){try {Start-Component 'AHK guard' {& (Join-Path $PSScriptRoot 'script-launcher\Manage.ps1') -Action Start}}catch{$errors+=$_.Exception.Message}}
if($settings.startWindowManager -or $settings.startKomorebi){try {Start-Component 'Window manager' {& (Join-Path $PSScriptRoot 'komorebi-support\Start-DesktopWM.ps1')}}catch{$errors+=$_.Exception.Message}}
if($catppuccin){
    try{Start-Component 'YASB and dock' {& (Join-Path $themeRoot 'Manage.ps1') -Action Start}}catch{$errors+=$_.Exception.Message}
}elseif($settings.bar -eq 'yasb'){
    try{Start-Component 'YASB' {& (Join-Path $themeRoot 'Start-Yasb.ps1')}}catch{$errors+=$_.Exception.Message}
}
if($errors.Count){$errors|Add-Content -LiteralPath (Join-Path $PSScriptRoot 'session-errors.log');throw ($errors -join [Environment]::NewLine)}
Log 'Desktop session ready.'
}catch{Log ('Session failed: '+$_.Exception.Message);throw}
finally{if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
