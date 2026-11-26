@echo off
title TV-Kit - clean up the TV and install the tv-home launcher
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\tvkit.ps1"
echo.
pause
