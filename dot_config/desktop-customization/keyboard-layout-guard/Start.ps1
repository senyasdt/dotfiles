$ErrorActionPreference='Stop'
# Registration is machine-wide; ordinary desktops must retain their standard layouts.
foreach($layout in @(@{Id='a0010409';Dll='ENTECH.dll';LayoutId='a001'},@{Id='a0020419';Dll='RUTECH.dll';LayoutId='a002'})){
    $key=Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts\'+$layout.Id) -ErrorAction SilentlyContinue
    if(-not $key -or $key.'Layout File' -ine $layout.Dll -or $key.'Layout Id' -ine $layout.LayoutId){
        Write-Output 'Keyboard layout guard skipped: both approved Technical AltGr registrations are required.'
        return
    }
}
$executable=Join-Path $PSScriptRoot 'TechnicalAltGrLayoutGuard.exe'
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
function Get-SessionGuards { @(Get-Process -Name TechnicalAltGrLayoutGuard -ErrorAction SilentlyContinue | Where-Object {$_.SessionId -eq $session}) }
$running=@(Get-SessionGuards)
if(@($running|Where-Object {$_.Path -ine $executable}).Count){throw 'Keyboard layout guard is running from another folder; stop that copy explicitly before migrating.'}
if(-not(Test-Path -LiteralPath $executable)){
    # chezmoi intentionally excludes binaries. Rebuild on first login after restore.
    $pending=Join-Path $PSScriptRoot ('layout-guard-build-'+[Guid]::NewGuid().ToString('N')+'.exe')
    try{
        & (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /target:winexe /platform:x64 /optimize+ ('/out:'+$pending) (Join-Path $PSScriptRoot 'LayoutGuard.cs')
        if($LASTEXITCODE -ne 0){throw 'Keyboard layout guard first-login build failed.'}
        Move-Item -LiteralPath $pending -Destination $executable
    }finally{if(Test-Path -LiteralPath $pending){Remove-Item -LiteralPath $pending}}
}
if(-not $running.Count){
    Start-Process -FilePath $executable -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
    Start-Sleep -Milliseconds 300
}
if(-not @(Get-SessionGuards|Where-Object {$_.Path -ieq $executable}).Count){throw 'Keyboard layout guard did not remain running; check status.txt and events.log.'}
