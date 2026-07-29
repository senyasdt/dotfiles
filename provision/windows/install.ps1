$ErrorActionPreference = "Stop"

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
}

function Install-WingetPackage {
    param([Parameter(Mandatory = $true)][string]$Id)

    $existing = winget list --id $Id --exact --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing -match [regex]::Escape($Id)) {
        return
    }

    Write-Step "Installing WinGet package $Id"
    winget install --id $Id --exact --accept-source-agreements --accept-package-agreements
}

function Install-PowerShellModuleIfMissing {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (Get-Module -ListAvailable -Name $Name) {
        return
    }

    Write-Step "Installing PowerShell module $Name"
    Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
}

if (-not (Test-Command winget)) {
    throw "winget is required on Windows to install GUI packages."
}

Install-Scoop

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
    "LGUG2Z.komorebi",
    "LGUG2Z.whkd",
    "AmN.yasb",
    "AutoHotkey.AutoHotkey",
    "Microsoft.VisualStudioCode"
)

$powershellModules = @(
    "posh-git",
    "Terminal-Icons",
    "PSFzf"
)

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
