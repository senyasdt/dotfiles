$ErrorActionPreference='Stop'
$source=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$desktop=Join-Path $source 'dot_config\desktop-customization'
foreach($profile in @('lite','full','full,desktop')){
    $plan=& (Join-Path $PSScriptRoot 'install.ps1') -Profiles $profile -Plan|ConvertFrom-Json
    if($profile -ne 'full,desktop' -and $plan.Winget.Count){throw ('GUI packages leaked into '+$profile)}
    if($plan.Winget -contains 'AmN.yasb'){throw 'YASB must be opt-in'}
}
$yasb=& (Join-Path $PSScriptRoot 'install.ps1') -Profiles full,desktop -Bar yasb -Plan|ConvertFrom-Json
if($yasb.Winget -notcontains 'AmN.yasb' -or $yasb.Scoop -notcontains 'komorebi'){throw 'Desktop package plan is incomplete'}
foreach($file in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1')+@(Get-ChildItem -LiteralPath $desktop -Filter '*.ps1' -Recurse)){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors){throw ('PowerShell parse error in '+$file.FullName+': '+($errors.Message -join '; '))}
}
& (Join-Path $source 'provision\tests\Test-Appearance.ps1')
$build=Join-Path ([IO.Path]::GetTempPath()) ('desktop-source-check-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($build)|Out-Null
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $csc /nologo /target:exe /platform:x64 /main:LauncherTests /codepage:65001 /r:System.Management.dll /r:System.Web.Extensions.dll ('/out:'+(Join-Path $build 'LauncherTests.exe')) (Join-Path $desktop 'script-launcher\ScriptLauncher.cs') (Join-Path $desktop 'script-launcher\LauncherTests.cs')
if($LASTEXITCODE -ne 0){throw 'Launcher tests failed to compile'}
& (Join-Path $build 'LauncherTests.exe')
if($LASTEXITCODE -ne 0){throw 'Launcher tests failed'}
& $csc /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll /r:System.Management.dll ('/out:'+(Join-Path $build 'FinderWidgets.exe')) (Join-Path $desktop 'finder-widgets\FinderWidgets.cs')
if($LASTEXITCODE -ne 0){throw 'Widgets failed to compile'}
& $csc /nologo /target:winexe /platform:x64 /optimize+ ('/out:'+(Join-Path $build 'TechnicalAltGrLayoutGuard.exe')) (Join-Path $desktop 'keyboard-layout-guard\LayoutGuard.cs')
if($LASTEXITCODE -ne 0){throw 'Layout guard failed to compile'}
Write-Host 'Desktop checks passed: plans, PowerShell syntax, AHK engine checks, appearance rollback and isolated helper builds.'
