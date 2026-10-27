param([ValidateSet('Build','Check','Start','Stop','Enable','Disable','Restart','Install','Uninstall','Status')][string]$Action='Status',[string]$Script='all')
$ErrorActionPreference='Stop'
$exe=Join-Path $PSScriptRoot 'ScriptLauncher.exe'
$shortcutPath=Join-Path ([Environment]::GetFolderPath('Startup')) 'AHK Script Launcher.lnk'
function Client([string[]]$Arguments) {
    $quoted=@($Arguments|ForEach-Object {'"'+$_+'"'}) -join ' '
    $process=Start-Process -FilePath $exe -ArgumentList $quoted -WindowStyle Hidden -PassThru
    if(-not $process.WaitForExit(12000)){throw 'Launcher command timed out.'}
    if($process.ExitCode -ne 0){throw ('Launcher command failed with code '+$process.ExitCode)}
}
if($Action -eq 'Stop' -or $Action -eq 'Build' -or $Action -eq 'Uninstall') {
    if(Get-Process -Name ScriptLauncher -ErrorAction SilentlyContinue){Client @('--stop'); Start-Sleep -Milliseconds 500}
}
if($Action -eq 'Build') {
    $deadline=[DateTime]::UtcNow.AddSeconds(4)
    while((Get-Process -Name ScriptLauncher -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
    if(Get-Process -Name ScriptLauncher -ErrorAction SilentlyContinue){throw 'Launcher did not stop.'}
    & (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 /r:System.Management.dll /r:System.Web.Extensions.dll ('/out:'+$exe) (Join-Path $PSScriptRoot 'ScriptLauncher.cs')
    if($LASTEXITCODE -ne 0){throw 'Build failed'}
}
if($Action -in @('Check','Install','Start','Enable','Disable','Restart')){Client @('--check')}
if($Action -eq 'Install') {
    $shell=New-Object -ComObject WScript.Shell
    if(Test-Path -LiteralPath $shortcutPath){$old=$shell.CreateShortcut($shortcutPath);if($old.TargetPath -ine $exe){throw 'Existing shortcut belongs to another program.'}}
    $shortcut=$shell.CreateShortcut($shortcutPath);$shortcut.TargetPath=$exe;$shortcut.WorkingDirectory=$PSScriptRoot;$shortcut.WindowStyle=7;$shortcut.Description='AHK scripts and per-program blocking rules';$shortcut.Save()
}
if($Action -in @('Install','Start','Enable','Disable','Restart')) {
    if(-not(Get-Process -Name ScriptLauncher -ErrorAction SilentlyContinue)){Start-Process -FilePath $exe -WorkingDirectory $PSScriptRoot -WindowStyle Hidden}
    if($Action -in @('Enable','Disable','Restart')){Client @('--'+$Action.ToLowerInvariant(),$Script)}
}
if($Action -eq 'Uninstall' -and (Test-Path -LiteralPath $shortcutPath)) {
    $shell=New-Object -ComObject WScript.Shell;$old=$shell.CreateShortcut($shortcutPath)
    if($old.TargetPath -ine $exe){throw 'Shortcut belongs to another program.'}
    Remove-Item -LiteralPath $shortcutPath
}
$status=Join-Path $PSScriptRoot 'runtime\status.json'
if($Action -eq 'Status' -and (Test-Path -LiteralPath $status)){Get-Content -LiteralPath $status -Raw -Encoding UTF8}
