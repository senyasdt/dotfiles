[CmdletBinding(SupportsShouldProcess=$true)]
param([ValidateSet('Smooth','Instant')][string]$Mode='Smooth')
$ErrorActionPreference='Stop'
$command=Get-Command komorebic.exe -ErrorAction SilentlyContinue
$client=if($command){$command.Source}else{Join-Path ([Environment]::GetFolderPath('UserProfile')) 'scoop\apps\komorebi\current\komorebic.exe'}
if(-not(Test-Path -LiteralPath $client)){throw 'komorebic.exe was not found.'}
function Invoke-Client([string[]]$Arguments) {
    & $client @Arguments | Out-Null
    if($LASTEXITCODE -ne 0){throw ('komorebic failed: '+($Arguments -join ' '))}
}
if(-not $PSCmdlet.ShouldProcess('Current komorebi session; movement on ALL workspaces',"Set $Mode movement")){return}
if($Mode -eq 'Instant'){
    Invoke-Client @('animation','disable','-a','movement')
}else{
    try {
        Invoke-Client @('animation-duration','160','-a','movement')
        Invoke-Client @('animation-style','--style','ease-out-cubic','-a','movement')
        Invoke-Client @('animation-fps','60')
        Invoke-Client @('animation','enable','-a','movement')
    }catch{
        # Avoid leaving an enabled, partially configured animation after a CLI error.
        Invoke-Client @('animation','disable','-a','movement')
        throw
    }
}
Write-Output "Movement: $Mode. Runtime only, global across workspaces; komorebi.json unchanged."
