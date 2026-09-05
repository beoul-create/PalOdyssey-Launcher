Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = "C:\PalOdyssey Launcher 2.0\tools\liveboard-bot"
WshShell.Run """C:\Program Files\nodejs\node.exe"" index.js", 0, False