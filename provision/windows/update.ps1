$ErrorActionPreference = "Stop"

$profiles = if ($env:CHEZMOI_PROFILES) { $env:CHEZMOI_PROFILES } else { "full" }
$sourcePath = chezmoi source-path

git -C $sourcePath pull --ff-only

$env:CHEZMOI_PROFILES = $profiles
powershell.exe -ExecutionPolicy Bypass -File (Join-Path $sourcePath "provision\windows\install.ps1")

chezmoi apply
