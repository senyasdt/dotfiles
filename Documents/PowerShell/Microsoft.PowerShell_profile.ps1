$sharedProfile = Join-Path $HOME ".config/powershell/profile.ps1"

if (Test-Path -LiteralPath $sharedProfile) {
    . $sharedProfile
}
