#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook true
if A_Args.Length && A_Args[1] = "--check"
    ExitApp
; Legacy filename retained for persisted ScriptLauncher rules/manual state.
; Classic profile uses the native app library; the YASB profile owns its override.
InstallMouseHook()
#HotIf
~LWin::ApplicationLibraryTap("LWin")
~RWin::ApplicationLibraryTap("RWin")
#HotIf
ApplicationLibraryTap(keyName) {
    Send "{Blind}{vkE8}"
    KeyWait keyName
    if A_PriorKey = keyName
        Run "explorer.exe shell:AppsFolder"
}
