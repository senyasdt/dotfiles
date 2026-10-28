Set shell = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
Set wmi = GetObject("winmgmts:\\.\root\cimv2")

profile = shell.ExpandEnvironmentStrings("%USERPROFILE%")
localAppData = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%")
scriptPath = profile & "\.config\yasb\scripts\vial_layout_overlay.py"
logPath = shell.ExpandEnvironmentStrings("%TEMP%") & "\vial_layout_overlay_launcher.log"

For Each proc In wmi.ExecQuery("SELECT ProcessId, Name, CommandLine FROM Win32_Process")
    cmd = ""
    On Error Resume Next
    cmd = proc.CommandLine
    On Error GoTo 0
    If InStr(1, cmd, "vial_layout_overlay.py", vbTextCompare) > 0 Then
        On Error Resume Next
        proc.Terminate()
        On Error GoTo 0
    End If
Next

candidates = Array( _
    localAppData & "\Python\pythoncore-3.14-64\pythonw.exe", _
    localAppData & "\Python\bin\pythonw.exe", _
    localAppData & "\Programs\Thonny\pythonw.exe", _
    localAppData & "\Microsoft\WindowsApps\pythonw.exe", _
    "pythonw.exe", _
    "pyw.exe" _
)

pythonw = ""
For Each candidate In candidates
    If InStr(1, candidate, "\", vbTextCompare) > 0 Then
        If fs.FileExists(candidate) Then
            pythonw = candidate
            Exit For
        End If
    Else
        pythonw = candidate
        Exit For
    End If
Next

If Not fs.FileExists(scriptPath) Then
    Set log = fs.OpenTextFile(logPath, 8, True)
    log.WriteLine Now & " missing overlay script: " & scriptPath
    log.Close
    WScript.Quit 1
End If

If pythonw = "" Then
    Set log = fs.OpenTextFile(logPath, 8, True)
    log.WriteLine Now & " pythonw.exe not found"
    log.Close
    WScript.Quit 1
End If

shell.Run Chr(34) & pythonw & Chr(34) & " " & Chr(34) & scriptPath & Chr(34), 1, False
