[CmdletBinding(SupportsShouldProcess=$true)]
param([switch]$Inspect)
$ErrorActionPreference='Stop'

function Split-ChatGPTCommandLine([string]$CommandLine) {
    if([string]::IsNullOrWhiteSpace($CommandLine)){return @()}
    if(!('Druzh.ChatGPTRendering.Arguments' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Druzh.ChatGPTRendering {
    public static class Arguments {
        [DllImport("shell32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
        static extern IntPtr CommandLineToArgvW(string commandLine,out int count);
        [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);
        public static string[] Split(string commandLine){
            int count;var memory=CommandLineToArgvW(commandLine,out count);
            if(memory==IntPtr.Zero)throw new InvalidOperationException("Cannot parse process command line.");
            try{var result=new string[count];for(int i=0;i<count;i++)result[i]=Marshal.PtrToStringUni(Marshal.ReadIntPtr(memory,i*IntPtr.Size));return result;}
            finally{LocalFree(memory);}
        }
    }
}
'@
    }
    return [Druzh.ChatGPTRendering.Arguments]::Split($CommandLine)
}

function Get-ChatGPTWindowSnapshot {
    @(Get-Process -Name ChatGPT -ErrorAction SilentlyContinue|Where-Object {$_.MainWindowHandle -ne [IntPtr]::Zero}|ForEach-Object {
        [pscustomobject]@{Id=$_.Id;Path=$_.Path;SessionId=$_.SessionId;Window=[int64]$_.MainWindowHandle;StartedUtc=$_.StartTime.ToUniversalTime()}
    })
}

function Get-ChatGPTRenderPlan([object[]]$Windows,[object[]]$Processes,[int]$SessionId,[string]$WindowsAppsRoot) {
    $knownPath='^'+[regex]::Escape($WindowsAppsRoot.TrimEnd('\'))+'\\OpenAI\.(?:Codex|ChatGPT-Desktop)_[^\\]+__2p2nqsd0c76g0\\app\\ChatGPT\.exe$'
    $parents=@($Windows|Where-Object {$_.Id -gt 0 -and $_.SessionId -eq $SessionId -and $_.Window -ne 0 -and $_.Path -match $knownPath})
    if($parents.Count -eq 0){throw 'Открытое окно ChatGPT из поддерживаемой установки Microsoft Store не найдено.'}
    if($parents.Count -ne 1){throw 'Найдено несколько основных процессов ChatGPT. Не удалось однозначно выбрать окно.'}
    $parent=$parents[0]
    $children=@($Processes|Where-Object {
        if($_.ProcessId -le 0 -or $_.ProcessId -eq $parent.Id -or $_.ParentProcessId -ne $parent.Id -or
           $_.SessionId -ne $SessionId -or $_.Name -ine 'ChatGPT.exe' -or $_.ExecutablePath -ine $parent.Path){return $false}
        $types=@(Split-ChatGPTCommandLine $_.CommandLine|Where-Object {$_ -clike '--type=*'})
        return $types.Count -eq 1 -and $types[0] -ceq '--type=gpu-process'
    })
    if($children.Count -eq 0){throw 'Графический подпроцесс ChatGPT не найден. Если приложение запускается, повторите команду немного позже.'}
    if($children.Count -ne 1){throw 'Найдено несколько графических подпроцессов. Завершение отменено.'}
    $child=$children[0]
    if(!$child.CreationDate -or !$parent.StartedUtc){throw 'Не удалось проверить время запуска процессов ChatGPT.'}
    [pscustomobject]@{ParentId=[int]$parent.Id;ParentStartedUtc=[datetime]$parent.StartedUtc;Window=[int64]$parent.Window;Executable=[string]$parent.Path;SessionId=$SessionId;GpuId=[int]$child.ProcessId;GpuStartedUtc=([datetime]$child.CreationDate).ToUniversalTime()}
}

function Test-ChatGPTRenderIdentity($Before,$After) {
    return $Before.ParentId -eq $After.ParentId -and $Before.ParentStartedUtc -eq $After.ParentStartedUtc -and
        $Before.Window -eq $After.Window -and $Before.Executable -ieq $After.Executable -and
        $Before.SessionId -eq $After.SessionId -and $Before.GpuId -eq $After.GpuId -and
        $Before.GpuStartedUtc -eq $After.GpuStartedUtc
}

function Write-ChatGPTRenderEvent([string]$Phase,$Snapshot,$Failure=$null) {
    try {
        $runtime=Join-Path $PSScriptRoot 'runtime';[void][IO.Directory]::CreateDirectory($runtime)
        $log=Join-Path $runtime 'chatgpt-render.jsonl'
        if((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -ge 131072){Copy-Item -LiteralPath $log -Destination ($log+'.1') -Force;[IO.File]::WriteAllText($log,'')}
        $entry=[ordered]@{at=[DateTimeOffset]::Now.ToString('o');operation='manual-gpu-reset';phase=$Phase}
        if($Snapshot){$entry.parentId=$Snapshot.ParentId;$entry.gpuId=$Snapshot.GpuId;$entry.window=$Snapshot.Window}
        if($Failure){$entry.errorType=$Failure.GetType().FullName;$entry.hresult=$Failure.HResult}
        [IO.File]::AppendAllText($log,($entry|ConvertTo-Json -Compress)+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    } catch {} # Diagnostic recording must not block recovery.
}

$sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId
$windowsAppsRoot=Join-Path $env:ProgramFiles 'WindowsApps'
$plan=Get-ChatGPTRenderPlan (Get-ChatGPTWindowSnapshot) @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'") $sessionId $windowsAppsRoot
if($Inspect){return $plan}
if(!$PSCmdlet.ShouldProcess(('ChatGPT GPU PID '+$plan.GpuId),'Пересоздать графический подпроцесс, сохранив основной процесс')){return}
$mutex=New-Object Threading.Mutex($false,'Local\Druzh.ChatGPTRendering');$locked=$false;$gpuProcess=$null;$mainProcess=$null
try {
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(!$locked){throw 'Восстановление отрисовки ChatGPT уже выполняется.'}
    $fresh=Get-ChatGPTRenderPlan (Get-ChatGPTWindowSnapshot) @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'") $sessionId $windowsAppsRoot
    if(!(Test-ChatGPTRenderIdentity $plan $fresh)){throw 'Процессы ChatGPT изменились после проверки. Ничего не завершено; повторите команду.'}
    $mainProcess=Get-Process -Id $fresh.ParentId -ErrorAction Stop
    $gpuProcess=Get-Process -Id $fresh.GpuId -ErrorAction Stop
    if($gpuProcess.Id -eq $mainProcess.Id -or $gpuProcess.ProcessName -ine 'ChatGPT' -or
       $gpuProcess.Path -ine $fresh.Executable -or $gpuProcess.SessionId -ne $sessionId -or
       [Math]::Abs(($gpuProcess.StartTime.ToUniversalTime()-$fresh.GpuStartedUtc).TotalMilliseconds) -gt 1){
        throw 'Графический процесс изменился перед завершением. Операция отменена.'
    }
    # This is the only termination site: the unique, revalidated GPU child.
    Write-ChatGPTRenderEvent 'begin' $fresh
    $gpuProcess.Kill()
    if(!$gpuProcess.WaitForExit(3000)){throw 'Графический подпроцесс не завершился за 3 секунды.'}
    $deadline=[DateTime]::UtcNow.AddSeconds(8);$replacement=$null
    do {
        Start-Sleep -Milliseconds 250
        $mainProcess.Refresh()
        if($mainProcess.HasExited){throw 'Основной процесс ChatGPT завершился во время восстановления.'}
        try {
            $next=Get-ChatGPTRenderPlan (Get-ChatGPTWindowSnapshot) @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'") $sessionId $windowsAppsRoot
            if($next.ParentId -eq $fresh.ParentId -and $next.ParentStartedUtc -eq $fresh.ParentStartedUtc -and
               $next.Window -eq $fresh.Window -and $next.GpuId -ne $fresh.GpuId){$replacement=$next}
        }catch{$replacement=$null}
    }while(!$replacement -and [DateTime]::UtcNow -lt $deadline)
    if(!$replacement){throw 'Графический процесс не восстановился за 8 секунд. Основной процесс принудительно не закрывался.'}
    Write-ChatGPTRenderEvent 'recovered' $replacement
    [pscustomobject]@{Status='Recovered';ParentId=$fresh.ParentId;PreviousGpuId=$fresh.GpuId;NewGpuId=$replacement.GpuId;MainWindowPreserved=$true}
}catch {
    Write-ChatGPTRenderEvent 'failed' $plan $_.Exception
    throw
}finally {
    if($gpuProcess){$gpuProcess.Dispose()};if($mainProcess){$mainProcess.Dispose()}
    if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()
}
