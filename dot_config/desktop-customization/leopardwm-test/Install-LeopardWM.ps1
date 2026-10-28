[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$runtime=Join-Path $PSScriptRoot 'runtime'
$version='0.3.4'
$hash='698E6E7346FF3FFD84AEE3EBF502CF036A74D4804882758B439A820E0A5983B0'
$name="LeopardWM-$version-x86_64-windows"
$url="https://github.com/jcardama/LeopardWM/releases/download/v$version/$name.zip"
if($env:PROCESSOR_ARCHITECTURE -ne 'AMD64'){throw 'This trial is pinned to Windows x64.'}
$manifestPath=Join-Path $runtime 'release.json'
if(Test-Path -LiteralPath $manifestPath){
    $existing=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
    if($existing.version -ne $version -or $existing.directory -ne $name -or $existing.archiveSha256 -ine $hash){throw 'Another portable release is installed; explicit migration is required.'}
    foreach($file in @('leopardwm.exe','leopardwm-cli.exe','lwm.exe','leopardwm-watchdog.exe')){
        if((Get-FileHash -LiteralPath (Join-Path $runtime ($name+'\'+$file))).Hash -ine $existing.hashes.$file){throw "Installed release checksum mismatch: $file"}
    }
    if((Get-FileHash -LiteralPath (Join-Path $runtime 'DesktopBridge.exe')).Hash -ine $existing.controllerSha256){throw 'Installed controller checksum mismatch.'}
    Write-Output "LeopardWM $version already installed and verified; binaries left intact."
    return
}
[void][IO.Directory]::CreateDirectory($runtime)
$archive=Join-Path $runtime ($name+'.zip')
if(-not(Test-Path -LiteralPath $archive)){Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing}
if((Get-FileHash -LiteralPath $archive).Hash -ine $hash){throw 'Official release archive checksum mismatch.'}
$bin=Join-Path $runtime $name
if(Test-Path -LiteralPath $bin){throw 'Trial already staged. Keep its manifest; do not overwrite running binaries.'}
Expand-Archive -LiteralPath $archive -DestinationPath $runtime
$bridgeRoot=Join-Path (Split-Path $PSScriptRoot) 'yasb-catppuccin'
$inputs=@('DesktopBridge.cs','KomorebiFeed.cs','ScrollingMouseNavigation.cs')|ForEach-Object{Join-Path $bridgeRoot $_}
$controller=Join-Path $runtime 'DesktopBridge.exe'
& (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll ('/out:'+$controller) @inputs
if($LASTEXITCODE -ne 0){throw 'Trial controller build failed.'}
$test=Start-Process -FilePath $controller -ArgumentList '--test' -WindowStyle Hidden -PassThru
try{if(-not $test.WaitForExit(10000) -or $test.ExitCode -ne 0){throw 'Controller policy tests failed.'}}finally{$test.Dispose()}
$files=[ordered]@{}
foreach($file in @('leopardwm.exe','leopardwm-cli.exe','lwm.exe','leopardwm-watchdog.exe')){$files[$file]=(Get-FileHash -LiteralPath (Join-Path $bin $file)).Hash}
$manifest=[ordered]@{version=$version;url=$url;archiveSha256=$hash;directory=$name;hashes=$files;controllerSha256=(Get-FileHash -LiteralPath $controller).Hash}
[IO.File]::WriteAllText((Join-Path $runtime 'release.json'),($manifest|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
Write-Output "LeopardWM $version staged; no managers or autostart entries changed."
