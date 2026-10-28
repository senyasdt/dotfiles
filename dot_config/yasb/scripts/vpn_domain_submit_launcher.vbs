Set shell = CreateObject("WScript.Shell")
script = shell.ExpandEnvironmentStrings("%USERPROFILE%") & "\.config\yasb\scripts\Add-VpnDomainGui.ps1"
shell.Run "powershell.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & script & Chr(34), 0, False
