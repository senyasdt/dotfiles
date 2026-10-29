param([ValidateSet('Enable','Disable','Status')][string]$Action='Status')
$ErrorActionPreference='Stop'
$name='Druzh YASB App Sync'
$script=Join-Path $PSScriptRoot 'Sync-Apps.ps1'
$launcher=Join-Path $PSScriptRoot 'Sync-Apps-Hidden.vbs'
$existing=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
if($existing -and (@($existing.Actions).Count -ne 1 -or (!$existing.Actions[0].Arguments.Contains('"'+$script+'"') -and !$existing.Actions[0].Arguments.Contains('"'+$launcher+'"')))){throw 'Task name belongs to another launcher; left untouched'}
if($Action -eq 'Status'){
    if($existing){$existing | Select-Object TaskName,State;Get-ScheduledTaskInfo -TaskName $name}else{'Not installed'}
    return
}
if($Action -eq 'Disable'){
    if($existing){
        if($existing.State -eq 'Running'){
            Stop-ScheduledTask -TaskName $name -ErrorAction Stop
            $deadline=[DateTime]::UtcNow.AddSeconds(5)
            while((Get-ScheduledTask -TaskName $name -ErrorAction Stop).State -eq 'Running'){
                if([DateTime]::UtcNow -ge $deadline){throw 'Launchpad sync did not stop; catalog restore canceled'}
                Start-Sleep -Milliseconds 100
            }
        }
        Unregister-ScheduledTask -TaskName $name -Confirm:$false
    }
    return
}
if(!(Test-Path -LiteralPath $script)){throw 'Sync-Apps.ps1 missing'}
if(!(Test-Path -LiteralPath $launcher)){throw 'Sync-Apps-Hidden.vbs missing'}
$user=[Security.Principal.WindowsIdentity]::GetCurrent().Name
$exe=Join-Path $env:WINDIR 'System32\wscript.exe'
# A GUI host hides the console at creation; PowerShell -WindowStyle alone flashes
# Windows Terminal before the shell can hide itself. Wait and propagate its exit code.
$arguments='//B //Nologo "'+$launcher+'"'
$taskAction=New-ScheduledTaskAction -Execute $exe -Argument $arguments -WorkingDirectory $PSScriptRoot
$triggers=@((New-ScheduledTaskTrigger -AtLogOn -User $user),(New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)))
$principal=New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 3) -MultipleInstances IgnoreNew -StartWhenAvailable
Register-ScheduledTask -TaskName $name -Action $taskAction -Trigger $triggers -Principal $principal -Settings $settings -Description 'Update YASB app search at logon and every five minutes; preserve manual folders, order and removals.' -Force | Select-Object TaskName,State
