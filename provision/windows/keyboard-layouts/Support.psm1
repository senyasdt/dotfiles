$ErrorActionPreference='Stop'
$script:LayoutRegistry='SYSTEM\CurrentControlSet\Control\Keyboard Layouts'
function Same-LayoutData($a,$b){($a|ConvertTo-Json -Compress -Depth 10) -ceq ($b|ConvertTo-Json -Compress -Depth 10)}
function Get-TechnicalLanguagePlan($Languages){
    $result=@(foreach($language in $Languages){[pscustomobject]@{LanguageTag=[string]$language.LanguageTag;InputMethodTips=@($language.InputMethodTips);Handwriting=[bool]$language.Handwriting;Spellchecking=[bool]$language.Spellchecking}})
    foreach($rule in @(@{Tag='en-US';Tip='0409:A0010409';Standard='0409:00000409'},@{Tag='ru-RU';Tip='0419:A0020419';Standard='0419:00000419'})){
        $existing=@($result|Where-Object {$_.LanguageTag -ieq $rule.Tag -or ($rule.Tag -eq 'ru-RU' -and $_.LanguageTag -ieq 'ru')})
        if(-not $existing.Count){$item=[pscustomobject]@{LanguageTag=$rule.Tag;InputMethodTips=@();Handwriting=$false;Spellchecking=$true};$result+=$item;$existing=@($item)}
        foreach($item in $existing){$item.InputMethodTips=@($item.InputMethodTips|Where-Object {$_ -ine $rule.Standard});if($item.InputMethodTips -inotcontains $rule.Tip){$item.InputMethodTips+= $rule.Tip}}
    }
    return ,$result
}
function Read-TechnicalLanguages {
    $list=Get-WinUserLanguageList
    if(-not $list.Count){throw 'Windows returned an empty user language list.'}
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    # Read the real profile through WMI, including when invoked by a packaged app.
    $real=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName GetMultiStringValue -Arguments @{hDefKey=[uint32]2147483651;sSubKeyName=($sid+'\Control Panel\International\User Profile');sValueName='Languages'}
    if($real.ReturnValue -ne 0 -or -not (Same-LayoutData @($list|ForEach-Object LanguageTag) @($real.sValue))){throw 'Language API and real user hive disagree. Run restore in ordinary Windows PowerShell as the desktop owner.'}
    return ,$list
}
function Set-TechnicalLanguages($Desired){
    $list=Read-TechnicalLanguages
    foreach($record in $Desired){
        $item=@($list|Where-Object LanguageTag -IEQ $record.LanguageTag)
        if(-not $item.Count){$list.Add((New-WinUserLanguageList -Language $record.LanguageTag)[0]);$item=@($list[$list.Count-1])}
        $item[0].InputMethodTips.Clear();foreach($tip in $record.InputMethodTips){$item[0].InputMethodTips.Add([string]$tip)}
    }
    # Preserve all other language settings and display-language preferences.
    Set-WinUserLanguageList -LanguageList $list -Force
}
function New-TechnicalLanguageList($Records){
    if(-not $Records.Count){throw 'A language backup cannot be empty.'}
    $list=New-WinUserLanguageList -Language $Records[0].LanguageTag;$list.Clear()
    foreach($record in $Records){
        $item=(New-WinUserLanguageList -Language $record.LanguageTag)[0]
        $item.InputMethodTips.Clear();foreach($tip in $record.InputMethodTips){$item.InputMethodTips.Add([string]$tip)}
        $item.Handwriting=[bool]$record.Handwriting;$item.Spellchecking=[bool]$record.Spellchecking;$list.Add($item)
    }
    return ,$list
}
function Read-LayoutMachineValue($Klid,$Name){
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine','Registry64')
    try{$key=$base.OpenSubKey($script:LayoutRegistry+'\'+$Klid);if(-not $key){return $null};try{$value=$key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames);if($null -ne $value -and $key.GetValueKind($Name) -ne 'String'){throw 'Unexpected registry value type.'};return $value}finally{$key.Dispose()}}finally{$base.Dispose()}
}
function Write-LayoutMachineValue($Klid,$Name,$Value){
    if($Klid -notin @('a0010409','a0020419') -or $Name -notin @('Layout File','Layout Id','Layout Text')){throw 'Registry write outside the approved layouts.'}
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine','Registry64')
    try{$key=$base.CreateSubKey($script:LayoutRegistry+'\'+$Klid);try{if($null -eq $Value){$key.DeleteValue($Name,$false)}else{$key.SetValue($Name,[string]$Value,'String')}}finally{$key.Dispose()}}finally{$base.Dispose()}
}
function Get-LayoutBundle([string]$Bundle){
    $manifest=Get-Content -LiteralPath (Join-Path $Bundle 'manifest.json') -Raw|ConvertFrom-Json
    if($manifest.version -ne 1 -or $manifest.layouts.Count -ne 2){throw 'Invalid keyboard bundle manifest.'}
    $seen=@()
    foreach($layout in $manifest.layouts){
        $expected=switch($layout.klid){'a0010409'{@('a001','ENTECH.dll','source/en-technical-altgr.klc')};'a0020419'{@('a002','RUTECH.dll','source/ru-technical-altgr.klc')};default{throw 'Unexpected custom layout ID.'}}
        if($layout.klid -in $seen -or $layout.layoutId -cne $expected[0] -or $layout.dll -cne $expected[1] -or $layout.source -cne $expected[2]){throw 'Unexpected custom layout identity.'};$seen+=$layout.klid
        if((Get-FileHash -LiteralPath (Join-Path $Bundle $layout.source)).Hash -ine $layout.sourceSha256){throw 'KLC source checksum mismatch.'}
        if($layout.files.Count -ne 2){throw 'Both x64 and WOW64 DLLs are required.'}
        $arches=@()
        foreach($file in $layout.files){
            $machine=switch($file.architecture){'x64'{34404};'wow64'{332};default{throw 'Unsupported DLL architecture.'}}
            if($file.architecture -in $arches -or $file.path -cne ($file.architecture+'/'+$layout.dll) -or $file.machine -ne $machine){throw 'Invalid DLL manifest path or architecture.'};$arches+=$file.architecture
            $path=Join-Path $Bundle $file.path
            if((Get-FileHash -LiteralPath $path).Hash -ine $file.sha256){throw 'DLL checksum mismatch.'}
            $bytes=[IO.File]::ReadAllBytes($path);$pe=[BitConverter]::ToInt32($bytes,60)
            if($bytes.Length -lt 256 -or $pe -lt 64 -or $pe+6 -gt $bytes.Length -or [BitConverter]::ToUInt32($bytes,$pe) -ne 17744 -or [BitConverter]::ToUInt16($bytes,$pe+4) -ne $machine){throw 'DLL PE architecture mismatch.'}
        }
    }
    return $manifest
}
function Get-LayoutMachinePlan($Manifest,[string]$Bundle){
    if(-not [Environment]::Is64BitProcess -or [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE','Machine') -ne 'AMD64'){throw 'Technical AltGr bundle supports x64 Windows with 64-bit Windows PowerShell only.'}
    $writes=@();$files=@()
    # Layout Id participates in the HKL handle; fail on a collision elsewhere.
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine','Registry64')
    try{$all=$base.OpenSubKey($script:LayoutRegistry);try{foreach($id in $all.GetSubKeyNames()){$k=$all.OpenSubKey($id);try{$lid=$k.GetValue('Layout Id',$null);foreach($layout in $Manifest.layouts){if($lid -ieq $layout.layoutId -and $id -ine $layout.klid){throw ('Layout Id collision: '+$id)}}}finally{$k.Dispose()}}}finally{$all.Dispose()}}finally{$base.Dispose()}
    foreach($layout in $Manifest.layouts){
        foreach($pair in @(@('Layout File',$layout.dll),@('Layout Id',$layout.layoutId),@('Layout Text',$layout.name))){
            $before=Read-LayoutMachineValue $layout.klid $pair[0]
            if($null -ne $before -and $before -ine $pair[1]){throw ('Existing custom registration differs: '+$layout.klid+'/'+$pair[0])}
            if($null -eq $before){$writes+=[pscustomobject]@{Klid=$layout.klid;Name=$pair[0];Before=$null;After=$pair[1]}}
        }
        foreach($file in $layout.files){
            $folder=if($file.architecture -eq 'x64'){'System32'}else{'SysWOW64'}
            $target=Join-Path $env:WINDIR ($folder+'\'+$layout.dll)
            $before=if(Test-Path -LiteralPath $target){(Get-FileHash -LiteralPath $target).Hash}else{$null}
            $legacy=@($layout.files|Where-Object architecture -EQ 'x64')[0].sha256
            $change=Get-LayoutFileChange $before $file.sha256 $legacy $file.architecture
            if($change){$files+=[pscustomobject]@{Source=(Join-Path $Bundle $file.path);Target=$target;Before=$before;After=$file.sha256;Backup=($file.architecture+'-'+$layout.dll)}}
        }
    }
    [pscustomobject]@{Writes=$writes;Files=$files}
}
function Get-LayoutFileChange($Before,$Expected,$Legacy,$Architecture){
    if($Before -ieq $Expected){return $false}
    if($Before -and -not ($Architecture -eq 'wow64' -and $Before -ieq $Legacy)){throw 'Different existing DLL left intact.'}
    return $true
}
function Restore-LayoutMachine($State,[string]$BackupDirectory){
    # Preflight every change before reverting any of them.
    $allowedTargets=@(foreach($folder in @('System32','SysWOW64')){foreach($name in @('ENTECH.dll','RUTECH.dll')){Join-Path $env:WINDIR ($folder+'\'+$name)}})
    foreach($file in $State.Files){
        if($allowedTargets -inotcontains $file.Target -or $file.Backup -notmatch '^(x64|wow64)-(ENTECH|RUTECH)\.dll$'){throw 'Unrecognized backup target.'}
        $now=if(Test-Path -LiteralPath $file.Target){(Get-FileHash $file.Target).Hash}else{$null}
        if($now -ine $file.Before -and $now -ine $file.After){throw 'DLL changed since installation; rollback refused.'}
        if($file.Before -and (Get-FileHash (Join-Path $BackupDirectory $file.Backup)).Hash -ine $file.Before){throw 'Backup checksum mismatch.'}
    }
    foreach($write in $State.Writes){if($write.Klid -notin @('a0010409','a0020419') -or $write.Name -notin @('Layout File','Layout Id','Layout Text')){throw 'Unrecognized backup registration.'};$now=Read-LayoutMachineValue $write.Klid $write.Name;if($now -ine $write.Before -and $now -ine $write.After){throw 'Registration changed since installation; rollback refused.'}}
    if($State.Writes.Count){foreach($write in @($State.Writes)[($State.Writes.Count-1)..0]){Write-LayoutMachineValue $write.Klid $write.Name $write.Before}}
    foreach($file in $State.Files){if($file.Before){Copy-Item -LiteralPath (Join-Path $BackupDirectory $file.Backup) -Destination $file.Target -Force}elseif(Test-Path -LiteralPath $file.Target){Remove-Item -LiteralPath $file.Target}}
}
Export-ModuleMember -Function *
