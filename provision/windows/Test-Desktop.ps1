param([switch]$DownloadRelease,[string]$ReleaseArchive)
$ErrorActionPreference='Stop'
$source=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$desktop=Join-Path $source 'dot_config\desktop-customization'
foreach($profile in @('lite','full','full,desktop')){
    $plan=& (Join-Path $PSScriptRoot 'install.ps1') -Profiles $profile -Plan|ConvertFrom-Json
    if($profile -eq 'lite' -and ($plan.Winget.Count -or $plan.Scoop -contains 'mise')){throw 'Full packages leaked into lite'}
    if($profile -eq 'full' -and (@($plan.Winget|Where-Object {$_ -ne 'Docker.DockerDesktop'}).Count -or $plan.Winget -notcontains 'Docker.DockerDesktop' -or $plan.Scoop -notcontains 'mise')){throw 'Full profile must retain upstream mise/Docker without desktop apps'}
    if($plan.Winget -contains 'AmN.yasb'){throw 'YASB must be opt-in'}
}
$savedProfiles=$env:CHEZMOI_PROFILES
try{
    $env:CHEZMOI_PROFILES='full,desktop'
    $lite=& (Join-Path $PSScriptRoot 'install.ps1') -Profiles lite -Plan|ConvertFrom-Json
    if($lite.Winget.Count -or $lite.Scoop -contains 'mise'){throw 'Explicit lite profile lost to inherited environment'}
    & (Join-Path $PSScriptRoot 'restore.ps1') -Profiles 'full,desktop' -Bar yasb -Theme catppuccin | Out-Null
}finally{$env:CHEZMOI_PROFILES=$savedProfiles}
$yasb=& (Join-Path $PSScriptRoot 'install.ps1') -Profiles full,desktop -Bar yasb -Plan|ConvertFrom-Json
if($yasb.Winget -notcontains 'AmN.yasb' -or $yasb.Scoop -notcontains 'komorebi'){throw 'Desktop package plan is incomplete'}
if($yasb.Scoop -notcontains 'JetBrainsMono-NF'){throw 'YASB icon font is missing from new-machine setup'}
foreach($file in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1')+@(Get-ChildItem -LiteralPath $desktop -Filter '*.ps1' -Recurse)){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors){throw ('PowerShell parse error in '+$file.FullName+': '+($errors.Message -join '; '))}
}
& (Join-Path $source 'provision\tests\Test-Appearance.ps1')
& (Join-Path $source 'provision\tests\Test-SessionStartup.ps1')
& (Join-Path $source 'provision\tests\Test-LayoutGuardStartup.ps1')
& (Join-Path $source 'provision\tests\Test-StartupPolicy.ps1')
& (Join-Path $source 'provision\tests\Test-WindowManager.ps1') -DownloadRelease:$DownloadRelease -ReleaseArchive $ReleaseArchive
$build=Join-Path ([IO.Path]::GetTempPath()) ('desktop-source-check-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($build)|Out-Null
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $csc /nologo /target:exe /platform:x64 /main:LauncherTests /codepage:65001 /r:System.Management.dll /r:System.Web.Extensions.dll ('/out:'+(Join-Path $build 'LauncherTests.exe')) (Join-Path $desktop 'script-launcher\ScriptLauncher.cs') (Join-Path $desktop 'script-launcher\LauncherTests.cs')
if($LASTEXITCODE -ne 0){throw 'Launcher tests failed to compile'}
& (Join-Path $build 'LauncherTests.exe')
if($LASTEXITCODE -ne 0){throw 'Launcher tests failed'}
& $csc /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll ('/out:'+(Join-Path $build 'DesktopBridge.exe')) (Join-Path $desktop 'yasb-catppuccin\DesktopBridge.cs') (Join-Path $desktop 'yasb-catppuccin\KomorebiFeed.cs') (Join-Path $desktop 'yasb-catppuccin\ScrollingMouseNavigation.cs')
if($LASTEXITCODE -ne 0){throw 'Desktop bridge failed to compile'}
$bridgeTest=Start-Process -FilePath (Join-Path $build 'DesktopBridge.exe') -ArgumentList '--test' -WindowStyle Hidden -PassThru -Wait
if($bridgeTest.ExitCode -ne 0){throw 'Desktop bridge policy checks failed'}
& $csc /nologo /target:winexe /platform:x64 /optimize+ ('/out:'+(Join-Path $build 'TechnicalAltGrLayoutGuard.exe')) (Join-Path $desktop 'keyboard-layout-guard\LayoutGuard.cs')
if($LASTEXITCODE -ne 0){throw 'Layout guard failed to compile'}
Write-Host 'Desktop checks passed: plans, PowerShell syntax, AHK engine checks, appearance rollback and isolated helper builds.'
