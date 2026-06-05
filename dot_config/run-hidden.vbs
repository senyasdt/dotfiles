Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

If WScript.Arguments.Count = 0 Then
    WScript.Quit 1
End If

scriptPath = WScript.Arguments(0)
logPath = shell.ExpandEnvironmentStrings("%USERPROFILE%") & "\.config\run-hidden.log"
parentDir = fso.GetParentFolderName(scriptPath)
If parentDir <> "" Then
    shell.CurrentDirectory = parentDir
End If

command = "%ComSpec% /d /c " & Chr(34) & scriptPath & Chr(34)

Set logFile = fso.OpenTextFile(logPath, 8, True, -1)
logFile.WriteLine "[" & Now & "] scriptPath=" & scriptPath & " cwd=" & shell.CurrentDirectory & " command=" & command
logFile.Close

shell.Run command, 0, False
