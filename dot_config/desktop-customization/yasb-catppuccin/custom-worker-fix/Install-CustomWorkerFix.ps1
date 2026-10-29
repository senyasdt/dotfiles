[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [ValidateSet('Apply','Undo','Status')][string]$Action='Status',
    [string]$YasbRoot=(Join-Path $env:ProgramFiles 'YASB'),
    [string]$PythonPath
)
$ErrorActionPreference='Stop'
if(!$PythonPath){
    $PythonPath=@((Join-Path $env:LOCALAPPDATA 'Python\pythoncore-3.14-64\python.exe'),(Join-Path $env:LOCALAPPDATA 'Programs\Python\Python314\python.exe')) | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
}
if(!$PythonPath -or !(Test-Path -LiteralPath $PythonPath)){throw 'Pass -PythonPath with a Python 3.14 python.exe path.'}
$exe=Join-Path $YasbRoot 'yasb.exe'
$archive=Join-Path $YasbRoot 'lib\library.zip'
if(!(Test-Path -LiteralPath $archive) -or !(Test-Path -LiteralPath $exe) -or (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion -notmatch '^2\.0\.7(?:\D|$)'){throw 'Only verified YASB 2.0.7 is supported; nothing changed.'}
if($Action -ne 'Status'){
    $running=@(Get-CimInstance Win32_Process -Filter "Name='yasb.exe'" -ErrorAction Stop)
    if(@($running | Where-Object { !$_.ExecutablePath -or $_.ExecutablePath -ieq $exe }).Count){throw 'Close YASB before applying/removing this patch. No process was stopped.'}
    $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if(!$admin -and $YasbRoot.StartsWith($env:ProgramFiles,[StringComparison]::OrdinalIgnoreCase)){throw 'Administrator PowerShell is required to modify Program Files.'}
}
if($Action -eq 'Status' -or $PSCmdlet.ShouldProcess($archive,($Action+' experimental custom worker lifecycle fix'))){
    & $PythonPath -X utf8 (Join-Path $PSScriptRoot 'patch_custom_worker.py') $Action.ToLowerInvariant() --archive $archive
    if($LASTEXITCODE -ne 0){throw 'Worker patch failed; see diagnostics above.'}
}
