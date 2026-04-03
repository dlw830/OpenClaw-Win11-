$ErrorActionPreference = 'Stop'

$script:SkipOnboard = $false
$script:SkipBootTask = $false
$script:DryRun = $false
$script:Resume = $false
$script:Distro = 'Ubuntu-24.04'
$script:RepoUrl = 'https://github.com/openclaw/openclaw.git'
$script:RepoRef = 'v2026.3.8'
$script:NetworkProfile = ''
$script:HttpProxy = ''
$script:HttpsProxy = ''
$script:NoProxy = ''
$script:AptMirror = ''
$script:NpmRegistry = ''
$script:NodeDistMirror = ''
$script:LinuxUser = $null
$script:WslScriptWin = $null
$script:WslScriptLinux = $null
$script:BatPath = Join-Path $PSScriptRoot 'deploy-openclaw-win11.bat'
$script:ConsoleUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:LastWslExitCode = 0

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
    Write-Host '用法：deploy-openclaw-win11.bat [参数]'
    Write-Host ''
    Write-Host '参数：'
    Write-Host '  --skip-onboard    只完成环境安装和构建，不启动 openclaw onboard'
    Write-Host '  --skip-boot-task  不创建 Windows 开机自动唤醒 WSL 的计划任务'
    Write-Host '  --dry-run         仅打印关键动作，不实际修改系统'
    Write-Host '  --distro 名称     指定 WSL 发行版，默认 Ubuntu-24.04'
    Write-Host '  --repo-url 地址   指定 OpenClaw Git 仓库地址，默认官方仓库'
    Write-Host '  --ref 名称        指定要部署的 Git 分支、标签或提交，默认 v2026.3.8'
    Write-Host '  --network-profile 预设网络配置，当前支持 cn'
    Write-Host '  --http-proxy 地址 指定 HTTP 代理，例如 http://127.0.0.1:7890'
    Write-Host '  --https-proxy 地址 指定 HTTPS 代理，例如 http://127.0.0.1:7890'
    Write-Host '  --no-proxy 列表   指定免代理地址，逗号分隔'
    Write-Host '  --apt-mirror 地址 指定 Ubuntu 软件源镜像根地址'
    Write-Host '  --npm-registry 地址 指定 npm/pnpm registry 地址'
    Write-Host '  --node-dist-mirror 地址 指定 Node.js 二进制下载镜像根地址'
    Write-Host '  --help, -h        显示本帮助'
    Write-Host ''
    Write-Host '说明：'
    Write-Host '  1. 把这 3 个部署文件放在同一目录后即可运行，不需要额外复制源码仓库。'
    Write-Host '  2. 官方推荐 Windows 通过 WSL2 + Ubuntu 部署，本脚本会在 WSL 内自动拉取源码并构建。'
    Write-Host '  3. 若首次安装 WSL，脚本会要求重启，并在重启后自动续跑。'
    Write-Host '  4. 若需国内网络优化，可优先尝试 --network-profile cn。'
    Write-Host ''
}

