$ErrorActionPreference = 'Stop'

$script:Distro = 'Ubuntu-24.04'
$script:LinuxUser = $null
$script:DryRun = $false
$script:PurgeConfig = $true
$script:RemoveBootTask = $true
$script:RemoveWslUser = $false
$script:RemoveDistro = $false
$script:ConsoleUtf8 = [System.Text.UTF8Encoding]::new($false)

$OutputEncoding = $script:ConsoleUtf8
[Console]::InputEncoding = $script:ConsoleUtf8
[Console]::OutputEncoding = $script:ConsoleUtf8

function Test-ShouldPauseOnExit {
    if ($env:OPENCLAW_INTERACTIVE_PAUSE -match '^(0|1)$') {
        return $env:OPENCLAW_INTERACTIVE_PAUSE -eq '1'
    }

    if (-not [Environment]::UserInteractive) {
        return $false
    }

    if ($Host.Name -ne 'ConsoleHost') {
        return $false
    }

    try {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId = $PID"
        for ($depth = 0; $depth -lt 4 -and $process; $depth++) {
            if ($process.Name -in @('cmd.exe', 'explorer.exe')) {
                return $true
            }

            if (-not $process.ParentProcessId) {
                break
            }

            $process = Get-CimInstance Win32_Process -Filter ("ProcessId = {0}" -f $process.ParentProcessId)
        }

        return $false
    }
    catch {
        return $false
    }
}

function Invoke-ExitPause {
    if (-not (Test-ShouldPauseOnExit)) {
        return
    }

    Write-Host ''
    Read-Host '按回车键关闭窗口' | Out-Null
}

function Write-Info([string]$Message) {
    Write-Host "[信息] $Message" -ForegroundColor Cyan
}

function Write-WarnMsg([string]$Message) {
    Write-Host "[警告] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg([string]$Message) {
    Write-Host "[错误] $Message" -ForegroundColor Red
}

function Show-Help {
    Write-Host ''
    Write-Host '用法：uninstall-openclaw-win11.bat [参数]'
    Write-Host ''
    Write-Host '参数：'
    Write-Host '  --distro 名称       指定要清理的 WSL 发行版，默认 Ubuntu-24.04'
    Write-Host '  --keep-config       保留 ~/.openclaw 与 ~/.config/openclaw 等状态目录'
    Write-Host '  --keep-boot-task    保留 Windows 计划任务 OpenClaw WSL Boot'
    Write-Host '  --remove-wsl-user   连同安装时创建的 Linux 用户目录一并删除'
    Write-Host '  --remove-distro     连同整个 WSL 发行版一起删除（危险操作）'
    Write-Host '  --dry-run           仅打印关键动作，不实际修改系统'
    Write-Host '  --help, -h          显示本帮助'
    Write-Host ''
    Write-Host '说明：'
    Write-Host '  1. 默认会删除 OpenClaw 服务、CLI 链接、源码副本、默认状态目录和开机计划任务。'
    Write-Host '  2. 默认不会删除整个 WSL 发行版，也不会删除 Linux 用户。'
    Write-Host '  3. 如需验证全新安装，可先执行本脚本，再运行 deploy-openclaw-win11.bat。'
    Write-Host '  4. 若传入 --remove-distro，会在清理完成后执行 wsl --unregister。'
    Write-Host ''
}

function Parse-Arguments {
    param([string[]]$InputArgs)

    for ($i = 0; $i -lt $InputArgs.Count; $i++) {
        switch ($InputArgs[$i]) {
            '--distro' {
                $i++
                if ($i -ge $InputArgs.Count) {
                    throw '--distro 需要跟一个发行版名称，例如 --distro Ubuntu-24.04'
                }
                $script:Distro = $InputArgs[$i]
            }
            '--keep-config' { $script:PurgeConfig = $false }
            '--keep-boot-task' { $script:RemoveBootTask = $false }
            '--remove-wsl-user' { $script:RemoveWslUser = $true }
            '--remove-distro' { $script:RemoveDistro = $true }
            '--dry-run' { $script:DryRun = $true }
            '--help' { Show-Help; exit 0 }
            '-h' { Show-Help; exit 0 }
            default { throw "不支持的参数：$($InputArgs[$i])" }
        }
    }
}

function Get-InstalledDistros {
    $output = & wsl.exe -l -q 2>$null
    if (-not $output) {
        return @()
    }

    return $output |
    ForEach-Object { ($_ -replace [char]0, '').Trim() } |
    Where-Object { $_ }
}

function Ensure-WslCommand {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) {
        throw '未找到 wsl.exe，请确认当前系统支持 WSL。'
    }
}

