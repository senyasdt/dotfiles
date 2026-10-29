param([string]$Destination=(Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config\yasb\launchpad'),[switch]$Refresh)
$ErrorActionPreference='Stop'
# Refresh remains compatible; import now merges without resetting custom layout.
& (Join-Path $PSScriptRoot 'Sync-Apps.ps1') -Destination $Destination