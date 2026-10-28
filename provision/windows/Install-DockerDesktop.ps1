param([string]$InstallerPath)
$ErrorActionPreference='Stop'
$localData=[Environment]::ExpandEnvironmentVariables((Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders').'Local AppData')
if(-not $localData){throw 'Cannot resolve the current user Local AppData folder'}
$userExecutable=Join-Path $localData 'Programs\DockerDesktop\Docker Desktop.exe'
$machineExecutable=Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
if(Test-Path -LiteralPath $machineExecutable){
    if(Test-Path -LiteralPath $userExecutable){throw 'Two Desktop installations detected. Reconcile before provisioning.'}
    Write-Output 'Existing machine Docker Desktop retained.'
    return
}
if(Test-Path -LiteralPath $userExecutable){Write-Output 'Per-user Docker Desktop is already installed.';return}
$arguments='install --user --quiet --accept-license --backend=wsl-2 --no-windows-containers'
if($InstallerPath){
    $installer=(Resolve-Path -LiteralPath $InstallerPath).Path
    # The offline installer is deliberately pinned and must be both authentic
    # and byte-for-byte equal to the official 4.97.0 WinGet release.
    $expected='2668273F82B342A058A28F9AB53EA7BDDDE10BB6D51307CE2EC54C2D36459744'
    if((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -ne $expected){throw 'Docker Desktop installer checksum mismatch'}
    $signature=Get-AuthenticodeSignature -LiteralPath $installer
    if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|, )CN=Docker Inc(,|$)'){throw 'Docker Desktop installer is not signed by Docker Inc'}
    $process=Start-Process -FilePath $installer -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
    if($process.ExitCode -notin @(0,3010)){throw "Docker Desktop installer failed ($($process.ExitCode))"}
}else{
    winget install --id Docker.DockerDesktop --exact --source winget --accept-source-agreements --accept-package-agreements --override $arguments
    if($LASTEXITCODE -notin @(0,3010)){throw "Docker Desktop installation failed ($LASTEXITCODE)"}
}
if(-not(Test-Path -LiteralPath $userExecutable)){throw 'Installer exited but the per-user Docker Desktop executable was not found'}
Write-Output "Docker Desktop installed: $userExecutable"
