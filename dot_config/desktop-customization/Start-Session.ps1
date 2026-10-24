$ErrorActionPreference='Stop'
$settings=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'desktop.json') -Raw|ConvertFrom-Json
if($settings.bar -notin @('none','yasb','mydockfinder')){throw 'Unknown bar in desktop.json'}
$errors=@()
# Each component is idempotent; one failed dependency must not stop AHK protection.
if($settings.startAhk){try {& (Join-Path $PSScriptRoot 'script-launcher\Manage.ps1') -Action Start}catch{$errors+=$_.Exception.Message}}
if($settings.startKomorebi){try {& (Join-Path $PSScriptRoot 'komorebi-support\Start-DesktopWM.ps1')}catch{$errors+=$_.Exception.Message}}
if($settings.startWidgets){try {& (Join-Path $PSScriptRoot 'finder-widgets\Manage.ps1') -Action Start}catch{$errors+=$_.Exception.Message}}
# Only YASB is started here. MyDockFinder uses its own optional Steam/startup setup.
if($settings.bar -eq 'yasb'){
    $yasb=Join-Path $env:ProgramFiles 'YASB\yasb.exe'
    if(-not(Get-Process yasb -ErrorAction SilentlyContinue)){
        if(Test-Path -LiteralPath $yasb){Start-Process -FilePath $yasb -WindowStyle Hidden}else{$errors+='YASB is selected but not installed.'}
    }
}
if($errors.Count){$errors|Add-Content -LiteralPath (Join-Path $PSScriptRoot 'session-errors.log');throw ($errors -join [Environment]::NewLine)}
