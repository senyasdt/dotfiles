param(
    [string[]]$Profiles=$(if($env:CHEZMOI_PROFILES){$env:CHEZMOI_PROFILES}else{'full'}),
    [ValidateSet('none','yasb','mydockfinder')][string]$Bar='none',
    [ValidateSet('classic','catppuccin')][string]$Theme='classic',
    [switch]$Plan
)
$ErrorActionPreference = "Stop"
$activeProfiles=@(($Profiles -join ',').Split(',')|ForEach-Object {$_.Trim()})
if(@($activeProfiles|Where-Object {$_ -notin @('lite','full','desktop')}).Count -or ($activeProfiles -contains 'lite' -and $activeProfiles.Count -gt 1) -or ($activeProfiles -contains 'desktop' -and $activeProfiles -notcontains 'full')){throw 'Use lite, full or full,desktop'}
$desktop=$activeProfiles -contains 'desktop'

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Install-Scoop {
    if (Test-Command scoop) {
        return
    }

    Write-Step "Installing Scoop"
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Invoke-RestMethod -Uri "https://get.scoop.sh" | Invoke-Expression
}

function Install-ScoopPackage {
    param([Parameter(Mandatory = $true)][string]$Package)

    $installed = scoop list $Package 2>$null
    if ($LASTEXITCODE -eq 0 -and $installed) {
        return
    }

    Write-Step "Installing Scoop package $Package"
    scoop install $Package
    if($LASTEXITCODE -ne 0){throw "Scoop failed: $Package"}
}

function Install-WingetPackage {
    param([Parameter(Mandatory = $true)][string]$Id)

    $existing = winget list --id $Id --exact --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing -match [regex]::Escape($Id)) {
        if($Id -eq 'AmN.yasb'){
            $yasbPath=Join-Path $env:ProgramFiles 'YASB\yasb.exe'
            $version=if(Test-Path -LiteralPath $yasbPath){(Get-Item -LiteralPath $yasbPath).VersionInfo.ProductVersion}else{''}
            if($version -notmatch '^(\d+\.\d+\.\d+)' -or [version]$Matches[1] -lt [version]'2.0.7'){
                Write-Step 'Upgrading YASB for the current configuration schema'
                winget upgrade --id $Id --exact --source winget --accept-source-agreements --accept-package-agreements
                if($LASTEXITCODE -notin @(0,3010)){throw "WinGet upgrade failed: $Id ($LASTEXITCODE)"}
                $version=if(Test-Path -LiteralPath $yasbPath){(Get-Item -LiteralPath $yasbPath).VersionInfo.ProductVersion}else{''}
                if($version -notmatch '^(\d+\.\d+\.\d+)' -or [version]$Matches[1] -lt [version]'2.0.7'){throw 'YASB 2.0.7 or newer is required; configuration was not applied.'}
            }
        }
        return
    }

    Write-Step "Installing WinGet package $Id"
    winget install --id $Id --exact --accept-source-agreements --accept-package-agreements
    if($LASTEXITCODE -notin @(0,3010)){throw "WinGet failed: $Id ($LASTEXITCODE)"}
}

function Install-PowerShellModuleIfMissing {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (Get-Module -ListAvailable -Name $Name) {
        return
    }

    Write-Step "Installing PowerShell module $Name"
    Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
}

$scoopPackages = @(
    "git",
    "python",
    "make",
    "gcc",
    "neovim",
    "ripgrep",
    "fd",
    "fzf",
    "eza",
    "bat",
    "zoxide",
    "yazi",
    "jq",
    "fastfetch",
    "chezmoi",
    "nodejs-lts",
    "7zip"
)

$wingetPackages = @(
    "wez.wezterm",
    "JanDeDobbeleer.OhMyPosh",
    "Google.Chrome",
    "Telegram.TelegramDesktop",
    "JetBrains.IntelliJIDEA.Ultimate",
    "Microsoft.PowerToys",
    "Flow-Launcher.Flow-Launcher",
    "AutoHotkey.AutoHotkey",
    "Microsoft.VisualStudioCode"
)
if($activeProfiles -contains 'lite'){$scoopPackages=@('git','ripgrep','fd','fzf','bat','jq','chezmoi')}
if($desktop){$scoopPackages+=@('komorebi','whkd')}else{$wingetPackages=@()}
if($desktop -and $Bar -eq 'yasb'){$wingetPackages+='AmN.yasb'}
if($Theme -eq 'catppuccin'){$wingetPackages=@($wingetPackages|Where-Object {$_ -ne 'Flow-Launcher.Flow-Launcher'})}

$powershellModules = @(
    "posh-git",
    "Terminal-Icons",
    "PSFzf"
)
if($Plan){[pscustomobject]@{Profiles=$activeProfiles;Bar=$Bar;Scoop=$scoopPackages;Winget=$wingetPackages;Modules=$powershellModules;Manual=@('Vial/ZMK helpers: install from their source releases','MyDockFinder: optional Steam installation','Custom keyboard layouts: restore approved installers')}|ConvertTo-Json -Depth 5;return}
if($wingetPackages.Count -and -not(Test-Command winget)){throw 'winget is required for the selected desktop packages'}
Install-Scoop
if($desktop){
    if(-not(Test-Path -LiteralPath (Join-Path $env:USERPROFILE 'scoop\buckets\extras'))){scoop bucket add extras;if($LASTEXITCODE -ne 0){throw 'Scoop extras bucket failed'}}
}

foreach ($package in $scoopPackages) {
    Install-ScoopPackage -Package $package
}

foreach ($package in $wingetPackages) {
    Install-WingetPackage -Id $package
}

if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
    Register-PSRepository -Default
}

Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

foreach ($module in $powershellModules) {
    Install-PowerShellModuleIfMissing -Name $module
}
