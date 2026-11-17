@echo off
title ROB RUN zh-TW - Uninstall
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -Filter *.ps1 | Unblock-File; & '%~dp0uninstall.ps1' %*"
echo.
pause
