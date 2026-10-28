[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [ValidateSet('Apply','Undo','Status')][string]$Action='Status',
    [string]$YasbRoot=(Join-Path $env:ProgramFiles 'YASB'),
    [string]$PythonPath
)
$ErrorActionPreference='Stop'
if(!$PythonPath){
    $candidates=@((Join-Path $env:LOCALAPPDATA 'Python\pythoncore-3.14-64\python.exe'),(Join-Path $env:LOCALAPPDATA 'Programs\Python\Python314\python.exe'))
    $PythonPath=$candidates|Where-Object {Test-Path -LiteralPath $_}|Select-Object -First 1
}
if(!$PythonPath -or !(Test-Path -LiteralPath $PythonPath)){throw 'Python 3.14 is required. Pass -PythonPath with its python.exe path.'}
$archive=Join-Path $YasbRoot 'lib\library.zip'
$exe=Join-Path $YasbRoot 'yasb.exe'
if(!(Test-Path -LiteralPath $archive) -or (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion -notmatch '^2\.0\.7(?:\D|$)'){throw 'Only the verified YASB 2.0.7 build is supported; nothing changed.'}
if($Action -ne 'Status'){
    if(@(Get-Process yasb -ErrorAction SilentlyContinue|Where-Object {$_.Path -ieq $exe}).Count){throw 'Close YASB before applying/removing its Launchpad patch. No process was stopped.'}
    $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if(!$admin -and $YasbRoot.StartsWith($env:ProgramFiles,[StringComparison]::OrdinalIgnoreCase)){throw 'Run this installer from an administrator PowerShell to modify Program Files.'}
}
if($Action -eq 'Status' -or $PSCmdlet.ShouldProcess($archive,($Action+' Launchpad manual order patch'))){
    & $PythonPath -X utf8 (Join-Path $PSScriptRoot 'patch_launchpad_order.py') $Action.ToLowerInvariant() --archive $archive
    if($LASTEXITCODE -ne 0){throw 'Launchpad patch failed; see diagnostic above'}
}
