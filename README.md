# 🐾 OpenClaw Win11 一键部署工具

专为 Windows 11 设计的 OpenClaw 一键部署脚本。全程自动完成 WSL2 安装、Ubuntu 配置、Node.js/pnpm/Python 环境搭建、源码拉取与构建，以及网关服务引导，让你用一个脚本从零开始部署完整的 OpenClaw 服务。

## ✨ 主要功能

### 🚀 全自动环境搭建

- 自动检测并安装 WSL2 + Ubuntu-24.04
- 自动安装 Node.js 22、pnpm 10、Python 3
- 自动拉取 OpenClaw 源码并完整构建
- 自动链接 `openclaw` CLI 到 Linux 用户环境
- 自动创建 Windows 开机自唤醒 WSL 的计划任务

### 🌐 国内网络优化

- **一键国内预设**：`--network-profile cn` 自动配置所有镜像
- **APT 镜像**：支持自定义 Ubuntu 软件源（清华 TUNA 等）
- **npm/pnpm Registry**：支持切换 npmmirror 等国内镜像
- **Node.js 下载镜像**：二进制包可从国内节点加速下载
- **HTTP/HTTPS 代理**：全链路代理穿透支持

### 🛡️ 智能容错与续跑

- WSL 首次安装需要重启时，自动注册 RunOnce 续跑任务
- WSL 内 systemd 配置变更后，脚本自动重启 WSL 并继续
- `--resume` 模式支持手动从中断位置续跑
- `--dry-run` 模式打印所有关键动作但不修改系统
- 网络下载自动重试（最多 3 次，指数退避）

### 📦 文件结构

```
deploy-openclaw-win11/
├── deploy-openclaw-win11.bat       # 部署入口（双击运行）
├── deploy-openclaw-win11.ps1       # PowerShell 部署主脚本
├── deploy-openclaw-win11.wsl.sh    # WSL 内部环境配置脚本
├── uninstall-openclaw-win11.bat    # 卸载入口
├── uninstall-openclaw-win11.ps1    # PowerShell 卸载脚本
├── 启动 OpenClaw.bat               # 启动网关服务
├── 停止 OpenClaw.bat               # 停止网关服务
└── scripts/
    ├── detect-wsl-distro.ps1       # 自动检测 WSL 发行版
    └── get-openclaw-dashboard-url.ps1  # 获取面板访问地址
```

## 🚀 快速开始

### 系统要求

- **操作系统**：Windows 11（Build 22000 及以上）
- **权限要求**：管理员权限（脚本会自动请求提权）
- **网络要求**：稳定的互联网连接，国内用户建议配合 `--network-profile cn`
- **磁盘空间**：至少 5 GB 可用空间

### 使用方法

#### 方式1：双击运行（推荐）

直接双击 `deploy-openclaw-win11.bat`，脚本会自动完成所有步骤。

#### 方式2：命令行运行

```cmd
deploy-openclaw-win11.bat [参数]
```

#### 方式3：国内网络一键优化

```cmd
deploy-openclaw-win11.bat --network-profile cn
```

### 部署步骤

1. **自动提权**

   脚本检测到非管理员环境时，会自动弹出 UAC 提权对话框。

2. **检测 / 安装 WSL2**

   若未安装 Ubuntu，脚本会自动执行 `wsl --install -d Ubuntu-24.04`。
   首次安装 WSL 通常需要重启 Windows，脚本会自动注册续跑任务，重启后无需手动操作。

3. **WSL 内全自动配置**

   - 创建与 Windows 用户名对应的 Linux 用户
   - 启用 systemd（并在需要时重启 WSL）
   - 安装系统基础依赖（git、curl、build-essential 等）
   - 安装 Node.js 22、pnpm 10
   - 拉取 OpenClaw 源码并构建

4. **网关引导安装**

   构建完成后，自动启动 `openclaw onboard` 交互式配置流程，引导完成模型认证、渠道配置和网关服务安装。

5. **部署完成**

   ```
   [完成] OpenClaw 已在 Win11 + WSL2 环境完成部署。
   [完成] Linux 用户：your-username
   [完成] WSL 发行版：Ubuntu-24.04
   [完成] 部署副本目录：/home/your-username/openclaw-local-src
   ```

## ⚙️ 命令行参数

### 部署参数（deploy-openclaw-win11.bat）

