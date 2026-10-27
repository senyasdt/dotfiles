[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$BundleDirectory)
$ErrorActionPreference='Stop'
$runtime=Join-Path $PSScriptRoot 'runtime'
$manifest=Join-Path $runtime 'motion-bundles.json'
if(Test-Path -LiteralPath $manifest){throw 'A movement trial already exists. Its original rollback bundle will not be overwritten.'}
$patchHash=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'native\latest-target-movement.patch')).Hash
$info=Get-Content -LiteralPath (Join-Path $BundleDirectory 'build-info.json') -Raw|ConvertFrom-Json
if($info.patches.'latest-target-movement.patch' -ine $patchHash){throw 'Build this trial using native/Build-Native.ps1 -SmoothMotion first.'}
foreach($file in @('komorebi.exe','komorebic.exe')){
    if((Get-FileHash -LiteralPath (Join-Path $BundleDirectory $file)).Hash -ine $info.hashes.$file){throw "Bundle hash mismatch: $file"}
}
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$previous=Join-Path $runtime ("motion-previous-$stamp")
$trial=Join-Path $runtime ("motion-trial-$stamp")
[IO.Directory]::CreateDirectory($previous)|Out-Null
[IO.Directory]::CreateDirectory($trial)|Out-Null
$bridgeRoot=Join-Path (Split-Path $PSScriptRoot) 'yasb-catppuccin'
foreach($file in @('komorebi.exe','komorebic.exe','build-info.json')){
    Copy-Item -LiteralPath (Join-Path $runtime ('native\'+$file)) -Destination $previous
    Copy-Item -LiteralPath (Join-Path $BundleDirectory $file) -Destination $trial
}
Copy-Item -LiteralPath (Join-Path $bridgeRoot 'DesktopBridge.exe') -Destination $previous
$inputs=@('DesktopBridge.cs','KomorebiFeed.cs','ScrollingMouseNavigation.cs')|ForEach-Object{Join-Path $bridgeRoot $_}
& (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll ('/out:'+(Join-Path $trial 'DesktopBridge.exe')) @inputs
if($LASTEXITCODE -ne 0){throw 'Bridge trial build failed; nothing switched.'}
$test=Start-Process -FilePath (Join-Path $trial 'DesktopBridge.exe') -ArgumentList '--test' -WindowStyle Hidden -PassThru
try{if(-not $test.WaitForExit(10000) -or $test.ExitCode -ne 0){throw 'Bridge policy tests failed; nothing switched.'}}finally{$test.Dispose()}
$config=Get-Content -LiteralPath (Join-Path $runtime 'native-config.json') -Raw|ConvertFrom-Json
$oldAnimation=$config.animation
if(-not $oldAnimation){throw 'Cannot determine the previous animation settings.'}
function Entry($directory,$animation){
    $hashes=[ordered]@{}
    foreach($file in @('komorebi.exe','komorebic.exe','build-info.json','DesktopBridge.exe')){$hashes[$file]=(Get-FileHash -LiteralPath (Join-Path $directory $file)).Hash}
    return [ordered]@{directory=(Split-Path $directory -Leaf);hashes=$hashes;animation=$animation}
}
$manifestValue=[ordered]@{
    Previous=(Entry $previous $oldAnimation)
    Trial=(Entry $trial ([ordered]@{enabled=@{movement=$true};duration=@{movement=160};style=@{movement='EaseOutSine'};fps=60}))
}
[IO.File]::WriteAllText($manifest,($manifestValue|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
Write-Output 'Trial staged and previous binaries preserved. Run Smooth-Motion.cmd; Restore-Motion.cmd reverts this trial.'
