param([switch]$DownloadRelease,[string]$ReleaseArchive)
$ErrorActionPreference='Stop'
$source=Split-Path (Split-Path $PSScriptRoot)
$desktop=Join-Path $source 'dot_config\desktop-customization'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('window-manager-check-'+[Guid]::NewGuid().ToString('N'))
$root=Join-Path $testRoot 'routing'
$leopard=Join-Path $root 'leopardwm-test'
$support=Join-Path $root 'komorebi-support'
$bridge=Join-Path $root 'yasb-catppuccin'
foreach($dir in @((Join-Path $leopard 'runtime'),$support,$bridge)){[void][IO.Directory]::CreateDirectory($dir)}
function Assert($ok,$message){if(-not $ok){throw $message}}
function Write-Json($path,$value){[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))}
foreach($name in @('Get-WindowManager.ps1','Convert-YasbConfig.ps1','yasb-widget.yaml')){Copy-Item (Join-Path $desktop ('leopardwm-test\'+$name)) $leopard}
Copy-Item (Join-Path $desktop 'komorebi-support\Start-DesktopWM.ps1') $support
[IO.File]::WriteAllText((Join-Path $leopard 'Use-WindowManager.ps1'),'param($Mode,$Operation,[switch]$Confirm); "$Mode/$Operation"')
Write-Json (Join-Path $root 'desktop.json') @{windowManager='Leopard'}
$selection=Join-Path $leopard 'runtime\selection.json'
function Selected {& (Join-Path $leopard 'Get-WindowManager.ps1')}
Assert ((Selected) -eq 'Komorebi') 'Uninstalled portable manager must not start'
Write-Json (Join-Path $leopard 'runtime\release.json') @{}
Assert ((Selected) -eq 'Leopard') 'Managed primary default lost'
Assert ((& (Join-Path $support 'Start-DesktopWM.ps1')) -eq 'Leopard/Switch') 'First login must initialize selection'
Write-Json $selection @{enabled=$true}
Assert ((& (Join-Path $support 'Start-DesktopWM.ps1')) -eq 'Leopard/Start') 'Wrong start dispatch'
Assert ((& (Join-Path $support 'Start-DesktopWM.ps1') -Restart) -eq 'Leopard/Restart') 'Wrong restart dispatch'
Assert ((& (Join-Path $support 'Start-DesktopWM.ps1') -Stop) -eq 'Leopard/Stop') 'Wrong stop dispatch'
Write-Json $selection @{enabled=$false}
Assert ((Selected) -eq 'Komorebi') 'Explicit fallback must override branch default'
Write-Json $selection @{enabled='false'}
$rejected=$false;try{Selected|Out-Null}catch{$rejected=$true};Assert $rejected 'Malformed selection must fail closed'
$convert=Join-Path $leopard 'Convert-YasbConfig.ps1'
$text=[IO.File]::ReadAllText((Join-Path $desktop 'yasb-catppuccin\config.yaml'))
$converted=& $convert -Text $text -BridgeRoot $bridge
Assert ($converted -match '(?m)^      - leopard_status\r?$') 'Leopard widget not selected'
Assert ((& $convert -Text $converted -BridgeRoot $bridge) -ceq $converted) 'Panel conversion must be idempotent'
$rejected=$false;try{& $convert -Text ($text.Replace('      - workspaces','      - unknown')) -BridgeRoot $bridge|Out-Null}catch{$rejected=$true}
Assert $rejected 'Unrecognized panel must be rejected before writes'
$hotkeyCheck=Join-Path $desktop 'leopardwm-test\Test-EffectiveHotkeys.ps1'
$managedConfig=[IO.File]::ReadAllText((Join-Path $desktop 'leopardwm-test\config.toml'))
$bindings=@([regex]::Matches($managedConfig,'(?m)^"([^"]+)"\s*=')|ForEach-Object {$_.Groups[1].Value})
$effective="Hotkeys:`n  Scroll modifier: Alt`n"+(($bindings|ForEach-Object {'  [Binding] Action: '+$_}) -join "`n")
Assert (& $hotkeyCheck -ConfigText $managedConfig -HotkeyText $effective) 'Managed hotkeys were rejected'
Assert (-not (& $hotkeyCheck -ConfigText $managedConfig -HotkeyText $effective.Replace('modifier: Alt','modifier: Ctrl+Alt'))) 'Silent fallback to default scroll modifier must be detected'
Assert (-not (& $hotkeyCheck -ConfigText $managedConfig -HotkeyText $effective.Replace('Action: Alt+2','Action: Ctrl+Alt+2'))) 'Missing workspace binding must be detected'
Assert (-not (& $hotkeyCheck -ConfigText $managedConfig -HotkeyText '')) 'Empty IPC response must not pass'
if($DownloadRelease -or $ReleaseArchive){
    $portable=Join-Path $testRoot 'portable'
    $portableLeopard=Join-Path $portable 'leopardwm-test'
    $portableBridge=Join-Path $portable 'yasb-catppuccin'
    foreach($dir in @((Join-Path $portableLeopard 'runtime'),$portableBridge)){[void][IO.Directory]::CreateDirectory($dir)}
    Copy-Item (Join-Path $desktop 'leopardwm-test\Install-LeopardWM.ps1') $portableLeopard
    foreach($file in @('DesktopBridge.cs','KomorebiFeed.cs','ScrollingMouseNavigation.cs','FloatingPopupGuard.cs')){Copy-Item (Join-Path $desktop ('yasb-catppuccin\'+$file)) $portableBridge}
    if($ReleaseArchive){Copy-Item -LiteralPath $ReleaseArchive -Destination (Join-Path $portableLeopard 'runtime\LeopardWM-0.3.4-x86_64-windows.zip')}
    & (Join-Path $portableLeopard 'Install-LeopardWM.ps1')
    $manifest=Get-Content (Join-Path $portableLeopard 'runtime\release.json') -Raw|ConvertFrom-Json
    Assert ($manifest.version -eq '0.3.4') 'Unexpected portable version'
    $binary=Join-Path $portableLeopard ('runtime\'+$manifest.directory+'\leopardwm.exe')
    $before=(Get-FileHash $binary).Hash
    & (Join-Path $portableLeopard 'Install-LeopardWM.ps1')
    Assert ((Get-FileHash $binary).Hash -eq $before) 'Repeated installation replaced native binary'
    $controller=Join-Path $portableLeopard 'runtime\DesktopBridge.exe'
    $bytes=[IO.File]::ReadAllBytes($controller);[IO.File]::WriteAllBytes($controller,($bytes+[byte]0))
    $rejected=$false;try{& (Join-Path $portableLeopard 'Install-LeopardWM.ps1')|Out-Null}catch{$rejected=$true}
    Assert $rejected 'Changed installed controller must fail verification'
    [IO.File]::WriteAllBytes($controller,$bytes)
}
Write-Host 'Window-manager checks passed: selection, first login, routing, panel conversion and optional pinned portable install. No real WM or AHK was started.'
