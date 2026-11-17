@echo off
title ROB RUN zh-TW - Install
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -Filter *.ps1 | Unblock-File; & '%~dp0install.ps1' %*"
echo.
pause
