Option Explicit

Dim shell
Dim fso
Dim scriptDir
Dim launchBat

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
launchBat = fso.BuildPath(scriptDir, "launch.bat")

If Not fso.FileExists(launchBat) Then
    MsgBox "launch.bat not found:" & vbCrLf & launchBat, vbCritical, "IYAGI Terminal"
    WScript.Quit 1
End If

' 0 = hidden window, False = do not wait.
shell.Run """" & launchBat & """", 0, False
