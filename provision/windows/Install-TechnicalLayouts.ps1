param(
    [ValidateSet('Plan','Apply','Machine','Rollback')][string]$Action='Plan',
    [string]$Root=(Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config\desktop-customization'),
    [string]$BackupDirectory
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess){throw 'Run this installer through 64-bit Windows PowerShell 5.1.'}
$bundle=Join-Path $PSScriptRoot 'keyboard-layouts'
Import-Module (Join-Path $bundle 'Support.psm1') -Force -DisableNameChecking
$manifest=Get-LayoutBundle $bundle
$rootPath=[IO.Path]::GetFullPath($Root)
$isAdmin=(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Save($path,$data){[IO.File]::WriteAllText($path,($data|ConvertTo-Json -Depth 15),(New-Object Text.UTF8Encoding($false)))}
function New-Backup($kind){$p=Join-Path $rootPath ('backup\technical-layouts-'+$kind+'-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($p);return $p}
function Elevate($operation,$backup){
    $ps=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    # Windows paths cannot contain quotes; no shell is involved in argument parsing.
    foreach($path in @($PSCommandPath,$rootPath,$backup)){if($path -and $path.Contains('"')){throw 'Invalid path.'}}
    $arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Action '+$operation+' -Root "'+$rootPath+'"'
    if($backup){$arguments+=' -BackupDirectory "'+$backup+'"'}
    $process=Start-Process -FilePath $ps -Verb RunAs -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
    $process.Refresh();if($process.ExitCode -ne 0){throw ('Elevated keyboard installation failed: '+$process.ExitCode)}
}
if($Action -eq 'Rollback'){
    if(-not $BackupDirectory){throw 'Pass the exact backup directory.'}
    $state=Get-Content -LiteralPath (Join-Path $BackupDirectory 'snapshot.json') -Raw|ConvertFrom-Json
    if($state.Root -ine $rootPath){throw 'Backup belongs to another desktop installation.'}
    if($state.Kind -eq 'machine'){
        if(-not $isAdmin){Elevate 'Rollback' $BackupDirectory;return}
        Restore-LayoutMachine $state $BackupDirectory
    }elseif($state.Kind -eq 'user'){
        if($state.UserSid -ne $sid){throw 'User backup belongs to a different account.'}
        $list=Read-TechnicalLanguages
        $current=@($list|ForEach-Object {[pscustomobject]@{LanguageTag=$_.LanguageTag;InputMethodTips=@($_.InputMethodTips);Handwriting=[bool]$_.Handwriting;Spellchecking=[bool]$_.Spellchecking}})
        if(-not (Same-LayoutData $current $state.After)){throw 'Languages changed after installation; rollback refused.'}
        # Recreate the exact original list, including languages added by the installer.
        $list=New-TechnicalLanguageList $state.Before
        Set-WinUserLanguageList -LanguageList $list -Force
    }else{throw 'Unrecognized backup kind.'}
    Write-Output 'Technical AltGr backup restored. Sign out and in to refresh loaded layouts.'
    return
}
$machine=Get-LayoutMachinePlan $manifest $bundle
if($Action -eq 'Machine'){
    if(-not $isAdmin){throw 'Machine layout installation requires Windows administrator consent.'}
    if(-not ($machine.Writes.Count+$machine.Files.Count)){Write-Output 'Machine layouts already match.';return}
    $backup=New-Backup 'machine'
    $state=[pscustomobject]@{Kind='machine';Root=$rootPath;Writes=$machine.Writes;Files=$machine.Files}
    foreach($file in $state.Files){if($file.Before){Copy-Item -LiteralPath $file.Target -Destination (Join-Path $backup $file.Backup)}}
    Save (Join-Path $backup 'snapshot.json') $state
    try{
        foreach($file in $state.Files){$now=if(Test-Path -LiteralPath $file.Target){(Get-FileHash $file.Target).Hash}else{$null};if($now -ine $file.Before){throw 'DLL changed during installation.'};Copy-Item -LiteralPath $file.Source -Destination $file.Target -Force;if((Get-FileHash $file.Target).Hash -ine $file.After){throw 'Installed DLL checksum mismatch.'}}
        foreach($write in $state.Writes){if((Read-LayoutMachineValue $write.Klid $write.Name) -ine $write.Before){throw 'Registration changed during installation.'};Write-LayoutMachineValue $write.Klid $write.Name $write.After}
        $check=Get-LayoutMachinePlan $manifest $bundle;if($check.Files.Count+$check.Writes.Count){throw 'Machine layout verification failed.'}
    }catch{Restore-LayoutMachine $state $backup;throw}
    Write-Output ('Machine keyboard installation verified. Backup: '+$backup)
    return
}
$languages=Read-TechnicalLanguages
$before=@($languages|ForEach-Object {[pscustomobject]@{LanguageTag=$_.LanguageTag;InputMethodTips=@($_.InputMethodTips);Handwriting=[bool]$_.Handwriting;Spellchecking=[bool]$_.Spellchecking}})
$desired=Get-TechnicalLanguagePlan $before
$userChanged=-not (Same-LayoutData $before $desired)
if($Action -eq 'Plan'){
    [pscustomobject]@{MachineRegistryChanges=$machine.Writes.Count;MachineFileChanges=$machine.Files.Count;RequiresAdministrator=([bool]($machine.Writes.Count+$machine.Files.Count));UserLanguageChanges=$userChanged;Languages=$desired;SignOutAfterChanges=([bool]($userChanged -or $machine.Writes.Count -or $machine.Files.Count))}|ConvertTo-Json -Depth 10
    return
}
if($machine.Writes.Count+$machine.Files.Count){if($isAdmin){& $PSCommandPath -Action Machine -Root $rootPath}else{Elevate 'Machine' $null}}
$check=Get-LayoutMachinePlan $manifest $bundle;if($check.Files.Count+$check.Writes.Count){throw 'Machine layouts remain incomplete; user profile left unchanged.'}
if($userChanged){
    # Re-read before writing so a concurrent language edit is never overwritten.
    $current=Read-TechnicalLanguages
    $now=@($current|ForEach-Object {[pscustomobject]@{LanguageTag=$_.LanguageTag;InputMethodTips=@($_.InputMethodTips);Handwriting=[bool]$_.Handwriting;Spellchecking=[bool]$_.Spellchecking}})
    if(-not (Same-LayoutData $now $before)){throw 'Languages changed during installation; rerun the plan.'}
    $backup=New-Backup 'user'
    $saved=@($current|ForEach-Object {[pscustomobject]@{LanguageTag=$_.LanguageTag;InputMethodTips=@($_.InputMethodTips);Handwriting=[bool]$_.Handwriting;Spellchecking=[bool]$_.Spellchecking}})
    Save (Join-Path $backup 'snapshot.json') ([pscustomobject]@{Kind='user';Root=$rootPath;UserSid=$sid;Before=$saved;After=$desired})
    Set-TechnicalLanguages $desired
    $list=Read-TechnicalLanguages
    $after=@($list|ForEach-Object {[pscustomobject]@{LanguageTag=$_.LanguageTag;InputMethodTips=@($_.InputMethodTips);Handwriting=[bool]$_.Handwriting;Spellchecking=[bool]$_.Spellchecking}})
    if(-not (Same-LayoutData $after $desired)){throw ('Language verification failed; saved profile: '+$backup)}
    Write-Output ('User keyboard configuration verified. Backup: '+$backup)
}
Write-Output 'Technical AltGr ready. Sign out and in after a new installation; existing application windows were not restarted.'