| 参数 | 说明 | 示例 |
|------|------|------|
| `--network-profile cn` | 国内网络一键预设，自动配置所有镜像 | `--network-profile cn` |
| `--distro 名称` | 指定 WSL 发行版，默认 `Ubuntu-24.04` | `--distro Ubuntu-22.04` |
| `--repo-url 地址` | 指定 OpenClaw Git 仓库地址 | `--repo-url https://github.com/openclaw/openclaw.git` |
| `--ref 名称` | 指定要部署的 Git 分支、标签或提交，默认 `v2026.3.8` | `--ref main` |
| `--http-proxy 地址` | 指定 HTTP 代理 | `--http-proxy http://127.0.0.1:7890` |
| `--https-proxy 地址` | 指定 HTTPS 代理 | `--https-proxy http://127.0.0.1:7890` |
| `--no-proxy 列表` | 指定免代理地址，逗号分隔 | `--no-proxy localhost,127.0.0.1` |
| `--apt-mirror 地址` | 指定 Ubuntu 软件源镜像根地址 | `--apt-mirror https://mirrors.tuna.tsinghua.edu.cn/ubuntu` |
| `--npm-registry 地址` | 指定 npm/pnpm registry 地址 | `--npm-registry https://registry.npmmirror.com` |
| `--node-dist-mirror 地址` | 指定 Node.js 二进制下载镜像根地址 | `--node-dist-mirror https://mirrors.tuna.tsinghua.edu.cn/nodejs-release` |
| `--skip-onboard` | 仅完成环境安装和构建，跳过 `openclaw onboard` | — |
| `--skip-boot-task` | 不创建 Windows 开机自动唤醒 WSL 的计划任务 | — |
| `--dry-run` | 仅打印关键动作，不实际修改系统 | — |
| `--help, -h` | 显示帮助信息 | — |

### 卸载参数（uninstall-openclaw-win11.bat）

| 参数 | 说明 |
|------|------|
| `--distro 名称` | 指定要清理的 WSL 发行版，默认 `Ubuntu-24.04` |
| `--keep-config` | 保留 `~/.openclaw` 与 `~/.config/openclaw` 等状态目录 |
| `--keep-boot-task` | 保留 Windows 计划任务 `OpenClaw WSL Boot` |
| `--remove-wsl-user` | 连同安装时创建的 Linux 用户目录一并删除 |
| `--remove-distro` | 连同整个 WSL 发行版一起删除（危险操作） |
| `--dry-run` | 仅打印关键动作，不实际修改系统 |

## 💡 使用场景

### 1. 国内环境快速部署

国内环境下各类资源（apt、npm、Node.js）下载较慢，推荐一行命令搞定所有镜像配置：

```cmd
deploy-openclaw-win11.bat --network-profile cn
```

等效于同时传入清华 TUNA 的 APT 镜像、npmmirror 的 npm registry 和 Node.js 下载镜像。

### 2. 代理环境部署

企业网络或需要走代理的场景：

```cmd
deploy-openclaw-win11.bat --http-proxy http://127.0.0.1:7890 --https-proxy http://127.0.0.1:7890 --no-proxy localhost,127.0.0.1
```

### 3. 仅安装环境，跳过引导

如需先完成环境搭建，之后再单独执行 `openclaw onboard`：

```cmd
deploy-openclaw-win11.bat --skip-onboard
```

### 4. 指定版本部署

部署特定标签或分支：

```cmd
deploy-openclaw-win11.bat --ref v2026.3.8
```

### 5. 调试部署流程

预览脚本将要执行的所有关键操作，不修改任何系统配置：

```cmd
deploy-openclaw-win11.bat --dry-run
```

## 🖥️ 启动与停止服务

部署完成后，使用以下批处理文件管理 OpenClaw 网关服务：

### 启动服务

双击 `启动 OpenClaw.bat`，脚本将：

1. 自动检测已安装 OpenClaw 的 WSL 发行版
2. 检查构建产物是否完整，缺失时自动重建
3. 启动 `openclaw-gateway` systemd 用户服务
4. 等待网关就绪（最多 90 秒）
5. 自动在默认浏览器中打开 Dashboard

### 停止服务

双击 `停止 OpenClaw.bat`，脚本将停止 WSL 内的 `openclaw-gateway` 服务。

### 手动访问 Dashboard

网关启动后，访问：

```
http://127.0.0.1:18789/
```

## 🌐 镜像源配置参考

### --network-profile cn 等效配置

```cmd
deploy-openclaw-win11.bat ^
  --apt-mirror https://mirrors.tuna.tsinghua.edu.cn/ubuntu ^
  --npm-registry https://registry.npmmirror.com ^
  --node-dist-mirror https://mirrors.tuna.tsinghua.edu.cn/nodejs-release
```

### 常用镜像地址

| 类型 | 镜像名称 | 地址 |
|------|----------|------|
| APT | 清华 TUNA | `https://mirrors.tuna.tsinghua.edu.cn/ubuntu` |
| APT | 阿里云 | `https://mirrors.aliyun.com/ubuntu` |
| APT | 中国科大 USTC | `https://mirrors.ustc.edu.cn/ubuntu` |
| npm | npmmirror | `https://registry.npmmirror.com` |
| Node.js | 清华 TUNA | `https://mirrors.tuna.tsinghua.edu.cn/nodejs-release` |
| Node.js | npmmirror | `https://npmmirror.com/mirrors/node` |

## 🎯 部署流程详解

