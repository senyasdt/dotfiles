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
        $duration=90
        $profile=Join-Path $PSScriptRoot 'runtime\motion-profile.json'
        if(Test-Path -LiteralPath $profile){$duration=[int]((Get-Content -LiteralPath $profile -Raw|ConvertFrom-Json).duration)}
        if($duration -notin @(90,160)){throw 'Unexpected movement duration in motion profile.'}
        Invoke-Client @('animation-duration',[string]$duration,'-a','movement')
        Invoke-Client @('animation-style','--style','ease-out-sine','-a','movement')
        Invoke-Client @('animation-fps','60')
        Invoke-Client @('animation','enable','-a','movement')
    }catch{
        # Avoid leaving an enabled, partially configured animation after a CLI error.
        Invoke-Client @('animation','disable','-a','movement')
        throw
    }
}
Write-Output "Movement: $Mode. Runtime only, global across workspaces; komorebi.json unchanged."