function Parse-Arguments {
    param([string[]]$InputArgs)

    for ($i = 0; $i -lt $InputArgs.Count; $i++) {
        switch ($InputArgs[$i]) {
            '--skip-onboard' { $script:SkipOnboard = $true }
            '--skip-boot-task' { $script:SkipBootTask = $true }
            '--dry-run' { $script:DryRun = $true }
            '--resume' { $script:Resume = $true }
            '--help' { Show-Help; exit 0 }
            '-h' { Show-Help; exit 0 }
            '--distro' {
                $i++
                if ($i -ge $InputArgs.Count) {
                    throw '--distro 需要跟一个发行版名称，例如 --distro Ubuntu-24.04'
                }
                $script:Distro = $InputArgs[$i]
            }
            '--repo-url' {
                $i++
                if ($i -ge $InputArgs.Count) {
                    throw '--repo-url 需要跟一个 Git 仓库地址，例如 --repo-url https://github.com/openclaw/openclaw.git'
                }
                $script:RepoUrl = $InputArgs[$i]
            }
            '--ref' {
                $i++
                if ($i -ge $InputArgs.Count) {
                    throw '--ref 需要跟一个 Git 分支、标签或提交，例如 --ref main'
                }
                $script:RepoRef = $InputArgs[$i]
            }
            '--network-profile' {
                $i++
                if ($i -ge $InputArgs.Count) {
                    throw '--network-profile 需要跟一个预设名称，例如 --network-profile cn'
                }
                $script:NetworkProfile = $InputArgs[$i]
            }
            '--http-proxy' {
                $i++
                if ($i -ge $InputArgs.Count) {
                    throw '--http-proxy 需要跟一个代理地址，例如 --http-proxy http://127.0.0.1:7890'
                }
                $script:HttpProxy = $InputArgs[$i]
            }
            '--https-proxy' {
                $i++
                if ($i -ge $InputArgs.Count) {
                    throw '--https-proxy 需要跟一个代理地址，例如 --https-proxy http://127.0.0.1:7890'
                }
                $script:HttpsProxy = $InputArgs[$i]
            }
            '--no-proxy' {
                $i++
                if ($i -ge $InputArgs.Count) {
                    throw '--no-proxy 需要跟一个免代理列表，例如 --no-proxy localhost,127.0.0.1'
                }
                $script:NoProxy = $InputArgs[$i]
            }
            '--apt-mirror' {
                $i++
                if ($i -ge $InputArgs.Count) {
                    throw '--apt-mirror 需要跟一个镜像地址，例如 --apt-mirror https://mirrors.tuna.tsinghua.edu.cn/ubuntu'
                }
                $script:AptMirror = $InputArgs[$i]
            }
            '--npm-registry' {
                $i++
                if ($i -ge $InputArgs.Count) {
                    throw '--npm-registry 需要跟一个 registry 地址，例如 --npm-registry https://registry.npmmirror.com'
                }
                $script:NpmRegistry = $InputArgs[$i]
            }
            '--node-dist-mirror' {
                $i++
                if ($i -ge $InputArgs.Count) {
                    throw '--node-dist-mirror 需要跟一个镜像地址，例如 --node-dist-mirror https://mirrors.tuna.tsinghua.edu.cn/nodejs-release'
                }
                $script:NodeDistMirror = $InputArgs[$i]
            }
            default {
                throw "不支持的参数：$($InputArgs[$i])"
            }
        }
    }
}

function Apply-NetworkProfile {
    if ([string]::IsNullOrWhiteSpace($script:NetworkProfile)) {
        return
    }

    switch ($script:NetworkProfile.ToLowerInvariant()) {
        'cn' {
            if ([string]::IsNullOrWhiteSpace($script:AptMirror)) {
                $script:AptMirror = 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu'
            }
            if ([string]::IsNullOrWhiteSpace($script:NpmRegistry)) {
                $script:NpmRegistry = 'https://registry.npmmirror.com'
            }
            if ([string]::IsNullOrWhiteSpace($script:NodeDistMirror)) {
                $script:NodeDistMirror = 'https://mirrors.tuna.tsinghua.edu.cn/nodejs-release'
            }
        }
        default {
            throw "不支持的网络预设：$($script:NetworkProfile)。当前仅支持 cn"
        }
    }
}

function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ResumeArguments {
    $items = @('--resume')
    if ($script:SkipOnboard) { $items += '--skip-onboard' }
    if ($script:SkipBootTask) { $items += '--skip-boot-task' }
    if ($script:DryRun) { $items += '--dry-run' }
    if ($script:Distro -ne 'Ubuntu-24.04') {
        $items += '--distro'
        $items += $script:Distro
    }
    if ($script:RepoUrl -ne 'https://github.com/openclaw/openclaw.git') {
        $items += '--repo-url'
        $items += $script:RepoUrl
    }
    if ($script:RepoRef -ne 'v2026.3.8') {
        $items += '--ref'
        $items += $script:RepoRef
    }
    if (-not [string]::IsNullOrWhiteSpace($script:NetworkProfile)) {
        $items += '--network-profile'
        $items += $script:NetworkProfile
    }
    if (-not [string]::IsNullOrWhiteSpace($script:HttpProxy)) {
        $items += '--http-proxy'
        $items += $script:HttpProxy
    }
    if (-not [string]::IsNullOrWhiteSpace($script:HttpsProxy)) {
        $items += '--https-proxy'
        $items += $script:HttpsProxy
    }
    if (-not [string]::IsNullOrWhiteSpace($script:NoProxy)) {
        $items += '--no-proxy'
        $items += $script:NoProxy
    }
    if (-not [string]::IsNullOrWhiteSpace($script:AptMirror)) {
        $items += '--apt-mirror'
        $items += $script:AptMirror
    }
    if (-not [string]::IsNullOrWhiteSpace($script:NpmRegistry)) {
        $items += '--npm-registry'
        $items += $script:NpmRegistry
    }
    if (-not [string]::IsNullOrWhiteSpace($script:NodeDistMirror)) {
        $items += '--node-dist-mirror'
        $items += $script:NodeDistMirror
    }
    return $items
}

