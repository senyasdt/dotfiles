$ErrorActionPreference = 'Stop'
$executable = Join-Path $PSScriptRoot 'TechnicalAltGrLayoutGuard.exe'
$runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$valueName = 'TechnicalAltGrLayoutGuard'
$current = Get-ItemPropertyValue -LiteralPath $runPath -Name $valueName -ErrorAction SilentlyContinue
if ($current -eq ('"' + $executable + '"')) {
    $previous = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'backup\startup-before.json') -Raw | ConvertFrom-Json
    if ($previous.existed) {
        Set-ItemProperty -LiteralPath $runPath -Name $valueName -Value $previous.value
    } else {
        Remove-ItemProperty -LiteralPath $runPath -Name $valueName
    }
}
Start-Process -FilePath $executable -ArgumentList '--stop' -WindowStyle Hidden -Wait
Write-Output 'Automatic layout cleanup disabled. Custom layouts and language settings are unchanged.'
