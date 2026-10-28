#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param([switch]$Notify)
$ErrorActionPreference='Stop'
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
$helper=Join-Path $env:LOCALAPPDATA 'Programs\vial-helper\vial-helperd.exe'
$candidates=@((Join-Path $env:LOCALAPPDATA 'Programs\Vial-0.7.5-portable\Vial\Vial.exe'),(Join-Path $env:LOCALAPPDATA 'Programs\Vial\Vial.exe'),(Join-Path $env:ProgramFiles 'Vial\Vial.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Vial\Vial.exe'),(Join-Path $env:LOCALAPPDATA 'Vial\Vial.exe'))
$editor=@($candidates|Where-Object {Test-Path -LiteralPath $_}|Select-Object -First 1)
if(!$editor.Count){throw 'Vial.exe was not found. Install Vial before opening its editor.'}
if(!$PSCmdlet.ShouldProcess('Vial editor and its HID helper','Open editor, restore helper only if it was running')){return}
$gate=New-Object Threading.Mutex($false,'Local\Druzh.VialSafeOpen')
$lifecycle=New-Object Threading.Mutex($false,'Local\Druzh.DesktopServices')
$locked=$false;$lifeLocked=$false;$resume=$false
function Helpers {
    $all=@(Get-Process vial-helperd -ErrorAction SilentlyContinue|Where-Object SessionId -EQ $session)
    if(@($all|Where-Object {$_.Path -ine $helper}).Count){throw 'Another Vial helper owner is running; left untouched.'}
    return @($all|Where-Object {$_.Path -ieq $helper})
}
function Lock-Lifecycle {
    try{$script:lifeLocked=$lifecycle.WaitOne(5000)}catch [Threading.AbandonedMutexException]{$script:lifeLocked=$true}
    if(!$script:lifeLocked){throw 'Another desktop helper operation is still running.'}
}
try {
    try{$locked=$gate.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(!$locked){throw 'A safe Vial editor session is already open.'}
    if(Get-Process Vial -ErrorAction SilentlyContinue|Where-Object SessionId -EQ $session){throw 'Vial is already open.'}
    Lock-Lifecycle
    $running=@(Helpers);$resume=$running.Count -gt 0
    foreach($p in $running){$p.Kill();if(!$p.WaitForExit(3000)){throw 'Vial HID helper did not stop.'}}
    $lifecycle.ReleaseMutex();$lifeLocked=$false
    $process=Start-Process -FilePath $editor[0] -WorkingDirectory (Split-Path $editor[0]) -PassThru
    $process.WaitForExit();$process.Dispose()
} catch {
    if($Notify){Add-Type -AssemblyName System.Windows.Forms;[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Open Vial safely','OK','Warning')}
    throw
} finally {
    try {
        if($resume -and !(Get-Process Vial -ErrorAction SilentlyContinue|Where-Object SessionId -EQ $session)){
            if(!$lifeLocked){Lock-Lifecycle}
            if(!(Helpers).Count){Start-Process -FilePath $helper -ArgumentList '--command run' -WorkingDirectory (Split-Path $helper) -WindowStyle Hidden}
            $folder=Join-Path $env:APPDATA 'vial-helper';[void][IO.Directory]::CreateDirectory($folder)
            [IO.File]::WriteAllText((Join-Path $folder 'refresh-layout.flag'),'')
        }
    }finally{if($lifeLocked){$lifecycle.ReleaseMutex()};$lifecycle.Dispose();if($locked){$gate.ReleaseMutex()};$gate.Dispose()}
}
