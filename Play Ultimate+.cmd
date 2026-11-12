@echo off
setlocal DisableDelayedExpansion
set "ULTIMATE_PLUS_GAME=%~f1"
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Data\Play.ps1"
if errorlevel 1 pause
