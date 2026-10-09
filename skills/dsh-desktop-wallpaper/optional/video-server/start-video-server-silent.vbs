' ============================================================
'  Starts the wallpaper video server with NO console window.
'  Used by the logon task "DSH Wallpaper Video Server" so logging
'  in does not open a black window.
' ============================================================
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)
Set sh = CreateObject("WScript.Shell")
sh.Run """" & base & "\start-wallpaper.bat""", 0, False
