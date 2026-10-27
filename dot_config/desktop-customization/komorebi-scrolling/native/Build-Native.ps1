[CmdletBinding()]
param([string]$BuildDirectory,[string]$Toolchain='1.99.1-x86_64-pc-windows-msvc',[switch]$SmoothMotion)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$base='24c0ce0b1df1b5d7d62c682a7e28b32980293883'
$patches=[ordered]@{
    'upstream-independent-widths.patch'='72110153BAFC0C5011DE957A17A11022E8E1ECECBB667A1A5317CD6ADAEDDEF9'
    'outer-edge-resize.patch'='9C79EE550E343DC74EFD52C41E3C0C41D8E3EAAEB5C634D25472727E9AE14A73'
}
if($SmoothMotion){$patches['latest-target-movement.patch']='75E165BB2744FEC35DB2C54F7D899272504A65284D820C842594824FE8A9FAF4'}
foreach($name in $patches.Keys){if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash -ine $patches[$name]){throw "Patch hash mismatch: $name"}}
if(-not(Get-Command cargo.exe -ErrorAction SilentlyContinue)){throw 'Install Rust with the Windows MSVC toolchain and Visual Studio C++ Build Tools first.'}
if(-not $BuildDirectory){$BuildDirectory=Join-Path $root ('runtime\build-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))}
if(Test-Path -LiteralPath $BuildDirectory){throw 'Choose a new build directory; existing checkouts are never reset.'}
$env:RUSTUP_TOOLCHAIN=$Toolchain
& git.exe clone --depth 1 --branch v0.1.41 https://github.com/LGUG2Z/komorebi.git $BuildDirectory
if($LASTEXITCODE -ne 0){throw 'Source clone failed'}
Push-Location $BuildDirectory
try{
    if((& git.exe rev-parse HEAD).Trim() -ne $base){throw 'Upstream tag moved; refusing to build a different base'}
    foreach($name in $patches.Keys){
        $path=Join-Path $PSScriptRoot $name
        & git.exe apply --check $path
        if($LASTEXITCODE -ne 0){throw "Patch no longer applies: $name"}
        & git.exe apply $path
        if($LASTEXITCODE -ne 0){throw "Patch failed: $name"}
    }
    & cargo.exe test --locked -p komorebi-layouts
    if($LASTEXITCODE -ne 0){throw 'Layout tests failed'}
    if($SmoothMotion){
        & cargo.exe test --locked -p komorebi --lib animation::retarget -- --test-threads=1
        if($LASTEXITCODE -ne 0){throw 'Movement retarget tests failed'}
    }
    & cargo.exe build --locked --release -p komorebi -p komorebic
    if($LASTEXITCODE -ne 0){throw 'Native build failed'}
    # Stage a new bundle; replacing a running binary is an explicit later step.
    $bundle=Join-Path $root ('runtime\bundle-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
    [IO.Directory]::CreateDirectory($bundle)|Out-Null
    $target=if($env:CARGO_TARGET_DIR){$env:CARGO_TARGET_DIR}else{Join-Path $BuildDirectory 'target'}
    $hashes=[ordered]@{}
    foreach($file in @('komorebi.exe','komorebic.exe')){
        Copy-Item -LiteralPath (Join-Path $target ('release\'+$file)) -Destination (Join-Path $bundle $file)
        $hashes[$file]=(Get-FileHash -LiteralPath (Join-Path $bundle $file)).Hash
    }
    $info=[ordered]@{base=$base;upstreamPr='https://github.com/LGUG2Z/komorebi/pull/1754';upstreamCommit='0fbe6f6a8b89b0b263cfec476dd940a8364f85dc';toolchain=$Toolchain;patches=$patches;hashes=$hashes;builtAt=[DateTimeOffset]::Now.ToString('o')}
    [IO.File]::WriteAllText((Join-Path $bundle 'build-info.json'),($info|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
    Write-Output "Tested bundle: $bundle. Keep the old native bundle before replacing runtime/native."
}finally{Pop-Location}
