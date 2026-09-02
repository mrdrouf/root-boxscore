@echo off
rem Runs the clipboard helper in the background (no window).
rem With it running, the box score's COPY button fills the clipboard itself.
start "" pythonw "%~dp0tools\clipboard_helper.py"
if errorlevel 1 start "" /min python "%~dp0tools\clipboard_helper.py"
