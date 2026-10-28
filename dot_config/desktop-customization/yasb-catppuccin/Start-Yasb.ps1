param([switch]$CheckOnly)
$ErrorActionPreference='Stop'

# Keep the IPC location and CLI lookup independent of the caller's environment.
# In particular, a redirected LOCALAPPDATA produces a different komorebi socket.
$profileRoot=[Environment]::GetFolderPath('UserProfile')
$localRoot=[Environment]::GetFolderPath('LocalApplicationData')
$yasb=Join-Path $env:ProgramFiles 'YASB\yasb.exe'
$cliRoot=Join-Path $profileRoot 'scoop\apps\komorebi\current'
$komorebic=Join-Path $cliRoot 'komorebic.exe'
if(!(Test-Path -LiteralPath $yasb)){throw 'YASB is not installed'}

# The saved WM choice is shared with Manage/Use-WindowManager. A LeopardWM
# session has no komorebi socket, and YASB must not require its CLI or IPC.
$selectionPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'leopardwm-test\runtime\selection.json'
$useKomorebi=$true
if(Test-Path -LiteralPath $selectionPath){
    $selection=Get-Content -LiteralPath $selectionPath -Raw|ConvertFrom-Json
    if($selection.enabled -is [bool] -and $selection.enabled){$useKomorebi=$false}
}

function New-LaunchInfo($file){
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$file
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    $info.WorkingDirectory=Split-Path $file
    $info.EnvironmentVariables['LOCALAPPDATA']=$localRoot
    $info.EnvironmentVariables['USERPROFILE']=$profileRoot
    $info.EnvironmentVariables['PATH']=$cliRoot+';'+(Join-Path $profileRoot 'scoop\shims')+';'+$env:PATH
    return $info
}

# Check before Manage stops a working bar. Normalized paths cannot remove
# socket restrictions inherited from an isolated parent process (WSAENETDOWN).
if($useKomorebi){
if(!(Test-Path -LiteralPath $komorebic)){throw 'The managed Scoop komorebic is not installed'}
$info=New-LaunchInfo $komorebic
$info.Arguments='query focused-workspace-index'
$info.RedirectStandardOutput=$true
$info.RedirectStandardError=$true
$probe=New-Object Diagnostics.Process
$probe.StartInfo=$info
try{
    [void]$probe.Start()
    $out=$probe.StandardOutput.ReadToEndAsync()
    $err=$probe.StandardError.ReadToEndAsync()
    if(!$probe.WaitForExit(3000)){
        $probe.Kill()
        throw 'komorebic launch check timed out; the existing YASB was left running'
    }
    $message=$err.GetAwaiter().GetResult()
    [void]$out.GetAwaiter().GetResult()
    if($probe.ExitCode -ne 0 -and $message -notmatch '\(os error 10061\)'){
        throw 'komorebic IPC is unavailable in this launch context. Run the desktop launcher from the normal Windows session; an agent must use an approved unrestricted tool call. The existing YASB was left running.'
    }
    # 10061 is expected when komorebi is stopped. YASB will subscribe when it
    # comes back; there is no need to wait for WM or restart the panel again.
}finally{$probe.Dispose()}
}
if($CheckOnly){return}

$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
if(@(Get-Process yasb -ErrorAction SilentlyContinue|Where-Object {$_.SessionId -eq $session -and $_.Path -ieq $yasb}).Count){return}
$info=New-LaunchInfo $yasb
$process=[Diagnostics.Process]::Start($info)
$process.Dispose()
