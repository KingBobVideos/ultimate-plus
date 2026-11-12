@echo off
setlocal DisableDelayedExpansion
set "ULTIMATE_PLUS_GAME=%~f1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Data\Install.ps1"
if errorlevel 1 pause
