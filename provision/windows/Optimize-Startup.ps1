param(
    [ValidateSet('Plan','Apply','Rollback','Status')][string]$Action='Plan',
    [string]$Root=(Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config\desktop-customization'),
    [string]$UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value,
    [string]$BackupDirectory
)
$ErrorActionPreference='Stop'
$rootPath=[IO.Path]::GetFullPath($Root)
$support=Join-Path $rootPath 'startup'
Import-Module (Join-Path $support 'Registry.psm1') -Force
$policy=Get-Content -LiteralPath (Join-Path $support 'policy.json') -Raw|ConvertFrom-Json
$runtime=Join-Path $rootPath 'runtime'
$profile=(Get-CimInstance Win32_UserProfile -Filter ("SID='"+$UserSid+"'")).LocalPath
if(-not $profile){throw 'Target user profile is not loaded'}
$startup=Join-Path $profile 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
$runKey=$UserSid+'\Software\Microsoft\Windows\CurrentVersion\Run'
$appKey=$UserSid+'\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'
$utf8=New-Object Text.UTF8Encoding($false)
function Save($path,$data){[IO.File]::WriteAllText($path,($data|ConvertTo-Json -Depth 20),$utf8)}
function Same($a,$b){($a|ConvertTo-Json -Compress -Depth 10) -ceq ($b|ConvertTo-Json -Compress -Depth 10)}
function Require-Admin {
    if(-not (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Apply/Rollback requires Windows administrator consent for the existing scheduled tasks. Plan makes no changes.'}
}
function Register-ManagedTask($task){
    $action=New-ScheduledTaskAction -Execute $task.Execute -Argument $task.Arguments -WorkingDirectory $rootPath
    $trigger=New-ScheduledTaskTrigger -AtLogOn -User $UserSid
    $trigger.Delay='PT'+[int]$task.DelaySeconds+'S'
    $principal=New-ScheduledTaskPrincipal -UserId $UserSid -LogonType Interactive -RunLevel Limited
    $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 3)
    Register-ScheduledTask -TaskName $task.Name -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description ('Managed dotfiles startup: '+$rootPath) -Force|Out-Null
}
if($Action -eq 'Status'){
    $marker=Join-Path $runtime 'startup-policy.json'
    if(-not (Test-Path -LiteralPath $marker)){[pscustomobject]@{Installed=$false;Root=$rootPath}|ConvertTo-Json;return}
    $state=Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json
    $snapshot=Get-Content -LiteralPath (Join-Path $state.backup 'snapshot.json') -Raw|ConvertFrom-Json
    $drift=@($snapshot.Registry|Where-Object {-not (Same (Read-StartupValue $_.Before.Key $_.Before.Name) $_.After)}|ForEach-Object {$_.Before.Name+' ('+$_.Reason+')'})
    $tasks=@(foreach($entry in $snapshot.NewTasks){$task=Get-ScheduledTask -TaskName $entry.Name -ErrorAction SilentlyContinue;[pscustomobject]@{Name=$entry.Name;Enabled=$task.Settings.Enabled;State=[string]$task.State;Delay=($task.Triggers.Delay -join ',');LastResult=(Get-ScheduledTaskInfo -TaskName $entry.Name -ErrorAction SilentlyContinue).LastTaskResult}})
    [pscustomobject]@{Installed=$true;AppliedAt=$state.appliedAt;Backup=$state.backup;PolicyChanged=((Get-FileHash -LiteralPath (Join-Path $support 'policy.json')).Hash -ne $state.policy);RegistryDrift=$drift;Tasks=$tasks}|ConvertTo-Json -Depth 6;return
}
if($Action -eq 'Rollback'){
    Require-Admin
    if(-not $BackupDirectory){throw 'Specify the exact backup directory'}
    $saved=Get-Content -LiteralPath (Join-Path $BackupDirectory 'snapshot.json') -Raw|ConvertFrom-Json
    if($saved.Root -ine $rootPath -or $saved.UserSid -ne $UserSid){throw 'Backup belongs to a different installation'}
    # Check every owner before removing any replacement task.
    foreach($task in $saved.NewTasks){$now=Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue;if($now -and (@($now.Actions).Count -ne 1 -or $now.Actions[0].Execute -ine $task.Execute -or $now.Actions[0].Arguments -cne $task.Arguments)){throw ('Task changed; rollback left intact: '+$task.Name)}}
    foreach($entry in $saved.Registry){$now=Read-StartupValue $entry.Before.Key $entry.Before.Name;if(-not (Same $now $entry.Before) -and -not (Same $now $entry.After)){throw ('Registry value changed; rollback left intact: '+$entry.Before.Name)}}
    foreach($file in $saved.Files){if((Test-Path -LiteralPath $file.Original) -and (Get-FileHash -LiteralPath $file.Original).Hash -ne $file.Hash){throw ('Startup file changed; rollback left intact: '+$file.Original)}}
    foreach($task in @($saved.LegacyTasks)+@($saved.DelayedLegacyTasks)){
        $now=Get-ScheduledTask -TaskName $task.Name -TaskPath $task.Path -ErrorAction SilentlyContinue
        [xml]$oldXml=[IO.File]::ReadAllText((Join-Path $BackupDirectory $task.Backup))
        if($now -and (@($now.Actions).Count -ne 1 -or $now.Actions[0].Execute -ine [string]$oldXml.Task.Actions.Exec.Command -or [string]$now.Actions[0].Arguments -cne [string]$oldXml.Task.Actions.Exec.Arguments)){throw ('Legacy task owner changed; rollback left intact: '+$task.Name)}
    }
    foreach($task in $saved.NewTasks){
        $now=Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue
        if($now){if(@($now.Actions).Count -ne 1 -or $now.Actions[0].Execute -ine $task.Execute -or $now.Actions[0].Arguments -cne $task.Arguments){throw ('Task changed; left intact: '+$task.Name)};Unregister-ScheduledTask -TaskName $task.Name -Confirm:$false}
    }
    foreach($entry in $saved.Registry){
        $now=Read-StartupValue $entry.Before.Key $entry.Before.Name
        if(Same $now $entry.Before){continue}
        if(-not (Same $now $entry.After)){throw ('Registry value changed; left intact: '+$entry.Before.Name)}
        Write-StartupValue $entry.Before
    }
    foreach($file in $saved.Files){
        if(Test-Path -LiteralPath $file.Original){if((Get-FileHash -LiteralPath $file.Original).Hash -eq $file.Hash){continue};throw ('Startup file re-created; left intact: '+$file.Original)}
        Copy-Item -LiteralPath (Join-Path $BackupDirectory $file.Backup) -Destination $file.Original
    }
    foreach($task in $saved.LegacyTasks){Register-ScheduledTask -TaskName $task.Name -TaskPath $task.Path -Xml ([IO.File]::ReadAllText((Join-Path $BackupDirectory $task.Backup))) -Force|Out-Null}
    foreach($task in $saved.DelayedLegacyTasks){Register-ScheduledTask -TaskName $task.Name -TaskPath $task.Path -Xml ([IO.File]::ReadAllText((Join-Path $BackupDirectory $task.Backup))) -Force|Out-Null}
    if($saved.DesktopSettings){
        $current=Get-Content -LiteralPath (Join-Path $rootPath 'desktop.json') -Raw|ConvertFrom-Json
        $old=Get-Content -LiteralPath (Join-Path $BackupDirectory 'desktop.json') -Raw|ConvertFrom-Json
        if($old.PSObject.Properties['startHidHelpers']){$current|Add-Member -NotePropertyName startHidHelpers -NotePropertyValue $old.startHidHelpers -Force}
        else{$current.PSObject.Properties.Remove('startHidHelpers')}
        Save (Join-Path $rootPath 'desktop.json') $current
    }
    Remove-Item -LiteralPath (Join-Path $runtime 'startup-policy.json') -ErrorAction SilentlyContinue
    if($saved.PSObject.Properties['DiagnosticsEnabledBefore'] -and -not $saved.DiagnosticsEnabledBefore){& (Join-Path $env:WINDIR 'System32\wevtutil.exe') sl 'Microsoft-Windows-Diagnostics-Performance/Operational' /e:false}
    Write-Output ('Startup restored from '+$BackupDirectory);return
}
$registry=@();$deferred=@();$missing=@()
$enum=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName EnumValues -Arguments @{hDefKey=[uint32]2147483651;sSubKeyName=$runKey}
foreach($name in $enum.sNames){
    $disabled=$policy.disableRunNames -contains $name
    foreach($prefix in $policy.disableRunPrefixes){if($name.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){$disabled=$true}}
    if($disabled){$registry+=[pscustomobject]@{Before=(Read-StartupValue $runKey $name);After=$null;Reason='Manual launch'}}
}
foreach($app in $policy.deferred){
    if($app.runName){
        $entry=Read-StartupValue $runKey $app.runName
        if(-not $entry){$missing+=$app.id;continue}
        $command=Split-StartupCommand $entry.Value
        if([IO.Path]::GetFileName($command.FilePath) -ine $app.exeName){throw ('Unexpected deferred executable for '+$app.id)}
        if(-not (Test-Path -LiteralPath $command.FilePath)){$missing+=($app.id+' (missing executable)');continue}
        $deferred+=[pscustomobject]@{id=$app.id;FilePath=$command.FilePath;Arguments=$command.Arguments;WorkingDirectory=$command.WorkingDirectory;processName=[IO.Path]::GetFileName($command.FilePath);delaySeconds=$app.delaySeconds}
        $registry+=[pscustomobject]@{Before=$entry;After=$null;Reason='Deferred '+$app.delaySeconds+' seconds'}
    }else{
        $entry=Read-StartupValue ($appKey+'\'+$app.packageFamily+'\'+$app.taskId) 'State'
        if(-not $entry){$missing+=$app.id;continue}
        $after=[pscustomobject]@{Key=$entry.Key;Name='State';Type=4;Value=[uint32]1}
        $registry+=[pscustomobject]@{Before=$entry;After=$after;Reason='Deferred '+$app.delaySeconds+' seconds'}
        $deferred+=[pscustomobject]@{id=$app.id;FilePath=(Join-Path $env:WINDIR 'explorer.exe');Arguments=('shell:AppsFolder\'+$app.packageFamily+'!'+$app.appId);WorkingDirectory=$profile;processName=$app.processName;packageFamily=$app.packageFamily;delaySeconds=$app.delaySeconds}
    }
}
foreach($app in $policy.disablePackaged){
    $entry=Read-StartupValue ($appKey+'\'+$app.family+'\'+$app.taskId) 'State'
    if($entry -and [int]$entry.Value -eq 2){$registry+=[pscustomobject]@{Before=$entry;After=[pscustomobject]@{Key=$entry.Key;Name='State';Type=4;Value=[uint32]1};Reason='Manual launch'}}
}
$legacy=@()
foreach($rule in $policy.legacyTasks){
    $task=Get-ScheduledTask -TaskName $rule.name -TaskPath $rule.path -ErrorAction SilentlyContinue
    if(-not $task -or $task.State -eq 'Disabled'){continue}
    $actions=@($task.Actions)
    if($actions.Count -ne 1){throw ('Unknown legacy task owner: '+$rule.name)}
    if($rule.executeSuffix -and -not $actions[0].Execute.Trim('"').EndsWith($rule.executeSuffix,[StringComparison]::OrdinalIgnoreCase)){throw ('Unknown task executable: '+$rule.name)}
    if($rule.argumentsContains -and $actions[0].Arguments -notlike ('*'+$rule.argumentsContains+'*')){throw ('Unknown task arguments: '+$rule.name)}
    $legacy+=[pscustomobject]@{Name=$task.TaskName;Path=$task.TaskPath;Backup=('tasks\'+$task.TaskName+'.xml');StopOnApply=$rule.stopOnApply}
}
$files=@()
$delayedLegacy=@()
foreach($rule in $policy.delayLegacyTasks){
    $task=Get-ScheduledTask -TaskName $rule.name -TaskPath $rule.path -ErrorAction SilentlyContinue
    if(-not $task -or $task.State -eq 'Disabled'){continue}
    if(@($task.Actions).Count -ne 1 -or -not $task.Actions[0].Execute.Trim('"').EndsWith($rule.executeSuffix,[StringComparison]::OrdinalIgnoreCase)){throw ('Unknown deferred task owner: '+$rule.name)}
    $delayedLegacy+=[pscustomobject]@{Name=$task.TaskName;Path=$task.TaskPath;Backup=('tasks\'+$task.TaskName+'.xml');DelaySeconds=$rule.delaySeconds}
}
foreach($name in $policy.removeStartupFiles){$path=Join-Path $startup $name;if(Test-Path -LiteralPath $path){$files+=[pscustomobject]@{Original=$path;Backup=('Startup\'+$name);Hash=(Get-FileHash -LiteralPath $path).Hash}}}
$powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$newTasks=@([pscustomobject]@{Name='Druzh Desktop Session';Execute=$powershell;Arguments=('-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $rootPath 'Start-Session.ps1')+'"');DelaySeconds=[int]$policy.desktopDelaySeconds})
foreach($app in $deferred){$newTasks+=[pscustomobject]@{Name=('Druzh Deferred '+$app.id);Execute=$powershell;Arguments=('-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $support 'Start-DeferredApp.ps1')+'" -Id '+$app.id);DelaySeconds=[int]$app.delaySeconds}}
foreach($task in $newTasks){if(Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue){throw ('Managed task already exists; inspect current policy or roll it back first: '+$task.Name)}}
$plan=[pscustomobject]@{Root=$rootPath;UserSid=$UserSid;Registry=$registry;Deferred=$deferred;LegacyTasks=$legacy;DelayedLegacyTasks=$delayedLegacy;Files=$files;NewTasks=$newTasks;MissingOptionalApps=$missing;DesktopSettings=(Test-Path -LiteralPath (Join-Path $rootPath 'desktop.json'))}
if($Action -eq 'Plan'){$plan|ConvertTo-Json -Depth 12;return}
Require-Admin
try{$diagnosticLog=Get-WinEvent -ListLog 'Microsoft-Windows-Diagnostics-Performance/Operational';$plan|Add-Member -NotePropertyName DiagnosticsEnabledBefore -NotePropertyValue $diagnosticLog.IsEnabled}catch{$diagnosticLog=$null}
if(-not $BackupDirectory){$BackupDirectory=Join-Path $rootPath ('backup\startup-policy-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))}
if(Test-Path -LiteralPath $BackupDirectory){throw 'Backup directory already exists'}
foreach($dir in @($BackupDirectory,(Join-Path $BackupDirectory 'tasks'),(Join-Path $BackupDirectory 'Startup'),$runtime)){[void][IO.Directory]::CreateDirectory($dir)}
Save (Join-Path $BackupDirectory 'snapshot.json') $plan
foreach($task in @($legacy)+@($delayedLegacy)){[IO.File]::WriteAllText((Join-Path $BackupDirectory $task.Backup),(Export-ScheduledTask -TaskName $task.Name -TaskPath $task.Path),$utf8)}
foreach($file in $files){Copy-Item -LiteralPath $file.Original -Destination (Join-Path $BackupDirectory $file.Backup)}
if($plan.DesktopSettings){Copy-Item -LiteralPath (Join-Path $rootPath 'desktop.json') -Destination (Join-Path $BackupDirectory 'desktop.json')}
# Register replacements before removing existing startup owners.
try{
Save (Join-Path $runtime 'deferred-apps.json') @($deferred)
foreach($task in $newTasks){Register-ManagedTask $task}
$settings=Get-Content -LiteralPath (Join-Path $rootPath 'desktop.json') -Raw|ConvertFrom-Json
$settings|Add-Member -NotePropertyName startHidHelpers -NotePropertyValue $true -Force
Save (Join-Path $rootPath 'desktop.json') $settings
foreach($entry in $registry){Remove-StartupValue $entry.Before;if($entry.After){Write-StartupValue $entry.After}}
foreach($task in $legacy){Disable-ScheduledTask -TaskName $task.Name -TaskPath $task.Path|Out-Null;if($task.StopOnApply){Stop-ScheduledTask -TaskName $task.Name -TaskPath $task.Path -ErrorAction SilentlyContinue}}
foreach($task in $delayedLegacy){
    [xml]$xml=[IO.File]::ReadAllText((Join-Path $BackupDirectory $task.Backup))
    $ns=New-Object Xml.XmlNamespaceManager($xml.NameTable);$ns.AddNamespace('t',$xml.DocumentElement.NamespaceURI)
    foreach($trigger in $xml.SelectNodes('//t:LogonTrigger',$ns)){
        $delay=$trigger.SelectSingleNode('t:Delay',$ns)
        if(-not $delay){$delay=$xml.CreateElement('Delay',$xml.DocumentElement.NamespaceURI);[void]$trigger.AppendChild($delay)}
        $delay.InnerText='PT'+[int]$task.DelaySeconds+'S'
    }
    Register-ScheduledTask -TaskName $task.Name -TaskPath $task.Path -Xml $xml.OuterXml -Force|Out-Null
}
foreach($file in $files){if((Get-FileHash -LiteralPath $file.Original).Hash -ne $file.Hash){throw ('Startup file changed; left intact: '+$file.Original)};Remove-Item -LiteralPath $file.Original}
if($diagnosticLog -and -not $diagnosticLog.IsEnabled){& (Join-Path $env:WINDIR 'System32\wevtutil.exe') sl 'Microsoft-Windows-Diagnostics-Performance/Operational' /e:true;if($LASTEXITCODE -ne 0){throw 'Could not enable boot timing log'}}
Save (Join-Path $runtime 'startup-policy.json') @{backup=$BackupDirectory;appliedAt=(Get-Date -Format o);policy=(Get-FileHash -LiteralPath (Join-Path $support 'policy.json')).Hash}
Write-Output ('Startup policy applied. Backup: '+$BackupDirectory)
}catch{
    $failure=$_
    try{& $PSCommandPath -Action Rollback -Root $rootPath -UserSid $UserSid -BackupDirectory $BackupDirectory|Out-Null}
    catch{throw ('Startup apply failed: '+$failure.Exception.Message+'. Automatic rollback also stopped: '+$_.Exception.Message+'. Backup: '+$BackupDirectory)}
    throw $failure
}
