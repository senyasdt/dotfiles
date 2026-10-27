#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook true
if A_Args.Length && A_Args[1] = "--check"
    ExitApp
; Alt+F12 is registered by YASB itself. Other F-key assignments are untouched.
; Only a solitary Win tap is redirected. Win+E and all other chords stay native.
InstallMouseHook()
#HotIf ProcessExist("yasb.exe")
~LWin::LaunchpadWinTap("LWin")
~RWin::LaunchpadWinTap("RWin")
#HotIf
LaunchpadWinTap(keyName) {
    Send "{Blind}{vkE8}"
    KeyWait keyName
    if A_PriorKey = keyName && ProcessExist("yasb.exe")
        Send "!{F12}"
}
