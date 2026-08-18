@echo off
title Root Box Score - export listener
cd /d "%~dp0"
python tools\export_listener.py
pause
