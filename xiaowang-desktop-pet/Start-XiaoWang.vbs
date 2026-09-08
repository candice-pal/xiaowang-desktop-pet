Option Explicit

Dim shell, fileSystem, baseFolder, scriptPath, command
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

baseFolder = fileSystem.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fileSystem.BuildPath(baseFolder, "XiaoWangPet.ps1")
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File " & Chr(34) & scriptPath & Chr(34)

shell.Run command, 0, False
