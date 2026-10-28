$ErrorActionPreference='Stop'
$source=Split-Path (Split-Path $PSScriptRoot)
$root=Join-Path ([IO.Path]::GetTempPath()) ('session-startup-check-'+[Guid]::NewGuid().ToString('N'))
foreach($relative in @('script-launcher','komorebi-support','yasb-catppuccin\runtime')){[void][IO.Directory]::CreateDirectory((Join-Path $root $relative))}
Copy-Item -LiteralPath (Join-Path $source 'dot_config\desktop-customization\Start-Session.ps1') -Destination $root
function Write-Fixture($relative,$text){[IO.File]::WriteAllText((Join-Path $root $relative),$text)}
Write-Fixture 'desktop.json' '{"theme":"catppuccin","bar":"yasb","startAhk":true,"startWindowManager":true}'
Write-Fixture 'yasb-catppuccin\runtime\profile.json' '{"mode":"catppuccin"}'
Write-Fixture 'script-launcher\Manage.ps1' 'param($Action); Add-Content (Join-Path $PSScriptRoot "actions.txt") $Action'
Write-Fixture 'komorebi-support\Start-DesktopWM.ps1' @'
$counter=Join-Path $PSScriptRoot 'calls.txt'
Add-Content $counter 'start'
if(@(Get-Content $counter).Count -eq 1){throw 'Simulated login dependency not ready'}
'ready'
'@
Write-Fixture 'yasb-catppuccin\Manage.ps1' 'param($Action); Add-Content (Join-Path $PSScriptRoot "actions.txt") $Action'
$savedTheme=$env:WINDOWS_DESKTOP_THEME
try{
    $env:WINDOWS_DESKTOP_THEME='catppuccin'
    & (Join-Path $root 'Start-Session.ps1')
    if(@(Get-Content (Join-Path $root 'komorebi-support\calls.txt')).Count -ne 2){throw 'Login transient failure was not retried'}
    if((Get-Content (Join-Path $root 'script-launcher\actions.txt')) -ne 'Start'){throw 'Startup must not enable or restart AHK scripts'}
    if((Get-Content (Join-Path $root 'yasb-catppuccin\actions.txt')) -ne 'Start'){throw 'Dock startup was skipped'}
    Write-Fixture 'komorebi-support\Start-DesktopWM.ps1' "throw 'Simulated persistent WM failure'"
    $rejected=$false
    try{& (Join-Path $root 'Start-Session.ps1')}catch{$rejected=$true}
    if(-not $rejected){throw 'Persistent startup failure was silently ignored'}
    if(@(Get-Content (Join-Path $root 'yasb-catppuccin\actions.txt')).Count -ne 2){throw 'WM failure must not prevent panel/dock startup'}
    if(-not (Test-Path -LiteralPath (Join-Path $root 'session-errors.log'))){throw 'Startup failure was not recorded'}
    # Reproduce the old early-exit bug: YASB's IPC probe throws, but the
    # independent dock controller still needs to be started for an existing bar.
    $manage=Join-Path $source 'dot_config\desktop-customization\yasb-catppuccin\Manage.ps1'
    $tokens=$null;$parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($manage,[ref]$tokens,[ref]$parseErrors)
    $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Start-Profile'},$true).Extent.Text
    & {
        param($definition,$root)
        . ([scriptblock]::Create($definition))
        $bridge=Join-Path $root 'fixture-bridge.exe';[IO.File]::WriteAllText($bridge,'fixture only')
        $yasb='fixture-yasb.exe';$script:bridgeStarted=$false
        function Assert-YasbVersion {}
        function Start-Yasb {throw 'Simulated unavailable komorebi IPC'}
        function Owned-Processes($name,$path){if($name -eq 'DesktopBridge' -and $script:bridgeStarted){@(1)}else{@()}}
        function Start-Process($FilePath,$WorkingDirectory,$WindowStyle){$script:bridgeStarted=$true}
        $failed=$false;try{Start-Profile}catch{$failed=$true}
        if(-not $failed -or -not $script:bridgeStarted){throw 'YASB preflight failure must be reported after starting the independent dock helper'}
    } $definition $root
}finally{$env:WINDOWS_DESKTOP_THEME=$savedTheme}
Write-Host 'Session startup checks passed: retry, independent dock startup, diagnostics and AHK Start-only. No desktop process was started.'
