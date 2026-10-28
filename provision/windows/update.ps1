param([switch]$Apply)
$ErrorActionPreference = "Stop"

$profiles = if ($env:CHEZMOI_PROFILES) { $env:CHEZMOI_PROFILES } else { "full" }
$theme=if($env:WINDOWS_DESKTOP_THEME){$env:WINDOWS_DESKTOP_THEME}else{'classic'}
$windowManager=$env:WINDOWS_DESKTOP_WM
$sourcePath = chezmoi source-path
if($LASTEXITCODE -ne 0){throw 'Cannot locate chezmoi source'}
if(-not $Apply){
    $options=@{Profiles=$profiles}
    if($env:WINDOWS_DESKTOP_BAR){$options.Bar=$env:WINDOWS_DESKTOP_BAR}
    if($env:WINDOWS_DESKTOP_THEME){$options.Theme=$theme}
    if($windowManager){$options.WindowManager=$windowManager}
    & (Join-Path $sourcePath 'provision\windows\restore.ps1') @options
    Write-Host 'Review git status and chezmoi diff; use -Apply to pull and restore.'
    return
}
$dirty=git -C $sourcePath status --porcelain
if($LASTEXITCODE -ne 0 -or $dirty){throw 'Source checkout must be clean before an update; save local source changes first.'}

git -C $sourcePath pull --ff-only
if($LASTEXITCODE -ne 0){throw 'Git pull failed; nothing was provisioned.'}

$options=@{Profiles=$profiles;Apply=$true}
if($env:WINDOWS_DESKTOP_BAR){$options.Bar=$env:WINDOWS_DESKTOP_BAR}
if($env:WINDOWS_DESKTOP_THEME){$options.Theme=$theme}
if($windowManager){$options.WindowManager=$windowManager}
& (Join-Path $sourcePath 'provision\windows\restore.ps1') @options
