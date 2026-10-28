$ErrorActionPreference='Stop'
$source=Split-Path (Split-Path $PSScriptRoot)
$support=Join-Path $source 'dot_config\desktop-customization\startup'
Import-Module (Join-Path $support 'Registry.psm1') -Force
$quoted=Split-StartupCommand '"C:\Program Files\Example\app.exe" --background'
if($quoted.FilePath -cne 'C:\Program Files\Example\app.exe' -or $quoted.Arguments -cne '--background'){throw 'Quoted startup command parsing failed'}
$unquoted=Split-StartupCommand 'C:\Program Files\Example\app.exe /mini'
if($unquoted.FilePath -cne $quoted.FilePath -or $unquoted.Arguments -cne '/mini'){throw 'Unquoted executable parsing failed'}
foreach($bad in @('app.exe --background','cmd /c app.exe','https://example.com')){
    $failed=$false;try{Split-StartupCommand $bad|Out-Null}catch{$failed=$true};if(-not $failed){throw 'Non-executable startup command accepted'}
}
$module=Get-Module Registry
& $module {
    $script:deleted=$false;$script:stored='original'
    function script:Invoke-CimMethod($Namespace,$ClassName,$MethodName,$Arguments){
        switch($MethodName){
            'EnumValues'{[pscustomobject]@{ReturnValue=0;sNames=@('Test');Types=@(1)}}
            'GetStringValue'{[pscustomobject]@{ReturnValue=0;sValue=$script:stored}}
            'DeleteValue'{$script:deleted=$true;[pscustomobject]@{ReturnValue=0}}
            'SetStringValue'{$script:stored=$Arguments.sValue;[pscustomobject]@{ReturnValue=0}}
            default{throw ('Unexpected test method: '+$MethodName)}
        }
    }
    $before=Read-StartupValue 'test-key' 'Test'
    $script:stored='changed elsewhere'
    $failed=$false;try{Remove-StartupValue $before}catch{$failed=$true}
    if(-not $failed -or $script:deleted){throw 'Concurrent registry edit was not protected'}
    Write-StartupValue $before
    if($script:stored -ne 'original'){throw 'Backup value could not be restored'}
    Remove-StartupValue $before
    if(-not $script:deleted){throw 'Exact planned registry value could not be removed'}
}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('deferred-startup-test-'+[Guid]::NewGuid().ToString('N'))
foreach($dir in @('startup','runtime')){[void][IO.Directory]::CreateDirectory((Join-Path $testRoot $dir))}
Copy-Item -LiteralPath (Join-Path $support 'Start-DeferredApp.ps1') -Destination (Join-Path $testRoot 'startup')
$entry=@(@{id='test';FilePath='C:\fixture-does-not-exist\app.exe';processName='app.exe';Arguments='';WorkingDirectory='C:\'})
[IO.File]::WriteAllText((Join-Path $testRoot 'runtime\deferred-apps.json'),(ConvertTo-Json -InputObject $entry))
function Get-CimInstance($ClassName,$Filter){[pscustomobject]@{SessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;ExecutablePath='C:\fixture-does-not-exist\app.exe'}}
& (Join-Path $testRoot 'startup\Start-DeferredApp.ps1') -Id test
# An owned running process must be reused even when its old launcher is absent.
function Get-CimInstance($ClassName,$Filter){[pscustomobject]@{SessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;ExecutablePath='C:\different-owner\app.exe'}}
$failed=$false;try{& (Join-Path $testRoot 'startup\Start-DeferredApp.ps1') -Id test}catch{$failed=$true}
if(-not $failed){throw 'A different process owner incorrectly suppressed a missing application'}
Write-Host 'Startup policy checks passed: command parsing, concurrent registry protection, restore and deferred-app ownership. No real process or registry entry was changed.'
