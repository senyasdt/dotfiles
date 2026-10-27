param([ValidateSet('Build','Install','Start','Stop','Uninstall','Status')][string]$Action='Status')
$ErrorActionPreference='Stop'
$exe=Join-Path $PSScriptRoot 'FinderWidgets.exe'
$shortcutPath=Join-Path ([Environment]::GetFolderPath('Startup')) 'Finder Widgets.lnk'
if($Action -eq 'Stop' -or $Action -eq 'Build' -or $Action -eq 'Uninstall') {
    if(Test-Path -LiteralPath $exe) {
        $stopper=Start-Process -FilePath $exe -ArgumentList '--stop' -WindowStyle Hidden -PassThru
        $stopper.WaitForExit()
        $deadline=[DateTime]::UtcNow.AddSeconds(6)
        do { $processes=@(Get-Process -Name FinderWidgets -ErrorAction SilentlyContinue | Where-Object Path -EQ $exe); if(-not $processes.Count){break}; Start-Sleep -Milliseconds 200 } while([DateTime]::UtcNow -lt $deadline)
        if($processes.Count){throw 'Widget process did not stop; executable left unchanged.'}
    }
}
if($Action -eq 'Build') {
    & (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll /r:System.Management.dll ('/out:'+$exe) (Join-Path $PSScriptRoot 'FinderWidgets.cs')
    if($LASTEXITCODE -ne 0){throw 'Widget build failed'}
}
if($Action -eq 'Install') {
    $shell=New-Object -ComObject WScript.Shell
    if(Test-Path -LiteralPath $shortcutPath){$old=$shell.CreateShortcut($shortcutPath); if($old.TargetPath -ine $exe){throw 'Shortcut belongs to another application'}}
    $shortcut=$shell.CreateShortcut($shortcutPath); $shortcut.TargetPath=$exe; $shortcut.WorkingDirectory=$PSScriptRoot; $shortcut.WindowStyle=7; $shortcut.Description='Personal widgets in the MyFinder system tray'; $shortcut.Save()
}
if($Action -eq 'Install' -or $Action -eq 'Start') { Start-Process -FilePath $exe -WorkingDirectory $PSScriptRoot -WindowStyle Hidden }
if($Action -eq 'Uninstall' -and (Test-Path -LiteralPath $shortcutPath)) {
    $shell=New-Object -ComObject WScript.Shell; $shortcut=$shell.CreateShortcut($shortcutPath)
    if($shortcut.TargetPath -ine $exe){throw 'Shortcut belongs to another application'}
    Remove-Item -LiteralPath $shortcutPath
}
Get-Process -Name FinderWidgets -ErrorAction SilentlyContinue | Select-Object Id,Path,WorkingSet64
