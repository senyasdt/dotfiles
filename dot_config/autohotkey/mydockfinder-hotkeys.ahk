#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook true

; Run with --check to validate syntax without enabling any hotkeys.
if A_Args.Length && A_Args[1] = "--check"
    ExitApp

; The owner assigned Alt+F12 to Launchpad in MyDockFinder.
; Preserve Windows-key chords and use only a standalone Windows-key tap.
InstallMouseHook()

#HotIf
~LWin::MyDockWinTap("LWin")
~RWin::MyDockWinTap("RWin")
#HotIf

MyDockWinTap(keyName) {
    ; Mask the Start menu while leaving the Windows key available for chords.
    Send "{Blind}{vkE8}"
    KeyWait keyName
    if A_PriorKey = keyName {
        if ProcessExist("Dock_64.exe")
            Send "!{F12}"
        else
            Run "explorer.exe shell:AppsFolder"
    }
}
