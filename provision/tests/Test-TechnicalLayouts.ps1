$ErrorActionPreference='Stop'
$source=Split-Path (Split-Path $PSScriptRoot)
$bundle=Join-Path $source 'provision\windows\keyboard-layouts'
Import-Module (Join-Path $bundle 'Support.psm1') -Force -DisableNameChecking
$manifest=Get-LayoutBundle $bundle
$assertions=0
function Check($Condition,$Message){if(-not $Condition){throw $Message};$script:assertions++}
$initial=@([pscustomobject]@{LanguageTag='en-US';InputMethodTips=@('0409:00000409');Handwriting=$true;Spellchecking=$true},[pscustomobject]@{LanguageTag='de-DE';InputMethodTips=@('0407:00000407');Handwriting=$false;Spellchecking=$false})
$desired=Get-TechnicalLanguagePlan $initial
Check ($desired.Count -eq 3) 'Fresh profile must receive both custom layouts without removing German'
Check ($desired[0].LanguageTag -eq 'en-US' -and $desired[1].LanguageTag -eq 'de-DE' -and $desired[2].LanguageTag -eq 'ru-RU') 'Existing language order must be preserved'
Check ($desired[0].InputMethodTips.Count -eq 1 -and $desired[0].InputMethodTips[0] -eq '0409:A0010409') 'US standard input tip must become the approved custom layout'
Check ($desired[0].Handwriting -and $desired[1].InputMethodTips[0] -eq '0407:00000407') 'Unrelated language settings changed'
Check (-not $desired[1].Spellchecking -and $desired[0].Spellchecking) 'Existing per-language spellchecking preference changed'
$restored=New-TechnicalLanguageList $initial
Check (-not $restored[1].Spellchecking -and $restored[0].Handwriting -and $restored[1].InputMethodTips[0] -eq '0407:00000407') 'Rollback reconstruction reset writable scalar properties or input tips'
Check ($initial[0].InputMethodTips[0] -eq '0409:00000409') 'Planner mutated the input snapshot'
Check (Same-LayoutData $desired (Get-TechnicalLanguagePlan $desired)) 'Language merge is not idempotent'
$ru=@([pscustomobject]@{LanguageTag='ru';InputMethodTips=@('0419:00000419','0419:00010419');Handwriting=$false})
$ruDesired=Get-TechnicalLanguagePlan $ru
Check ($ruDesired.Count -eq 2 -and $ruDesired[0].LanguageTag -eq 'ru') 'Existing neutral Russian tag must be reused'
Check ($ruDesired[0].InputMethodTips -contains '0419:00010419' -and $ruDesired[0].InputMethodTips -contains '0419:A0020419' -and $ruDesired[0].InputMethodTips -notcontains '0419:00000419') 'Unrelated Russian layout was not preserved'
Check (Get-LayoutFileChange $null 'new' 'legacy' 'x64') 'Missing DLL must be installed'
Check (-not (Get-LayoutFileChange 'new' 'new' 'legacy' 'wow64')) 'Matching DLL must remain untouched'
Check (Get-LayoutFileChange 'legacy' 'new' 'legacy' 'wow64') 'Known wrong-architecture WOW64 copy must be repairable'
foreach($arch in @('x64','wow64')){$rejected=$false;try{Get-LayoutFileChange 'foreign' 'new' 'legacy' $arch|Out-Null}catch{$rejected=$true};Check $rejected 'Foreign DLL must not be replaced'}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('technical-layout-check-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
Copy-Item -Path (Join-Path $bundle '*') -Destination $fixture -Recurse
$tampered=Join-Path $fixture 'wow64\ENTECH.dll'
$bytes=[IO.File]::ReadAllBytes($tampered);$bytes[200]=$bytes[200] -bxor 1;[IO.File]::WriteAllBytes($tampered,$bytes)
$rejected=$false;try{Get-LayoutBundle $fixture|Out-Null}catch{$rejected=$true};Check $rejected 'Tampered DLL was accepted'
# Mock only the registry adapter; exercise real rollback ordering and conflict checks.
& (Get-Module Support) {
    $script:fixtureRegistry=@{'a0010409/Layout File'='ENTECH.dll';'a0010409/Layout Id'='a001'}
    function script:Read-LayoutMachineValue($Klid,$Name){$script:fixtureRegistry[$Klid+'/'+$Name]}
    function script:Write-LayoutMachineValue($Klid,$Name,$Value){$script:fixtureRegistry[$Klid+'/'+$Name]=$Value}
    $state=[pscustomobject]@{Files=@();Writes=@([pscustomobject]@{Klid='a0010409';Name='Layout File';Before=$null;After='ENTECH.dll'},[pscustomobject]@{Klid='a0010409';Name='Layout Id';Before=$null;After='a001'})}
    $script:fixtureRegistry['a0010409/Layout Id']='changed'
    $rejected=$false;try{Restore-LayoutMachine $state 'unused'}catch{$rejected=$true}
    if(-not $rejected -or $script:fixtureRegistry['a0010409/Layout File'] -ne 'ENTECH.dll'){throw 'Rollback changed data before rejecting concurrent modification'}
    $script:fixtureRegistry['a0010409/Layout Id']='a001'
    Restore-LayoutMachine $state 'unused'
    if($null -ne $script:fixtureRegistry['a0010409/Layout File'] -or $null -ne $script:fixtureRegistry['a0010409/Layout Id']){throw 'Rollback failed to restore the original absent values'}
    Restore-LayoutMachine ([pscustomobject]@{Files=@();Writes=@()}) 'unused'
}
Remove-Module Support
Write-Host ('PASS: '+$assertions+' keyboard bundle/language/file policy checks plus rollback conflict/order/empty-state checks. No real language, system file or registry changes.')
