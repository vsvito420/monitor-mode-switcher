' Starts Monitor Mode Switcher without a console window.
' Optional argument: a mode name, e.g.  MonitorModeSwitcher.vbs "Desk"  (switches directly, no tray)
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
arg = ""
If WScript.Arguments.Count > 0 Then arg = " -Mode """ & WScript.Arguments(0) & """"
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\MonitorModeSwitcher.ps1""" & arg, 0, False
