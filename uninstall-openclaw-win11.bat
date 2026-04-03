@echo off
setlocal EnableExtensions
set "OPENCLAW_INTERACTIVE_PAUSE=0"
set "OPENCLAW_INTERACTIVE_ALWAYS_PAUSE=1"
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall-openclaw-win11.ps1" %*
set "RC=%ERRORLEVEL%"
if "%OPENCLAW_INTERACTIVE_ALWAYS_PAUSE%"=="1" (
	echo.
	pause
)
exit /b %RC%
