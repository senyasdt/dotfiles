param(
    [string[]]$Profiles=@('full','desktop'),
    [ValidateSet('none','yasb','mydockfinder')][string]$Bar='none',
    [switch]$Apply
)
$ErrorActionPreference='Stop'
$profileText=$Profiles -join ','
$source=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if(-not $Apply){
    & (Join-Path $PSScriptRoot 'install.ps1') -Profiles $Profiles -Bar $Bar -Plan
    Write-Host 'Plan only. Apply will provision packages, apply chezmoi files, build helpers and register desktop startup. No game/Steam, HID-helper or custom-layout installer is run automatically.'
    return
}
if(-not(Get-Command chezmoi -ErrorAction SilentlyContinue)){throw 'Install chezmoi and initialize the dotfiles repository first.'}
$env:CHEZMOI_PROFILES=$profileText
$env:WINDOWS_DESKTOP_BAR=$Bar
& (Join-Path $PSScriptRoot 'install.ps1') -Profiles $Profiles -Bar $Bar
chezmoi --source $source apply --exclude externals
if($LASTEXITCODE -ne 0){throw 'chezmoi apply failed; desktop activation was not attempted.'}
if($profileText.Split(',') -contains 'desktop'){
    & (Join-Path $PSScriptRoot 'desktop.ps1') -Action Install
}
# Keep future native Windows sessions/apply consistent with the chosen profile.
[Environment]::SetEnvironmentVariable('CHEZMOI_PROFILES',$profileText,'User')
[Environment]::SetEnvironmentVariable('WINDOWS_DESKTOP_BAR',$Bar,'User')
Write-Host 'Restore source applied. See provision/windows/README.md for manual checkpoints and the verification scope.'
