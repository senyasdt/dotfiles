[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$BundleDirectory,
    [ValidateSet('Trial','Strip')][string]$Kind='Trial')
$ErrorActionPreference='Stop'
$runtime=Join-Path $PSScriptRoot 'runtime'
$manifest=Join-Path $runtime 'motion-bundles.json'
$existing=if(Test-Path -LiteralPath $manifest){Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json}else{[pscustomobject]@{}}
if($Kind -eq 'Trial' -and (Test-Path -LiteralPath $manifest)){throw 'A movement trial already exists. Its original rollback bundle will not be overwritten.'}
$patchName=if($Kind -eq 'Strip'){'strip-shared-motion.patch'}else{'latest-target-movement.patch'}
$patchHash=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot ('native\'+$patchName))).Hash
$info=Get-Content -LiteralPath (Join-Path $BundleDirectory 'build-info.json') -Raw|ConvertFrom-Json
if($info.patches.$patchName -ine $patchHash){throw 'Movement patch hash does not match this tested bundle.'}
foreach($file in @('komorebi.exe','komorebic.exe')){
    if((Get-FileHash -LiteralPath (Join-Path $BundleDirectory $file)).Hash -ine $info.hashes.$file){throw "Bundle hash mismatch: $file"}
}
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$bridgeRoot=Join-Path (Split-Path $PSScriptRoot) 'yasb-catppuccin'
function Entry($directory,$animation){
    $hashes=[ordered]@{}
    foreach($file in @('komorebi.exe','komorebic.exe','build-info.json','DesktopBridge.exe')){$hashes[$file]=(Get-FileHash -LiteralPath (Join-Path $directory $file)).Hash}
    return [ordered]@{directory=(Split-Path $directory -Leaf);hashes=$hashes;animation=$animation}
}
if($existing.Previous){
    $previous=[IO.Path]::GetFullPath((Join-Path $runtime $existing.Previous.directory))
    if(-not $previous.StartsWith(([IO.Path]::GetFullPath($runtime).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Previous bundle must be inside runtime.'}
    foreach($file in @('komorebi.exe','komorebic.exe','build-info.json','DesktopBridge.exe')){
        if((Get-FileHash -LiteralPath (Join-Path $previous $file)).Hash -ine $existing.Previous.hashes.$file){throw "Original rollback hash mismatch: $file"}
    }
}else{
    $previous=Join-Path $runtime ("motion-previous-$stamp")
    [IO.Directory]::CreateDirectory($previous)|Out-Null
    foreach($file in @('komorebi.exe','komorebic.exe','build-info.json')){Copy-Item -LiteralPath (Join-Path $runtime ('native\'+$file)) -Destination $previous}
    Copy-Item -LiteralPath (Join-Path $bridgeRoot 'DesktopBridge.exe') -Destination $previous
    $config=Get-Content -LiteralPath (Join-Path $runtime 'native-config.json') -Raw|ConvertFrom-Json
    if(-not $config.animation){throw 'Cannot determine the previous animation settings.'}
    $existing|Add-Member -NotePropertyName Previous -NotePropertyValue (Entry $previous $config.animation)
}
$trial=Join-Path $runtime ("motion-"+$Kind.ToLowerInvariant()+"-$stamp")
[IO.Directory]::CreateDirectory($trial)|Out-Null
foreach($file in @('komorebi.exe','komorebic.exe','build-info.json')){Copy-Item -LiteralPath (Join-Path $BundleDirectory $file) -Destination $trial}
$inputs=@('DesktopBridge.cs','KomorebiFeed.cs','ScrollingMouseNavigation.cs')|ForEach-Object{Join-Path $bridgeRoot $_}
& (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll ('/out:'+(Join-Path $trial 'DesktopBridge.exe')) @inputs
if($LASTEXITCODE -ne 0){throw 'Bridge trial build failed; nothing switched.'}
$test=Start-Process -FilePath (Join-Path $trial 'DesktopBridge.exe') -ArgumentList '--test' -WindowStyle Hidden -PassThru
try{if(-not $test.WaitForExit(10000) -or $test.ExitCode -ne 0){throw 'Bridge policy tests failed; nothing switched.'}}finally{$test.Dispose()}
$duration=if($Kind -eq 'Strip'){90}else{160}
$entry=Entry $trial ([ordered]@{enabled=@{movement=$true};duration=@{movement=$duration};style=@{movement='EaseOutSine'};fps=60})
$existing|Add-Member -NotePropertyName $Kind -NotePropertyValue $entry -Force
if(Test-Path -LiteralPath $manifest){Copy-Item -LiteralPath $manifest -Destination (Join-Path $runtime ("motion-bundles-before-$stamp.json"))}
[IO.File]::WriteAllText($manifest,($existing|ConvertTo-Json -Depth 30),(New-Object Text.UTF8Encoding($false)))
Write-Output "Movement bundle $Kind staged. The original Previous bundle was preserved."