```
deploy-openclaw-win11.bat
├── 检测 Windows 版本（≥ Build 22000 为 Win11）
├── 检测 / 安装 WSL2 + Ubuntu
│   └── 首次安装需重启 → 注册 RunOnce 自动续跑
├── WSL 内部署（deploy-openclaw-win11.wsl.sh）
│   ├── 创建 Linux 用户（与 Windows 用户名对应）
│   ├── 配置 /etc/wsl.conf（启用 systemd，设置默认用户）
│   │   └── 配置变更需重启 WSL → 自动续跑
│   ├── 安装系统依赖（apt-get）
│   ├── 安装 Node.js 22（从 tarball）
│   ├── 启用 pnpm 10（Corepack 或 npm 全局安装）
│   ├── 配置 npm/pnpm registry（可选）
│   ├── 拉取 OpenClaw 源码（浅克隆）
│   ├── pnpm install（含构建脚本审批）
│   ├── pnpm ui:build + pnpm build
│   ├── pnpm link --global（链接 openclaw CLI）
│   ├── loginctl enable-linger（用户服务持久化）
│   └── openclaw onboard --install-daemon（交互引导）
└── 创建 Windows 开机自启动计划任务
```

## 🛠️ 常见问题

### 1. WSL 安装后提示需要重启

**原因**：首次安装 WSL2 需要启用 Windows 功能并重启系统。

**处理**：脚本会自动弹出重启确认，选择 Y 立即重启，或稍后手动重启。重启后脚本会自动继续，无需手动操作。

### 2. BIOS 未开启虚拟化

**错误**：`WSL/Ubuntu 安装失败，请检查 BIOS 虚拟化...`

**解决**：进入 BIOS 启用 Intel VT-x 或 AMD-V，并在 Windows 功能中启用「虚拟机平台」和「适用于 Linux 的 Windows 子系统」。

### 3. 国内下载速度慢

**解决**：使用国内网络预设：

```cmd
deploy-openclaw-win11.bat --network-profile cn
```

### 4. npm/pnpm 依赖安装超时

**解决**：配置 npm 镜像源：

```cmd
deploy-openclaw-win11.bat --npm-registry https://registry.npmmirror.com
```

### 5. pnpm 请求审批构建脚本

**提示**：`检测到 pnpm 需要审批构建脚本，接下来会打开审批界面。`

**处理**：脚本会自动调用 `pnpm approve-builds`，在交互界面中批准列出的依赖后，脚本自动继续。

### 6. 构建产物缺失，启动失败

**错误**：`[错误] 构建产物缺失且自动重建失败。`

**解决**：重新运行部署脚本，或在 WSL 中手动执行：

```bash
cd ~/openclaw-local-src && pnpm build
```

### 7. 管理员提权被取消

**错误**：`管理员提权被取消，脚本无法继续。`

**解决**：以管理员身份手动运行命令提示符，然后再执行部署脚本。

### 8. 卸载后重新安装

先执行卸载：

```cmd
uninstall-openclaw-win11.bat
```

再重新部署：

```cmd
deploy-openclaw-win11.bat
```

## 🔄 更新日志

### v1.0 (20260101)

- ✅ 初始版本发布
- ✅ 支持 WSL2 + Ubuntu-24.04 全自动部署
- ✅ 支持 `--network-profile cn` 国内加速一键预设
- ✅ 支持 HTTP/HTTPS 代理透传
- ✅ 支持自定义 APT、npm、Node.js 镜像
- ✅ WSL 和 systemd 重启后自动续跑
- ✅ Windows 开机自动唤醒 WSL 计划任务
- ✅ 启动 / 停止网关快捷批处理文件
- ✅ 支持 `--dry-run` 模拟执行和完整卸载脚本

## 💖 支持与赞助（打赏）

如果这个项目对你有帮助，欢迎通过以下方式支持作者的持续维护与改进：

- ⭐ **Star 本项目**（这是最好的支持方式）
- 🍴 **Fork 并参与贡献**
- 💬 提出 Issue / 改进建议
- ☕ **自愿打赏（非强制）**

### 打赏方式

| 平台 | 说明 |
|------|------|
| 微信 | 扫描下方二维码 |

> 打赏完全自愿，不影响项目的任何功能或授权。

## 📄 许可证

本项目基于 **MIT License** 开源发布。
你可以自由地使用、修改和分发本项目，但需保留原始版权声明。

---

## 🤝 贡献指南

欢迎提交 **Issue** 和 **Pull Request**！

建议流程：

1. Fork 本仓库
2. 新建分支进行修改
3. 提交 PR 并简要说明修改内容

如是较大改动，建议先提交 Issue 讨论。

---

## 📧 联系方式

- Email：[1013344248@qq.com](mailto:1013344248@qq.com)
- GitHub：@dlw830

---

**Happy Deploying!** 🚀
如果你觉得这个项目有价值，别忘了点个 ⭐
