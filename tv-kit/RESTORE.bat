@echo off
title TV-Kit - restore the TV
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\restore.ps1" %*
echo.
pause