function Ensure-Admin {
    if (Test-Admin) {
        return
    }

    Write-Info '需要管理员权限，正在尝试自动提权...'
    if ($script:DryRun) {
        Write-Info '当前为 dry-run，跳过管理员提权。'
        return
    }

    $argList = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        ('"{0}"' -f $PSCommandPath)
    ) + (Get-ResumeArguments | ForEach-Object { '"{0}"' -f $_ })

    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList ($argList -join ' ') -PassThru -Wait
    if (-not $process) {
        throw '管理员提权被取消，脚本无法继续。'
    }
    exit $process.ExitCode
}

function Convert-ToWslPath {
    param([Parameter(Mandatory)] [string]$WindowsPath)

    $resolved = (Resolve-Path $WindowsPath).Path.TrimEnd('\')
    $drive = $resolved.Substring(0, 1).ToLowerInvariant()
    $rest = $resolved.Substring(2).Replace('\', '/')
    return "/mnt/$drive$rest"
}

function Check-WindowsVersion {
    $build = [Environment]::OSVersion.Version.Build
    if ($build -ge 22000) {
        Write-Info "已检测到 Windows 11 或更高版本，系统构建号：$build"
    }
    else {
        Write-WarnMsg "当前系统构建号为 $build，看起来不是 Win11。脚本仍会继续，但不保证完全兼容。"
    }
}

function Ensure-WslCommand {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) {
        throw '未找到 wsl.exe，请确认当前系统支持 WSL。'
    }
}

function Prepare-LinuxUser {
    $user = $env:USERNAME.ToLowerInvariant() -replace '[^a-z0-9_-]', '-'
    if ([string]::IsNullOrWhiteSpace($user)) {
        $user = 'openclaw'
    }
    $script:LinuxUser = $user
    Write-Info "计划使用 Linux 用户：$($script:LinuxUser)"
}

function Register-Resume {
    $resumeArgs = Get-ResumeArguments
    $command = '"{0}" {1}' -f $script:BatPath, ($resumeArgs -join ' ')
    if ($script:DryRun) {
        Write-Info "模拟注册 RunOnce：$command"
        return
    }
    New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'OpenClawWin11Deploy' -Value $command -PropertyType String -Force | Out-Null
}

function Clear-Resume {
    if ($script:DryRun) {
        return
    }
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'OpenClawWin11Deploy' -ErrorAction SilentlyContinue
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

function Detect-OrInstallDistro {
    $distros = Get-InstalledDistros
    $found = $distros | Where-Object { $_ -eq $script:Distro } | Select-Object -First 1
    if (-not $found) {
        $found = $distros | Where-Object { $_ -eq 'Ubuntu-24.04' } | Select-Object -First 1
    }
    if (-not $found) {
        $found = $distros | Where-Object { $_ -eq 'Ubuntu' } | Select-Object -First 1
    }

    if ($found) {
        $script:Distro = $found
        Write-Info "已找到 WSL 发行版：$($script:Distro)"
        return $false
    }

    Write-Info "未检测到可用的 Ubuntu WSL 发行版，准备安装：$($script:Distro)"
    if ($script:DryRun) {
        return $true
    }

    Ensure-Admin
    & wsl.exe --install -d $script:Distro
    if ($LASTEXITCODE -ne 0) {
        throw 'WSL/Ubuntu 安装失败，请检查 BIOS 虚拟化、VirtualMachinePlatform、Hyper-V 和网络环境。'
    }
    return $true
}

function Test-WslDistroLaunch {
    param([Parameter(Mandatory)] [string]$DistroName)

    if ($script:DryRun) {
        return $true
    }

    & wsl.exe -d $DistroName --exec /bin/true 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

function Confirm-WslDistroLaunch {
    if (Test-WslDistroLaunch -DistroName $script:Distro) {
        return
    }

    $installedDistros = Get-InstalledDistros
    $candidates = @($script:Distro, 'Ubuntu-24.04', 'Ubuntu') + $installedDistros
    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        if ($candidate -eq $script:Distro) {
            continue
        }

        if (Test-WslDistroLaunch -DistroName $candidate) {
            Write-WarnMsg "WSL 发行版 $($script:Distro) 当前无法启动，已自动改用：$candidate"
            $script:Distro = $candidate
            return
        }
    }

    $knownDistros = if ($installedDistros) { $installedDistros -join ', ' } else { '无' }
    throw "当前 PowerShell 会话无法启动 WSL 发行版 $($script:Distro)。已检测到的发行版：$knownDistros。请先手动运行 `wsl -l -v` 和 `wsl -d $($script:Distro)` 确认可启动，然后再重试。"
}

function Write-WslScript {
    $helperPath = Join-Path $PSScriptRoot 'deploy-openclaw-win11.wsl.sh'
    if (-not (Test-Path $helperPath)) {
        throw "缺少 WSL 部署助手脚本：$helperPath"
    }
    $script:WslScriptWin = $helperPath
    $script:WslScriptLinux = Convert-ToWslPath -WindowsPath $helperPath
}

function Run-WslProvision {
    Write-Info '开始在 WSL 中执行 OpenClaw 部署流程...'
    if ($script:DryRun) {
        Write-Info "模拟执行：wsl.exe -d $($script:Distro) -u root -- bash $($script:WslScriptLinux) $($script:RepoUrl) $($script:RepoRef) $($script:LinuxUser) $([int]$script:SkipOnboard) $($script:HttpProxy) $($script:HttpsProxy) $($script:NoProxy) $($script:AptMirror) $($script:NpmRegistry) $($script:NodeDistMirror)"
        $script:LastWslExitCode = 0
        return
    }

    $script:LastWslExitCode = 0
    & wsl.exe -d $script:Distro -u root -- bash $script:WslScriptLinux $script:RepoUrl $script:RepoRef $script:LinuxUser ([int]$script:SkipOnboard) $script:HttpProxy $script:HttpsProxy $script:NoProxy $script:AptMirror $script:NpmRegistry $script:NodeDistMirror
    $script:LastWslExitCode = $LASTEXITCODE
}

function Create-BootTask {
    Write-Info '正在创建 WSL 开机自启动任务...'
    if ($script:DryRun) {
        Write-Info "模拟执行：schtasks /create /tn `"OpenClaw WSL Boot`" /tr `"wsl.exe -d $($script:Distro) --exec /bin/true`" /sc onstart /ru SYSTEM /f"
        return
    }

    if (-not (Test-Admin)) {
        Write-WarnMsg '当前不是管理员会话，已跳过创建 WSL 开机自启动任务。'
        Write-WarnMsg '如需创建该任务，请稍后以管理员身份重新运行 deploy-openclaw-win11.bat --skip-onboard。'
        return
    }

    & schtasks.exe /create /tn 'OpenClaw WSL Boot' /tr "wsl.exe -d $($script:Distro) --exec /bin/true" /sc onstart /ru SYSTEM /f | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'WSL 开机自启动任务创建失败。'
    }
}

function Show-Banner {
    Write-Host ''
    Write-Host '=============================================================' -ForegroundColor DarkGray
    Write-Host '                 OpenClaw Win11 一键部署脚本' -ForegroundColor Green
    Write-Host '=============================================================' -ForegroundColor DarkGray
    Write-Host ''
    Write-Info '官方推荐的 Windows 部署方式是 WSL2 + Ubuntu。'
    Write-Info '本脚本会自动处理 WSL2、Ubuntu、Python、Node.js 22、pnpm、源码拉取、构建、CLI 链接和网关引导安装。'
    Write-Host ''
}

try {
    Parse-Arguments -InputArgs $args
    Apply-NetworkProfile
    Show-Banner
    Check-WindowsVersion
    Ensure-WslCommand
    Prepare-LinuxUser
    Write-Info "源码仓库：$($script:RepoUrl)"
    Write-Info "源码版本：$($script:RepoRef)"
    if (-not [string]::IsNullOrWhiteSpace($script:NetworkProfile)) {
        Write-Info "网络预设：$($script:NetworkProfile)"
    }
    if (-not [string]::IsNullOrWhiteSpace($script:HttpProxy)) {
        Write-Info "HTTP 代理：$($script:HttpProxy)"
    }
    if (-not [string]::IsNullOrWhiteSpace($script:HttpsProxy)) {
        Write-Info "HTTPS 代理：$($script:HttpsProxy)"
    }
    if (-not [string]::IsNullOrWhiteSpace($script:AptMirror)) {
        Write-Info "APT 镜像：$($script:AptMirror)"
    }
    if (-not [string]::IsNullOrWhiteSpace($script:NpmRegistry)) {
        Write-Info "npm registry：$($script:NpmRegistry)"
    }
    if (-not [string]::IsNullOrWhiteSpace($script:NodeDistMirror)) {
        Write-Info "Node.js 下载镜像：$($script:NodeDistMirror)"
    }

    $needsReboot = Detect-OrInstallDistro
    if ($needsReboot) {
        Register-Resume
        Write-WarnMsg '已触发 WSL/Ubuntu 安装，通常需要重启 Windows 后继续。'
        Write-Info '我已注册一次性自启动，重启后会自动继续执行本脚本。'
        if (-not $script:DryRun) {
            $choice = Read-Host '是否现在重启 Windows？输入 Y 立即重启，输入其他任意键稍后手动重启'
            if ($choice -match '^[Yy]$') {
                shutdown.exe /r /t 10 /c 'OpenClaw Win11 部署需要重启系统以完成 WSL 安装。'
            }
        }
        exit 0
    }

    Confirm-WslDistroLaunch
    Write-WslScript
    Run-WslProvision
    $rc = $script:LastWslExitCode
    if ($rc -eq 42) {
        Write-Info '正在重启 WSL，以启用 systemd 并切换默认 Linux 用户...'
        if (-not $script:DryRun) {
            & wsl.exe --shutdown
            if ($LASTEXITCODE -ne 0) {
                throw 'WSL 重启失败，请手动执行 wsl --shutdown 后重试。'
            }
            Start-Sleep -Seconds 3
        }
        Run-WslProvision
        $rc = $script:LastWslExitCode
    }
    if ($rc -ne 0) {
        throw "WSL 内部署流程失败，退出码：$rc"
    }

    if (-not $script:SkipBootTask) {
        Create-BootTask
    }

    Clear-Resume
    Write-Host ''
    Write-Host '[完成] OpenClaw 已在 Win11 + WSL2 环境完成部署。' -ForegroundColor Green
    Write-Host "[完成] Linux 用户：$($script:LinuxUser)" -ForegroundColor Green
    Write-Host "[完成] WSL 发行版：$($script:Distro)" -ForegroundColor Green
    Write-Host "[完成] 部署副本目录：/home/$($script:LinuxUser)/openclaw-local-src" -ForegroundColor Green
    if ($script:SkipOnboard) {
        Write-Info '你跳过了引导配置，可稍后执行下面的命令继续：'
        Write-Host "wsl -d $($script:Distro) -- bash -lc 'export PNPM_HOME=\"`$HOME/.local/share/pnpm\"; export PATH=\"`$PNPM_HOME:`$PATH\"; cd ~/openclaw-local-src && openclaw onboard --install-daemon'"
    }
    else {
        Write-Info '如果你已经完成引导配置，现在可以用下面的命令检查服务：'
        Write-Host "wsl -d $($script:Distro) -- bash -lc 'systemctl --user status openclaw-gateway --no-pager'"
    }
    Invoke-ExitPause
    exit 0
}
catch {
    Write-Host ''
    Write-ErrorMsg $_.Exception.Message
    Write-Host '[提示] 常见排查点：' -ForegroundColor Yellow
    Write-Host '  1. BIOS 已开启虚拟化，且 Windows 已允许 WSL2。' -ForegroundColor Yellow
    Write-Host '  2. 网络可以访问源码仓库、Ubuntu 软件源、Node.js 下载源和 npm registry；国内网络可优先尝试 --network-profile cn。' -ForegroundColor Yellow
    Write-Host '  3. 若 pnpm 提示 Ignored build scripts，请按提示批准后重试。' -ForegroundColor Yellow
    Write-Host '  4. 如需修复已安装网关，可在 WSL 内执行 openclaw doctor。' -ForegroundColor Yellow
    Invoke-ExitPause
    exit 1
}
