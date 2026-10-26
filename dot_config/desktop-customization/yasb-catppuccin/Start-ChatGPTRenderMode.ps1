[CmdletBinding(SupportsShouldProcess=$true)]
param([ValidateSet('Default','Software')][string]$Mode='Software',[switch]$Inspect)
$ErrorActionPreference='Stop'
function Get-ChatGPTLaunchPlan([object[]]$Packages,[object[]]$Processes,[int]$SessionId,[string]$Mode) {
    $supported=@($Packages|Where-Object {
        ($_.Name -eq 'OpenAI.Codex' -and $_.PackageFamilyName -eq 'OpenAI.Codex_2p2nqsd0c76g0') -or
        ($_.Name -eq 'OpenAI.ChatGPT-Desktop' -and $_.PackageFamilyName -eq 'OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0')
    })
    if($supported.Count -ne 1){throw 'Не удалось однозначно выбрать установленный ChatGPT из Microsoft Store.'}
    $running=@($Processes|Where-Object {$_.Name -ieq 'ChatGPT.exe' -and $_.SessionId -eq $SessionId})
    [pscustomobject]@{Mode=$Mode;Executable=(Join-Path $supported[0].InstallLocation 'app\ChatGPT.exe');Arguments=if($Mode -eq 'Software'){'--disable-gpu'}else{''};CanStart=($running.Count -eq 0);RunningPids=@($running|ForEach-Object ProcessId)}
}
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
function Plan {
    Get-ChatGPTLaunchPlan @(Get-AppxPackage|Where-Object Name -in @('OpenAI.Codex','OpenAI.ChatGPT-Desktop')) @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'") $session $Mode
}
$plan=Plan
if($Inspect){return $plan}
if(!$plan.CanStart){throw 'ChatGPT уже открыт. Сначала закрой приложение через его меню выхода, затем выбери этот запуск ещё раз. Текущий чат не закрывался.'}
if(!(Test-Path -LiteralPath $plan.Executable)){throw 'Исполняемый файл ChatGPT не найден.'}
if(!$PSCmdlet.ShouldProcess(('ChatGPT: '+$Mode),'Запустить приложение; без изменения постоянных GPU-настроек')){return}
$mutex=New-Object Threading.Mutex($false,'Local\Druzh.ChatGPTLaunchMode');$locked=$false
try {
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(!$locked){throw 'Другой запуск ChatGPT ещё выполняется.'}
    $fresh=Plan
    if(!$fresh.CanStart -or $fresh.Executable -ine $plan.Executable){throw 'Состояние ChatGPT изменилось; запуск отменён.'}
    $start=@{FilePath=$fresh.Executable;WorkingDirectory=(Split-Path $fresh.Executable);PassThru=$true}
    if($fresh.Arguments){$start.ArgumentList=$fresh.Arguments}
    $p=Start-Process @start
    try {
        if($p.WaitForExit(800)){throw ('ChatGPT завершился при запуске; код '+$p.ExitCode)}
        [pscustomobject]@{Status='Started';Mode=$Mode;ProcessId=$p.Id;PersistentSettingsChanged=$false}
    } finally {$p.Dispose()}
} finally {if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
