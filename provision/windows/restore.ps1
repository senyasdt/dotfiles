param(
    [string[]]$Profiles=@('full','desktop'),
    [ValidateSet('none','yasb','mydockfinder')][string]$Bar='none',
    [ValidateSet('classic','catppuccin')][string]$Theme='classic',
    [switch]$Apply
)
$ErrorActionPreference='Stop'
$profileText=$Profiles -join ','
if($Theme -eq 'catppuccin' -and ($Bar -ne 'yasb' -or $Profiles -notcontains 'desktop')){throw 'Catppuccin requires -Bar yasb and the desktop profile'}
$source=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if(-not $Apply){
    & (Join-Path $PSScriptRoot 'install.ps1') -Profiles $Profiles -Bar $Bar -Theme $Theme -Plan
    Write-Host ('Desktop theme: '+$Theme+'. Catppuccin is opt-in and creates a private rollback snapshot.')
    Write-Host 'Plan only. Apply will provision packages, apply chezmoi files, build helpers and register desktop startup. No game/Steam, HID-helper or custom-layout installer is run automatically.'
    return
}
if(-not(Get-Command chezmoi -ErrorAction SilentlyContinue)){throw 'Install chezmoi and initialize the dotfiles repository first.'}
$env:CHEZMOI_PROFILES=$profileText
$env:WINDOWS_DESKTOP_BAR=$Bar
$env:WINDOWS_DESKTOP_THEME=$Theme
& (Join-Path $PSScriptRoot 'install.ps1') -Profiles $Profiles -Bar $Bar -Theme $Theme
chezmoi --source $source apply --exclude externals
if($LASTEXITCODE -ne 0){throw 'chezmoi apply failed; desktop activation was not attempted.'}
if($profileText.Split(',') -contains 'desktop'){
    & (Join-Path $PSScriptRoot 'desktop.ps1') -Action Install
    if($Theme -eq 'catppuccin'){
        $themeRoot=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config\desktop-customization\yasb-catppuccin'
        & (Join-Path $themeRoot 'Manage.ps1') -Action Build
        & (Join-Path $themeRoot 'Manage.ps1') -Action Apply
    }
}
# Keep future native Windows sessions/apply consistent with the chosen profile.
[Environment]::SetEnvironmentVariable('CHEZMOI_PROFILES',$profileText,'User')
[Environment]::SetEnvironmentVariable('WINDOWS_DESKTOP_BAR',$Bar,'User')
[Environment]::SetEnvironmentVariable('WINDOWS_DESKTOP_THEME',$Theme,'User')
Write-Host 'Restore source applied. See provision/windows/README.md for manual checkpoints and the verification scope.'