function Confirm-WslDistro {
    $distros = Get-InstalledDistros
    if (-not $distros) {
        throw '未检测到任何 WSL 发行版，无需卸载 OpenClaw。'
    }

    $found = $distros | Where-Object { $_ -eq $script:Distro } | Select-Object -First 1
    if (-not $found) {
        $found = $distros | Where-Object { $_ -eq 'Ubuntu-24.04' } | Select-Object -First 1
    }
    if (-not $found) {
        $found = $distros | Where-Object { $_ -eq 'Ubuntu' } | Select-Object -First 1
    }
    if (-not $found) {
        $known = $distros -join ', '
        throw "未找到可用于卸载 OpenClaw 的 Ubuntu WSL 发行版。已安装：$known"
    }

    if ($found -ne $script:Distro) {
        Write-WarnMsg "指定发行版 $($script:Distro) 不可用，已自动改用：$found"
        $script:Distro = $found
    }
}

function Prepare-LinuxUser {
    $user = $env:USERNAME.ToLowerInvariant() -replace '[^a-z0-9_-]', '-'
    if ([string]::IsNullOrWhiteSpace($user)) {
        $user = 'openclaw'
    }
    $script:LinuxUser = $user
}

function Convert-ToWslPath {
    param([Parameter(Mandatory)] [string]$WindowsPath)

    $resolved = (Resolve-Path $WindowsPath).Path.TrimEnd('\')
    $drive = $resolved.Substring(0, 1).ToLowerInvariant()
    $rest = $resolved.Substring(2).Replace('\', '/')
    return "/mnt/$drive$rest"
}

function Invoke-WslRootCommand {
    param([Parameter(Mandatory)] [string]$Command)

    if ($script:DryRun) {
        Write-Info "模拟执行：wsl.exe -d $($script:Distro) -u root -- bash <临时脚本>"
        Write-Host $Command
        return
    }

    $tempFile = Join-Path $env:TEMP ('openclaw-uninstall-{0}.sh' -f [guid]::NewGuid().ToString('N'))
    $encoding = [System.Text.UTF8Encoding]::new($false)

    try {
        [System.IO.File]::WriteAllText($tempFile, $Command, $encoding)
        $tempFileWsl = Convert-ToWslPath -WindowsPath $tempFile
        & wsl.exe -d $script:Distro -u root -- bash $tempFileWsl
        if ($LASTEXITCODE -ne 0) {
            throw "WSL 卸载步骤执行失败，退出码：$LASTEXITCODE"
        }
    }
    finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Remove-BootTask {
    if (-not $script:RemoveBootTask) {
        return
    }

    if ($script:DryRun) {
        Write-Info '模拟删除计划任务：OpenClaw WSL Boot'
        return
    }

    & cmd.exe /d /c 'schtasks /query /tn "OpenClaw WSL Boot" >nul 2>nul'
    if ($LASTEXITCODE -ne 0) {
        Write-WarnMsg '未找到计划任务 OpenClaw WSL Boot，已跳过。'
        return
    }

    & cmd.exe /d /c 'schtasks /delete /tn "OpenClaw WSL Boot" /f >nul 2>nul'
    if ($LASTEXITCODE -eq 0) {
        Write-Info '已删除计划任务 OpenClaw WSL Boot。'
        return
    }

    Write-WarnMsg '删除计划任务 OpenClaw WSL Boot 失败，已跳过。'
}

function Clear-ResumeEntry {
    if ($script:DryRun) {
        Write-Info '模拟删除 RunOnce 项：OpenClawWin11Deploy'
        return
    }

    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'OpenClawWin11Deploy' -ErrorAction SilentlyContinue
}

function Remove-WslDistro {
    if (-not $script:RemoveDistro) {
        return
    }

    if ($script:DryRun) {
        Write-Info "模拟注销 WSL 发行版：$($script:Distro)"
        return
    }

    & wsl.exe --terminate $script:Distro 1>$null 2>$null
    & wsl.exe --unregister $script:Distro
    if ($LASTEXITCODE -ne 0) {
        throw "注销 WSL 发行版失败：$($script:Distro)"
    }

    Write-Info "已注销 WSL 发行版：$($script:Distro)"
}

function Get-UninstallScript {
    $purgeFlag = if ($script:PurgeConfig) { '1' } else { '0' }
    $removeUserFlag = if ($script:RemoveWslUser) { '1' } else { '0' }
    $lines = @(
        'set -Eeuo pipefail'
        "APP_USER='$($script:LinuxUser)'"
        "PURGE_CONFIG='$purgeFlag'"
        "REMOVE_USER='$removeUserFlag'"
        ''
        'if ! id "$APP_USER" >/dev/null 2>&1; then'
        "  echo '[信息] WSL 用户不存在，跳过 Linux 侧清理。'"
        '  exit 0'
        'fi'
        ''
        'systemctl --machine "${APP_USER}@" --user disable --now openclaw-gateway.service >/dev/null 2>&1 || true'
        'systemctl --machine "${APP_USER}@" --user daemon-reload >/dev/null 2>&1 || true'
        'pkill -u "$APP_USER" -f openclaw-gateway >/dev/null 2>&1 || true'
        'pkill -u "$APP_USER" -f win11-keepalive >/dev/null 2>&1 || true'
        ''
        'rm -f "/home/$APP_USER/.config/systemd/user/openclaw-gateway.service"'
        'rm -f /home/$APP_USER/.config/systemd/user/openclaw-gateway-*.service'
        'rm -f "/home/$APP_USER/.openclaw/win11-keepalive.pid"'
        'rm -rf "/home/$APP_USER/openclaw-local-src"'
        'rm -f "/home/$APP_USER/.local/share/pnpm/openclaw"'
        'rm -f "/home/$APP_USER/.local/share/pnpm/openclaw.cmd"'
        'rm -f "/home/$APP_USER/.local/share/pnpm/openclaw.ps1"'
        'loginctl disable-linger "$APP_USER" >/dev/null 2>&1 || true'
        ''
        'if [ "$PURGE_CONFIG" = "1" ]; then'
        '  rm -rf "/home/$APP_USER/.openclaw"'
        '  rm -rf /home/$APP_USER/.openclaw-*'
        '  rm -rf "/home/$APP_USER/.config/openclaw"'
        'fi'
        ''
        'if [ "$REMOVE_USER" = "1" ]; then'
        '  userdel -r "$APP_USER" >/dev/null 2>&1 || true'
        'fi'
        ''
        "echo '[信息] WSL 侧 OpenClaw 清理完成。'"
    )

    return ($lines -join "`n")
}

function Show-Banner {
    Write-Host ''
    Write-Host '=============================================================' -ForegroundColor DarkGray
    Write-Host '                 OpenClaw Win11 一键卸载脚本' -ForegroundColor Green
    Write-Host '=============================================================' -ForegroundColor DarkGray
    Write-Host ''
    Write-Info '本脚本会清理 OpenClaw 在 WSL2 + Ubuntu 中安装的服务、源码副本和默认状态目录。'
    Write-Info '默认保留 WSL 发行版和 Linux 用户，便于反复验证安装流程。'
    Write-Host ''
}

try {
    Parse-Arguments -InputArgs $args
    Show-Banner
    Ensure-WslCommand
    Confirm-WslDistro
    Prepare-LinuxUser

    Write-Info "目标 WSL 发行版：$($script:Distro)"
    Write-Info "目标 Linux 用户：$($script:LinuxUser)"
    if ($script:PurgeConfig) {
        Write-Info '将删除默认 OpenClaw 状态目录。'
    }
    if ($script:RemoveWslUser) {
        Write-WarnMsg '将同时删除 Linux 用户及其 home 目录。'
    }
    if ($script:RemoveDistro) {
        Write-WarnMsg '将同时删除整个 WSL 发行版，此操作不可恢复。'
    }

    Invoke-WslRootCommand -Command (Get-UninstallScript)
    Remove-BootTask
    Clear-ResumeEntry
    Remove-WslDistro

    Write-Host ''
    Write-Host '[完成] OpenClaw 卸载流程已完成。' -ForegroundColor Green
    Write-Host "[完成] WSL 发行版：$($script:Distro)" -ForegroundColor Green
    Write-Host "[完成] Linux 用户：$($script:LinuxUser)" -ForegroundColor Green
    if (-not $script:RemoveWslUser) {
        Write-Info '如需重新验证安装脚本，现在可直接重新运行 deploy-openclaw-win11.bat。'
    }
    Invoke-ExitPause
    exit 0
}
catch {
    Write-Host ''
    Write-ErrorMsg $_.Exception.Message
    Write-Host '[提示] 常见排查点：' -ForegroundColor Yellow
    Write-Host '  1. 先确认目标 WSL 发行版可以正常启动。' -ForegroundColor Yellow
    Write-Host '  2. 如果 OpenClaw 没装完整，部分清理动作提示跳过属于正常现象。' -ForegroundColor Yellow
    Write-Host '  3. 如需保留已有配置，请改用 --keep-config。' -ForegroundColor Yellow
    Invoke-ExitPause
    exit 1
}
