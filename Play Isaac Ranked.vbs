Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

launcherDir = fso.GetParentFolderName(WScript.ScriptFullName) & "\launcher"
cmd = "cmd /c cd /d """ & launcherDir & """ && if not exist config.json copy /Y config.default.json config.json >nul && if not exist node_modules npm install >nul 2>&1 && npm run gui"

' 0 = hidden window, True = wait until launcher exits (when Isaac closes)
WshShell.Run cmd, 0, True
