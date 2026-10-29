$ErrorActionPreference='Stop'
$source=Split-Path (Split-Path $PSScriptRoot)
$root=Join-Path ([IO.Path]::GetTempPath()) ('session-startup-check-'+[Guid]::NewGuid().ToString('N'))
foreach($relative in @('script-launcher','komorebi-support','keyboard-layout-guard','yasb-catppuccin\runtime')){[void][IO.Directory]::CreateDirectory((Join-Path $root $relative))}
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
Write-Fixture 'keyboard-layout-guard\Start.ps1' 'Add-Content (Join-Path $PSScriptRoot "calls.txt") "start"'
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
    Write-Fixture 'desktop.json' '{"theme":"catppuccin","bar":"yasb","startAhk":true,"enableAhkOnLogin":true,"startWindowManager":false}'
    & (Join-Path $root 'Start-Session.ps1')
    if(@(Get-Content (Join-Path $root 'script-launcher\actions.txt'))[-1] -ne 'Login'){throw 'Login-enabled profile did not use the once-per-logon guard command'}
    if(Test-Path (Join-Path $root 'keyboard-layout-guard\calls.txt')){throw 'Optional layout cleanup ran without opt-in'}
    Write-Fixture 'desktop.json' '{"theme":"catppuccin","bar":"yasb","startAhk":true,"startLayoutGuard":true}'
    & (Join-Path $root 'Start-Session.ps1')
    if(@(Get-Content (Join-Path $root 'keyboard-layout-guard\calls.txt')).Count -ne 1){throw 'Enabled layout cleanup was skipped'}
    Write-Fixture 'keyboard-layout-guard\Start.ps1' "throw 'Simulated layout guard failure'"
    $ahkBefore=@(Get-Content (Join-Path $root 'script-launcher\actions.txt')).Count
    $rejected=$false
    try{& (Join-Path $root 'Start-Session.ps1')}catch{$rejected=$true}
    if(-not $rejected -or @(Get-Content (Join-Path $root 'script-launcher\actions.txt')).Count -ne ($ahkBefore+1)){throw 'Layout guard failure must be reported without preventing AHK startup'}
    & {
        param($source,$root)
        $fixture=Join-Path $root 'manage-fixture';[void][IO.Directory]::CreateDirectory($fixture)
        Copy-Item -LiteralPath (Join-Path $source 'dot_config\desktop-customization\script-launcher\Manage.ps1') -Destination $fixture
        function Get-Process { [pscustomobject]@{Name='ScriptLauncher'} }
        function Start-Process($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru){
            Add-Content -LiteralPath (Join-Path (Split-Path $FilePath) 'arguments.txt') -Value $ArgumentList
            $fake=[pscustomobject]@{ExitCode=0}
            $fake|Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {param($timeout) $true}
            return $fake
        }
        & (Join-Path $fixture 'Manage.ps1') -Action Login
        $calls=@(Get-Content -LiteralPath (Join-Path $fixture 'arguments.txt'))
        if($calls.Count -ne 2 -or $calls[1] -cne '"--login" "all"'){throw 'Login CLI operation and selector were not quoted separately'}
    } $source $root
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
Write-Host 'Session startup checks passed: retry, independent dock/layout/AHK startup, optional layout cleanup, diagnostics and AHK Start/Login dispatch. No desktop process was started.'
