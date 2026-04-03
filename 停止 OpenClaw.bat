@echo off
setlocal EnableExtensions DisableDelayedExpansion

call :detect_distro
if errorlevel 1 exit /b 1

echo Stopping OpenClaw Gateway in WSL distro "%DISTRO%"...
wsl.exe -d %DISTRO% -- bash -lc "source ~/.profile >/dev/null 2>&1 || true; systemctl --user stop openclaw-gateway.service || true; if [ -f ~/.openclaw/win11-keepalive.pid ]; then pid=\$(cat ~/.openclaw/win11-keepalive.pid); kill \$pid 2>/dev/null || true; rm -f ~/.openclaw/win11-keepalive.pid; fi"
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
  echo.
  echo Failed to stop OpenClaw.
  echo If the service was not installed, stop any foreground process manually inside WSL.
  exit /b %RC%
)

echo.
echo OpenClaw stop command completed.
exit /b 0

:detect_distro
set "DISTRO="
for /f "usebackq delims=" %%I in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\detect-wsl-distro.ps1"`) do (
  if not defined DISTRO set "DISTRO=%%I"
)

if defined DISTRO exit /b 0

echo No WSL distro found.
echo Install OpenClaw first with deploy-openclaw-win11.bat.
exit /b 1
