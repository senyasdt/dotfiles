[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -eq 'Core'){
    & (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    if($LASTEXITCODE -ne 0){throw 'Windows dock icon preparation failed'}
    return
}
$destination=Join-Path $PSScriptRoot 'runtime\pinned-icons'
[void][IO.Directory]::CreateDirectory($destination)
$explorer=Join-Path $destination 'explorer.png'
$terminal=Join-Path $destination 'terminal.png'
if((Test-Path -LiteralPath $explorer) -and (Test-Path -LiteralPath $terminal)){return}
Add-Type -AssemblyName System.Drawing
if(-not ('AppIcons' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'AppIcons.cs') -ReferencedAssemblies System.Drawing}
if(!(Test-Path -LiteralPath $explorer)){
    if(![AppIcons]::Save((Join-Path $env:WINDIR 'explorer.exe'),$explorer)){throw 'Could not extract the Windows Explorer icon.'}
}
if(!(Test-Path -LiteralPath $terminal)){
    $catalog=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config\yasb\launchpad\apps.json'
    $entry=$null
    if(Test-Path -LiteralPath $catalog){$entry=@(Get-Content -LiteralPath $catalog -Raw|ConvertFrom-Json|Where-Object {$_.path -like '*Microsoft.WindowsTerminal_*' -and (Test-Path -LiteralPath $_.icon)}|Select-Object -First 1)}
    if($entry -and $entry.Count){Copy-Item -LiteralPath $entry[0].icon -Destination $terminal}
    elseif(![AppIcons]::Save((Join-Path $env:WINDIR 'System32\cmd.exe'),$terminal)){throw 'Could not extract a Windows terminal icon.'}
}
