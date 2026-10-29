param(
    [string[]]$Profiles=@('full','desktop'),
    [ValidateSet('none','yasb')][string]$Bar,
    [ValidateSet('classic','catppuccin')][string]$Theme,
    [ValidateSet('Leopard','Komorebi')][string]$WindowManager,
    [switch]$Apply,
    [switch]$SkipTechnicalLayouts
)
$ErrorActionPreference='Stop'
# PowerShell callers and update.ps1 may pass either an array or comma text.
$Profiles=@(($Profiles -join ',').Split(',')|ForEach-Object {$_.Trim()}|Where-Object {$_})
$profileText=$Profiles -join ','
$source=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$defaults=(Get-Content -LiteralPath (Join-Path $source '.chezmoidata\windows-desktop.json') -Raw|ConvertFrom-Json).windowsDesktop
$desktop=$Profiles -contains 'desktop'
if(-not $Bar){$Bar=if($desktop){$defaults.bar}else{'none'}}
if(-not $Theme){$Theme=if($Bar -eq 'yasb'){$defaults.theme}else{'classic'}}
if(-not $WindowManager){$WindowManager=if($desktop -and $Bar -eq 'yasb' -and $Theme -eq 'catppuccin'){$defaults.windowManager}else{'Komorebi'}}
if($Theme -eq 'catppuccin' -and ($Bar -ne 'yasb' -or $Profiles -notcontains 'desktop')){throw 'Catppuccin requires -Bar yasb and the desktop profile'}
if($WindowManager -eq 'Leopard' -and (-not $desktop -or $Theme -ne 'catppuccin' -or $Bar -ne 'yasb')){throw 'LeopardWM requires full,desktop with YASB Catppuccin.'}
if(-not $Apply){
    & (Join-Path $PSScriptRoot 'install.ps1') -Profiles $Profiles -Bar $Bar -Theme $Theme -Plan
    Write-Host ('Desktop: '+$WindowManager+' / '+$Bar+' / '+$Theme+'. LeopardWM is pinned to 0.3.4 and verified with SHA256; existing choices are preserved until Apply.')
    Write-Host 'Plan only. Apply will provision packages, apply chezmoi files, build helpers and register desktop startup. No game/Steam or HID-helper installer is run automatically.'
    if($desktop -and -not $SkipTechnicalLayouts){Write-Host 'Desktop Apply also installs the verified English/Russian Technical AltGr layouts; machine changes may request Windows administrator consent. Sign out/in after a new installation.'}
    return
}
if(-not(Get-Command chezmoi -ErrorAction SilentlyContinue)){throw 'Install chezmoi and initialize the dotfiles repository first.'}
$managedRoot=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config\desktop-customization'
$priorChoice=Join-Path $managedRoot 'leopardwm-test\runtime\selection.json'
if($Theme -eq 'classic' -and (Test-Path -LiteralPath $priorChoice) -and (Get-Content -LiteralPath $priorChoice -Raw|ConvertFrom-Json).enabled){throw 'Switch to komorebi before restoring the classic theme; no packages or files were changed.'}
$env:CHEZMOI_PROFILES=$profileText
$env:WINDOWS_DESKTOP_BAR=$Bar
$env:WINDOWS_DESKTOP_THEME=$Theme
$env:WINDOWS_DESKTOP_WM=$WindowManager
& (Join-Path $PSScriptRoot 'install.ps1') -Profiles $Profiles -Bar $Bar -Theme $Theme
chezmoi --source $source apply --exclude externals
if($LASTEXITCODE -ne 0){throw 'chezmoi apply failed; desktop activation was not attempted.'}
if($profileText.Split(',') -contains 'desktop'){
    if(-not $SkipTechnicalLayouts){
        & (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Install-TechnicalLayouts.ps1') -Action Apply -Root $managedRoot
        if($LASTEXITCODE -ne 0){throw 'Technical AltGr installation failed; desktop activation was not attempted. See Install-TechnicalLayouts.ps1 -Action Plan.'}
    }
    & (Join-Path $PSScriptRoot 'desktop.ps1') -Action Install
    if($Theme -eq 'catppuccin'){
        $themeRoot=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config\desktop-customization\yasb-catppuccin'
        & (Join-Path $themeRoot 'Manage.ps1') -Action Build
        $leopardRoot=Join-Path (Split-Path $themeRoot) 'leopardwm-test'
        if($WindowManager -eq 'Leopard'){& (Join-Path $leopardRoot 'Install-LeopardWM.ps1')}
        & (Join-Path $themeRoot 'Manage.ps1') -Action Apply
        if($WindowManager -eq 'Leopard'){
            & (Join-Path $leopardRoot 'Use-WindowManager.ps1') -Mode Leopard -Confirm:$false
            & (Join-Path $leopardRoot 'Use-WindowManager.ps1') -Mode Leopard -Operation Reload -Confirm:$false
        }else{
            $choice=Join-Path $leopardRoot 'runtime\selection.json'
            if((Test-Path -LiteralPath $choice) -and (Get-Content -LiteralPath $choice -Raw|ConvertFrom-Json).enabled){
                & (Join-Path $leopardRoot 'Use-WindowManager.ps1') -Mode Komorebi -Confirm:$false
                # Return restores an older bar snapshot; render the current shared UI again.
                & (Join-Path $themeRoot 'Manage.ps1') -Action Refresh
            }
            & (Join-Path $managedRoot 'komorebi-support\Start-DesktopWM.ps1')
        }
        $appearanceRoot=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config\desktop-customization\appearance'
        & (Join-Path $appearanceRoot 'Manage-Appearance.ps1') -Action Apply
    }else{
        & (Join-Path $managedRoot 'komorebi-support\Start-DesktopWM.ps1')
    }
}
# Keep future native Windows sessions/apply consistent with the chosen profile.
[Environment]::SetEnvironmentVariable('CHEZMOI_PROFILES',$profileText,'User')
[Environment]::SetEnvironmentVariable('WINDOWS_DESKTOP_BAR',$Bar,'User')
[Environment]::SetEnvironmentVariable('WINDOWS_DESKTOP_THEME',$Theme,'User')
[Environment]::SetEnvironmentVariable('WINDOWS_DESKTOP_WM',$WindowManager,'User')
Write-Host 'Restore source applied. See provision/windows/README.md for manual checkpoints and the verification scope.'
