param([switch]$Check)
$ErrorActionPreference='Stop'
if($Check){[pscustomobject]@{Provider='Windows Applications folder';Target='shell:AppsFolder';RequiresAHK=$false;RequiresMyDockFinder=$false};return}
Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList 'shell:AppsFolder'
