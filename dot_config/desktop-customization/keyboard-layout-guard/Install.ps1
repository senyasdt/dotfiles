$ErrorActionPreference = 'Stop'
$fixRoot = $PSScriptRoot
$executable = Join-Path $fixRoot 'TechnicalAltGrLayoutGuard.exe'
$runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$valueName = 'TechnicalAltGrLayoutGuard'
if (-not (Test-Path -LiteralPath $executable)) { throw 'Build the helper before installing.' }
$backup = Join-Path $fixRoot 'backup'
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$statePath = Join-Path $backup 'startup-before.json'
if (-not (Test-Path -LiteralPath $statePath)) {
    $runKey = Get-Item -LiteralPath $runPath -ErrorAction SilentlyContinue
    $previous = if ($runKey) { $runKey.GetValue($valueName, $null) } else { $null }
    @{ existed = $null -ne $previous; value = $previous } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
    & reg.exe export 'HKCU\Keyboard Layout' (Join-Path $backup 'keyboard-layout.reg') /y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Keyboard layout backup failed.' }
    & reg.exe export 'HKCU\Control Panel\International\User Profile' (Join-Path $backup 'language-profile.reg') /y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Language profile backup failed.' }
}
New-Item -Path $runPath -Force | Out-Null
New-ItemProperty -LiteralPath $runPath -Name $valueName -Value ('"' + $executable + '"') -PropertyType String -Force | Out-Null
$started = Start-Process -FilePath $executable -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 3
Get-ItemPropertyValue -LiteralPath $runPath -Name $valueName
Get-Content -LiteralPath (Join-Path $fixRoot 'status.txt')
Get-Process -Name TechnicalAltGrLayoutGuard -ErrorAction Stop | Select-Object Id,ProcessName,Path
