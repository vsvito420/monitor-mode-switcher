' Toggles between the two toggle modes (default: the first two modes) without a console window.
' Pin the "Monitor Toggle" shortcut to the taskbar for a one-click switch.
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\MonitorModeSwitcher.ps1"" -Toggle", 0, False
