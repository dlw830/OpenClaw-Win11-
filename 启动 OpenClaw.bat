@echo off
setlocal EnableExtensions DisableDelayedExpansion

call :detect_distro
if errorlevel 1 exit /b 1

echo Starting OpenClaw Gateway in WSL distro "%DISTRO%"...
call :start_keepalive
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
  echo.
  echo Failed to start OpenClaw.
  echo Try running this command manually:
  echo wsl -d "%DISTRO%" -- bash -lc "export PNPM_HOME=\"$HOME/.local/share/pnpm\"; export PATH=\"$PNPM_HOME:$PATH\"; openclaw doctor"
  exit /b %RC%
)

echo.
echo Waiting for Gateway to become ready...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$deadline=(Get-Date).AddSeconds(90); do { try { $response=Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 http://127.0.0.1:18789/; if ($response.StatusCode -eq 200) { exit 0 } } catch {} ; Start-Sleep -Seconds 2 } while ((Get-Date) -lt $deadline); exit 1"
if errorlevel 1 (
  echo Gateway is still starting. Open http://127.0.0.1:18789/ in your browser in a few seconds.
  exit /b 0
)

set "DASHBOARD_URL="
for /f "usebackq delims=" %%I in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\get-openclaw-dashboard-url.ps1"`) do (
  if not defined DASHBOARD_URL set "DASHBOARD_URL=%%I"
)
if not defined DASHBOARD_URL set "DASHBOARD_URL=http://127.0.0.1:18789/"

echo Gateway is ready at %DASHBOARD_URL%
start "" "%DASHBOARD_URL%"
exit /b 0

:start_keepalive
wsl.exe -d %DISTRO% -- bash -lc "if [ ! -f ~/openclaw-local-src/dist/index.js ]; then echo && echo '  [警告] 构建产物缺失，正在自动重建，可能需要数分钟...' && echo; cd ~/openclaw-local-src && pnpm build 2>&1 || exit 1; fi"
if errorlevel 1 (
  echo.
  echo [错误] 构建产物缺失且自动重建失败。
  echo 请重新运行 deploy-openclaw-win11.bat，或在 WSL 中手动执行：
  echo   cd ~/openclaw-local-src ^&^& pnpm build
  exit /b 1
)
start "OpenClaw Gateway" /min wsl.exe -d %DISTRO% -- bash -lc "mkdir -p ~/.openclaw; if [ -f ~/.openclaw/win11-keepalive.pid ] && kill -0 \$(cat ~/.openclaw/win11-keepalive.pid) 2>/dev/null; then source ~/.profile >/dev/null 2>&1 || true; systemctl --user restart openclaw-gateway.service; exit 0; fi; echo \$$ > ~/.openclaw/win11-keepalive.pid; trap 'rm -f ~/.openclaw/win11-keepalive.pid' EXIT; source ~/.profile >/dev/null 2>&1 || true; systemctl --user restart openclaw-gateway.service; while true; do sleep 3600; done"
exit /b %ERRORLEVEL%

:detect_distro
set "DISTRO="
for /f "usebackq delims=" %%I in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\detect-wsl-distro.ps1"`) do (
  if not defined DISTRO set "DISTRO=%%I"
)

if defined DISTRO exit /b 0

echo No WSL distro found.
echo Install OpenClaw first with deploy-openclaw-win11.bat.
exit /b 1
