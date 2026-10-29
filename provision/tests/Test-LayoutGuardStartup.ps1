$ErrorActionPreference='Stop'
$source=Split-Path (Split-Path $PSScriptRoot)
$root=Join-Path ([IO.Path]::GetTempPath()) ('layout-startup-check-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
foreach($name in @('Start.ps1','LayoutGuard.cs')){Copy-Item -LiteralPath (Join-Path $source ('dot_config\desktop-customization\keyboard-layout-guard\'+$name)) -Destination $root}
$exe=Join-Path $root 'TechnicalAltGrLayoutGuard.exe'
$global:LayoutGuardStartupFixture=@{Registered=0;Started=0;Running=$false;Foreign=$false}
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
function Get-ItemProperty($LiteralPath,$ErrorAction){
    if($global:LayoutGuardStartupFixture.Registered -eq 0){return $null}
    if($LiteralPath -like '*a0010409'){return [pscustomobject]@{'Layout File'='ENTECH.dll';'Layout Id'='a001'}}
    if($global:LayoutGuardStartupFixture.Registered -eq 1){return $null}
    [pscustomobject]@{'Layout File'=$(if($global:LayoutGuardStartupFixture.Registered -eq 3){'WRONG.dll'}else{'RUTECH.dll'});'Layout Id'='a002'}
}
function Get-Process($Name,$ErrorAction){
    if($global:LayoutGuardStartupFixture.Running){[pscustomobject]@{Path=$(if($global:LayoutGuardStartupFixture.Foreign){'C:\other\TechnicalAltGrLayoutGuard.exe'}else{$exe});SessionId=$session}}
}
function Start-Process($FilePath,$WorkingDirectory,$WindowStyle){
    if($FilePath -cne $exe -or $WindowStyle -ne 'Hidden'){throw 'Unexpected helper launch'}
    $global:LayoutGuardStartupFixture.Started++;$global:LayoutGuardStartupFixture.Running=$true
}
try{
foreach($state in @(0,1,3)){
    $global:LayoutGuardStartupFixture.Registered=$state
    & (Join-Path $root 'Start.ps1')|Out-Null
    if((Test-Path -LiteralPath $exe) -or $global:LayoutGuardStartupFixture.Started){throw 'Missing or changed custom registrations must not build or start cleanup'}
}
$global:LayoutGuardStartupFixture.Registered=2
& (Join-Path $root 'Start.ps1')|Out-Null
if(-not(Test-Path -LiteralPath $exe) -or $global:LayoutGuardStartupFixture.Started -ne 1){throw 'Fresh restore failed to build and start the helper automatically'}
& (Join-Path $root 'Start.ps1')|Out-Null
if($global:LayoutGuardStartupFixture.Started -ne 1){throw 'Repeated startup created a second helper'}
$global:LayoutGuardStartupFixture.Foreign=$true
$rejected=$false
try{& (Join-Path $root 'Start.ps1')|Out-Null}catch{$rejected=$true}
if(-not $rejected -or $global:LayoutGuardStartupFixture.Started -ne 1){throw 'Foreign helper ownership was not preserved'}
$template=Get-Content -LiteralPath (Join-Path $source 'dot_config\desktop-customization\desktop.json.tmpl') -Raw
if($template -notmatch '"startLayoutGuard": true'){throw 'Fresh desktop restore must enable safe layout auto-detection'}
Write-Host 'Layout startup checks passed: absent/partial/changed registrations, fresh binary-free restore, idempotency, foreign ownership and default enablement. No real helper or registry changes.'
}finally{Remove-Variable -Name LayoutGuardStartupFixture -Scope Global}
