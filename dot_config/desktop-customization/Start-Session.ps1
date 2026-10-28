$ErrorActionPreference='Stop'
$settings=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'desktop.json') -Raw|ConvertFrom-Json
if($settings.bar -notin @('none','yasb')){throw 'Unknown bar in desktop.json'}
$errors=@()
$theme=[Environment]::GetEnvironmentVariable('WINDOWS_DESKTOP_THEME','User')
if(-not $theme){$theme=$settings.theme}
$themeRoot=Join-Path $PSScriptRoot 'yasb-catppuccin'
$themeState=Join-Path $themeRoot 'runtime\profile.json'
$catppuccin=$false
if($theme -eq 'catppuccin' -and (Test-Path -LiteralPath $themeState)){
    try{$catppuccin=(Get-Content -LiteralPath $themeState -Raw|ConvertFrom-Json).mode -eq 'catppuccin'}catch{$errors+=$_.Exception.Message}
}
# Each component is idempotent; one failed dependency must not stop AHK protection.
if($settings.startAhk){try {& (Join-Path $PSScriptRoot 'script-launcher\Manage.ps1') -Action Start}catch{$errors+=$_.Exception.Message}}
if($settings.startWindowManager -or $settings.startKomorebi){try {& (Join-Path $PSScriptRoot 'komorebi-support\Start-DesktopWM.ps1')}catch{$errors+=$_.Exception.Message}}
if($catppuccin){
    try{& (Join-Path $themeRoot 'Manage.ps1') -Action Start}catch{$errors+=$_.Exception.Message}
}elseif($settings.bar -eq 'yasb'){
    try{& (Join-Path $themeRoot 'Start-Yasb.ps1')}catch{$errors+=$_.Exception.Message}
}
if($errors.Count){$errors|Add-Content -LiteralPath (Join-Path $PSScriptRoot 'session-errors.log');throw ($errors -join [Environment]::NewLine)}
