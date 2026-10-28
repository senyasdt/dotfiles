param([Parameter(Mandatory=$true)][string]$ConfigText,
    [Parameter(Mandatory=$true)][AllowEmptyString()][string]$HotkeyText)
# Compare the managed flat TOML hotkey section with the daemon's IPC response.
# A healthy process/status alone can still mean it silently loaded defaults.
$section=[regex]::Match($ConfigText,'(?ms)^\[hotkeys\][^\r\n]*\r?\n(.*?)(?=^\[|\z)').Groups[1].Value
$scroll=[regex]::Match($section,'(?m)^\s*scroll_modifier\s*=\s*"([^"]+)"').Groups[1].Value
if(-not $scroll){throw 'Managed LeopardWM config must declare scroll_modifier.'}
if($HotkeyText -notmatch ('(?m)^\s*Scroll modifier:\s*'+[regex]::Escape($scroll)+'\s*$')){return $false}
foreach($binding in [regex]::Matches($section,'(?m)^\s*"([^"]+)"\s*=\s*"[^"]+"')){
    if($HotkeyText -notmatch ('(?m):\s*'+[regex]::Escape($binding.Groups[1].Value)+'\s*$')){return $false}
}
return $true
