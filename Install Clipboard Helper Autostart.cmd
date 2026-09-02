@echo off
rem Installs the clipboard helper into the Startup folder, so it runs
rem automatically at every login. Double-click once and forget it.
set TARGET=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\RootBoxScoreClipboard.cmd
> "%TARGET%" echo @echo off
>> "%TARGET%" echo start "" pythonw "%~dp0tools\clipboard_helper.py"
call "%TARGET%"
echo Clipboard helper installed to autostart and started now.
pause
