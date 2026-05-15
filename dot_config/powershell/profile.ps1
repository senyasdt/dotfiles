function Test-Command {
    param([Parameter(Mandatory = $true)][string]$Name)

    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Import-VcVarsEnvironment {
    if ($script:VcVarsLoaded) {
        return
    }

    $vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path -LiteralPath $vcvars)) {
        return
    }

    $cmdOutput = & cmd.exe /d /s /c "`"$vcvars`" >nul && set"
    foreach ($line in $cmdOutput) {
        $separator = $line.IndexOf("=")
        if ($separator -lt 1) {
            continue
        }

        $name = $line.Substring(0, $separator)
        $value = $line.Substring($separator + 1)
        Set-Item -Path "Env:$name" -Value $value
    }

    $script:VcVarsLoaded = $true
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$env:Path = (@($userPath, $machinePath) | Where-Object { $_ }) -join ";"

$env:VISUAL = "nvim"
$env:EDITOR = "nvim"

if ((Test-Command python) -and (-not (Test-Command python3))) {
    Set-Alias python3 python -ErrorAction SilentlyContinue
}

if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue

    try {
        $predictionSource = if ($PSVersionTable.PSVersion.Major -ge 7) { "HistoryAndPlugin" } else { "History" }
        Set-PSReadLineOption -PredictionSource $predictionSource -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction Stop
    }
    catch {
    }

    try {
        Set-PSReadLineOption -BellStyle None -ErrorAction Stop
        Set-PSReadLineOption -HistorySearchCursorMovesToEnd -ErrorAction Stop
        Set-PSReadLineOption -Colors @{
            InlinePrediction = "#6c7086"
            Command          = "#8aadf4"
            Parameter        = "#c6a0f6"
            String           = "#a6da95"
            Operator         = "#f5a97f"
            Variable         = "#eed49f"
            Number           = "#f5bde6"
            Type             = "#91d7e3"
            Comment          = "#939ab7"
        } -ErrorAction Stop
    }
    catch {
    }

    try { Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward -ErrorAction Stop } catch {}
    try { Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward -ErrorAction Stop } catch {}
    try { Set-PSReadLineKeyHandler -Chord Tab -Function MenuComplete -ErrorAction Stop } catch {}
}

if (Get-Module -ListAvailable -Name posh-git) {
    Import-Module posh-git -ErrorAction SilentlyContinue
}

if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons -ErrorAction SilentlyContinue
}

if ((Get-Module -ListAvailable -Name PSFzf) -and (Test-Command fzf)) {
    Import-Module PSFzf -ErrorAction SilentlyContinue
    Set-PsFzfOption -PSReadlineChordProvider "Ctrl+t" -PSReadlineChordReverseHistory "Ctrl+r"
}

if (Test-Command zoxide) {
    Invoke-Expression (& { (zoxide init powershell --cmd cd | Out-String) })
}

function dev {
    $devRoot = if ($env:DEV_HOME) { $env:DEV_HOME } else { Join-Path $HOME "dev" }
    Set-Location -Path $devRoot
}

function y {
    if (-not (Test-Command yazi)) {
        Write-Warning "yazi is not installed."
        return
    }

    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        yazi @args --cwd-file="$tmp"
        $cwd = (Get-Content -LiteralPath $tmp -Raw).Trim()
        if ($cwd -and (Test-Path -LiteralPath $cwd)) {
            Set-Location -LiteralPath $cwd
        }
    }
    finally {
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
    }
}

if (Test-Command nvim) {
    $script:NvimExe = (Get-Command nvim -CommandType Application | Select-Object -First 1).Source

    function nvim {
        Import-VcVarsEnvironment

        $fullConfig = Join-Path $env:LOCALAPPDATA "nvim"
        $liteConfig = Join-Path $env:LOCALAPPDATA "nvim-lite"

        if (Test-Path -LiteralPath $fullConfig) {
            & $script:NvimExe @args
        }
        elseif (Test-Path -LiteralPath $liteConfig) {
            $env:NVIM_APPNAME = "nvim-lite"
            try {
                & $script:NvimExe @args
            }
            finally {
                Remove-Item Env:NVIM_APPNAME -ErrorAction SilentlyContinue
            }
        }
        else {
            & $script:NvimExe -u NONE -i NONE @args
        }
    }

    function vim { nvim @args }
}

if (Test-Command bat) {
    Remove-Item Alias:cat -ErrorAction SilentlyContinue
    function cat { bat --paging=never --style=plain @args }
}

if (Test-Command eza) {
    if (Get-Alias ls -ErrorAction SilentlyContinue) {
        Remove-Item Alias:ls -ErrorAction SilentlyContinue
    }
    function ls { eza --long --all --group --icons=auto @args }
}

if (Test-Command chezmoi) {
    Set-Alias ch chezmoi -ErrorAction SilentlyContinue
}

Clear-Host
if (Test-Command fastfetch) {
    fastfetch
}

$ompConfig = Join-Path $HOME ".config/powershell/druzh.omp.json"
if ((Test-Command oh-my-posh) -and (Test-Path -LiteralPath $ompConfig)) {
    oh-my-posh init pwsh --config $ompConfig | Invoke-Expression
}
