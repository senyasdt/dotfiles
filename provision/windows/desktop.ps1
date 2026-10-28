param(
    [string]$Root=(Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config\desktop-customization'),
    [ValidateSet('Build','Install','Status')][string]$Action='Status',
    [switch]$IncludeLayoutGuard
)
$ErrorActionPreference='Stop'
$profileRoot=[Environment]::GetFolderPath('UserProfile')
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
$rootPath=[IO.Path]::GetFullPath($Root)
$required=@('script-launcher\ScriptLauncher.cs','script-launcher\config.json','script-launcher\Manage.ps1','komorebi-support\Start-DesktopWM.ps1','Start-Session.ps1')
foreach($relative in $required){if(-not(Test-Path -LiteralPath (Join-Path $rootPath $relative))){throw ('Missing deployed desktop file: '+$relative+'. Apply the Windows desktop chezmoi targets first.')}}
$settings=Get-Content -LiteralPath (Join-Path $rootPath 'desktop.json') -Raw|ConvertFrom-Json
if($settings.bar -notin @('none','yasb')){throw 'desktop.json bar must be none or yasb'}
if($Action -eq 'Status'){
    [pscustomobject]@{Root=$rootPath;Bar=$settings.bar;StartupReady=(Test-Path -LiteralPath (Join-Path $rootPath 'script-launcher\ScriptLauncher.exe'));VialInstalled=(Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Programs\vial-helper\run-hidden.ps1'));ZmkInstalled=(Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Programs\zmk-yasb\zmk-helperd.exe'));LayoutGuard='Optional; requires approved custom layouts installed separately'}|ConvertTo-Json
    return
}
# Do not take ownership from a helper running in another checkout.
foreach($name in @('ScriptLauncher','FinderWidgets')){
    $foreign=@(Get-Process -Name $name -ErrorAction SilentlyContinue|Where-Object {$_.SessionId -eq $session -and -not $_.Path.StartsWith($rootPath+'\',[StringComparison]::OrdinalIgnoreCase)})
    if($foreign.Count){throw ($name+' is running from another folder. Stop that copy explicitly before migrating; current processes were left intact.')}
}
foreach($folder in @('script-launcher')){& (Join-Path $rootPath ($folder+'\Manage.ps1')) -Action Build}
if($IncludeLayoutGuard){
    $guard=Join-Path $rootPath 'keyboard-layout-guard'
    & (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /target:winexe /platform:x64 /optimize+ ('/out:'+(Join-Path $guard 'TechnicalAltGrLayoutGuard.exe')) (Join-Path $guard 'LayoutGuard.cs')
    if($LASTEXITCODE -ne 0){throw 'Layout guard build failed'}
}
if($Action -eq 'Build'){return}
$startup=[Environment]::GetFolderPath('Startup')
# Previous installations are reviewable, not silently duplicated or deleted.
$conflicts=@('AHK Program Guard.lnk','AHK Script Launcher.lnk','YASB Catppuccin.lnk','MyDockFinder.lnk','MyDockFinder Hotkeys.lnk','Finder Widgets.lnk','autohotkey.cmd','komorebi.cmd','zmk-text-replacements.ahk','yasb.cmd')|Where-Object {Test-Path -LiteralPath (Join-Path $startup $_)}
if($conflicts){throw ('Review/remove backed-up legacy Startup entries first: '+($conflicts -join ', '))}
$linkPath=Join-Path $startup 'Desktop Session.lnk'
$shell=New-Object -ComObject WScript.Shell
$link=$shell.CreateShortcut($linkPath)
$powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$argument='-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $rootPath 'Start-Session.ps1')+'"'
if((Test-Path -LiteralPath $linkPath) -and ($link.TargetPath -ine $powershell -or $link.Arguments -cne $argument)){throw 'Existing Desktop Session shortcut belongs to a different installation'}
$link.TargetPath=$powershell;$link.Arguments=$argument;$link.WorkingDirectory=$rootPath;$link.WindowStyle=7;$link.Save()
$appLinkPath=Join-Path ([Environment]::GetFolderPath('Programs')) 'All Applications.lnk'
$apps=$shell.CreateShortcut($appLinkPath)
$explorer=Join-Path $env:WINDIR 'explorer.exe'
if((Test-Path -LiteralPath $appLinkPath) -and ($apps.TargetPath -ine $explorer -or $apps.Arguments -ne 'shell:AppsFolder')){throw 'Existing All Applications shortcut belongs to another application'}
$apps.TargetPath=$explorer;$apps.Arguments='shell:AppsFolder';$apps.Description='Installed applications, independent of AHK and desktop panels';$apps.Save()
Write-Host 'Desktop startup installed. Sign in again or run Start-Session.ps1 explicitly.'
