#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${1:?missing repo url}"
REPO_REF="${2:?missing repo ref}"
APP_USER="${3:?missing linux user}"
SKIP_ONBOARD="${4:-0}"
HTTP_PROXY_VALUE="${5:-}"
HTTPS_PROXY_VALUE="${6:-}"
NO_PROXY_VALUE="${7:-}"
APT_MIRROR="${8:-}"
NPM_REGISTRY="${9:-}"
NODE_DIST_MIRROR="${10:-https://nodejs.org/dist}"
NODE_VERSION="v22.14.0"
USER_HOME="/home/${APP_USER}"
TARGET_DIR="${USER_HOME}/openclaw-local-src"
INSTALL_LOG="${USER_HOME}/openclaw-pnpm-install.log"
UI_BUILD_LOG="${USER_HOME}/openclaw-ui-build.log"
BUILD_LOG="${USER_HOME}/openclaw-build.log"

say() {
  printf '[%s] %s\n' "$1" "$2"
}

info() {
  say 信息 "$1"
}

warn() {
  say 警告 "$1"
}

fail() {
  say 错误 "$1"
  exit 1
}

retry() {
  local max_attempts=3
  local delay=3
  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    local rc=$?
    if (( attempt >= max_attempts )); then
      return "$rc"
    fi
    warn "命令失败，${delay} 秒后重试（${attempt}/${max_attempts}）：$*"
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}

trim_trailing_slash() {
  local value="$1"
  while [[ "$value" == */ ]]; do
    value="${value%/}"
  done
  printf '%s' "$value"
}

configure_network() {
  if [[ -n "$HTTP_PROXY_VALUE" ]]; then
    export http_proxy="$HTTP_PROXY_VALUE"
    export HTTP_PROXY="$HTTP_PROXY_VALUE"
  fi
  if [[ -n "$HTTPS_PROXY_VALUE" ]]; then
    export https_proxy="$HTTPS_PROXY_VALUE"
    export HTTPS_PROXY="$HTTPS_PROXY_VALUE"
  fi
  if [[ -n "$NO_PROXY_VALUE" ]]; then
    export no_proxy="$NO_PROXY_VALUE"
    export NO_PROXY="$NO_PROXY_VALUE"
  fi
  if [[ -n "$APT_MIRROR" ]]; then
    APT_MIRROR="$(trim_trailing_slash "$APT_MIRROR")"
  fi
  if [[ -n "$NPM_REGISTRY" ]]; then
    NPM_REGISTRY="$(trim_trailing_slash "$NPM_REGISTRY")"
  fi
  NODE_DIST_MIRROR="$(trim_trailing_slash "$NODE_DIST_MIRROR")"
}

run_user() {
  local command="$1"
  su - "$APP_USER" -c "export PNPM_HOME=\"$USER_HOME/.local/share/pnpm\"; export PATH=\"$USER_HOME/.local/share/pnpm:\$PATH\"; export OPENCLAW_BUNDLED_PLUGINS_DIR=\"$TARGET_DIR/extensions\"; export COREPACK_ENABLE_DOWNLOAD_PROMPT=0; export PYTHON=\"/usr/bin/python3\"; export http_proxy=\"$HTTP_PROXY_VALUE\"; export https_proxy=\"$HTTPS_PROXY_VALUE\"; export no_proxy=\"$NO_PROXY_VALUE\"; export HTTP_PROXY=\"$HTTP_PROXY_VALUE\"; export HTTPS_PROXY=\"$HTTPS_PROXY_VALUE\"; export NO_PROXY=\"$NO_PROXY_VALUE\"; bash -lc $(printf '%q' "$command")"
}

ensure_user() {
  if id "$APP_USER" >/dev/null 2>&1; then
    info "WSL 用户 ${APP_USER} 已存在。"
  else
    info "正在创建 WSL 用户 ${APP_USER}。"
    useradd -m -s /bin/bash "$APP_USER"
    usermod -aG sudo "$APP_USER" || true
  fi
  mkdir -p "$USER_HOME/.local/share/pnpm" "$USER_HOME/.pnpm-store"
  chown -R "$APP_USER:$APP_USER" "$USER_HOME"
}

ensure_wsl_conf() {
  local changed=0
  touch /etc/wsl.conf
  if ! grep -Eqi '^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true[[:space:]]*$' /etc/wsl.conf; then
    printf '\n[boot]\nsystemd=true\n' >> /etc/wsl.conf
    changed=1
  fi
  if ! grep -Eqi "^[[:space:]]*default[[:space:]]*=[[:space:]]*${APP_USER}[[:space:]]*$" /etc/wsl.conf; then
    printf '\n[user]\ndefault=%s\n' "$APP_USER" >> /etc/wsl.conf
    changed=1
  fi
  if (( changed )); then
    info "已更新 /etc/wsl.conf，需要重启 WSL 以启用 systemd 和默认用户。"
    exit 42
  fi
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "systemctl 不可用，需要重启 WSL。"
    exit 42
  fi
  if [[ "$(ps -p 1 -o comm= 2>/dev/null || true)" != "systemd" ]]; then
    warn "systemd 尚未成为 PID 1，需要重启 WSL。"
    exit 42
  fi
}

install_base_packages() {
  export DEBIAN_FRONTEND=noninteractive
  configure_apt_mirror
  info "正在更新 Ubuntu 软件源。"
  retry apt-get update
  info "正在安装基础依赖。"
  retry apt-get install -y sudo ca-certificates curl git jq unzip zip build-essential pkg-config python3 python3-pip python3-venv python-is-python3
}

configure_apt_mirror() {
  if [[ -z "$APT_MIRROR" ]]; then
    return 0
  fi

  info "正在切换 Ubuntu 软件源镜像：${APT_MIRROR}"
  if compgen -G '/etc/apt/sources.list.d/*.sources' >/dev/null; then
    local source_file
    for source_file in /etc/apt/sources.list.d/*.sources; do
      sed -i -E "s#https?://[^ ]+/ubuntu-ports#${APT_MIRROR}#g; s#https?://[^ ]+/ubuntu#${APT_MIRROR}#g" "$source_file"
    done
  fi
  if [[ -f /etc/apt/sources.list ]]; then
    sed -i -E "s#https?://[^ ]+/ubuntu#${APT_MIRROR}#g; s#https?://security\.ubuntu\.com/ubuntu#${APT_MIRROR}#g; s#https?://archive\.ubuntu\.com/ubuntu#${APT_MIRROR}#g; s#https?://ports\.ubuntu\.com/ubuntu-ports#${APT_MIRROR}#g" /etc/apt/sources.list
  fi
}

ensure_python_toolchain() {
  command -v python3 >/dev/null 2>&1 || fail 'python3 安装失败。'
  command -v python >/dev/null 2>&1 || fail 'python 命令不可用，无法满足原生依赖构建。'
  command -v pip3 >/dev/null 2>&1 || fail 'pip3 安装失败。'
  info "Python 已就绪：$(python3 --version 2>/dev/null || echo unknown)"
}

ensure_nodejs() {
  local need_install=1
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
    if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 22 )); then
      need_install=0
      info "已检测到 Node.js $(node -v)。"
    else
      warn "当前 Node.js 版本过低：$(node -v 2>/dev/null || echo unknown)，准备升级到 22。"
    fi
  fi
  if (( need_install )); then
    install_nodejs_from_tarball
    info "Node.js 安装完成：$(node -v)"
  fi
}

install_nodejs_from_tarball() {
  local arch
  local download_url
  local archive_path="/tmp/node-${NODE_VERSION}.tar.xz"
  local extract_dir="/usr/local/lib/nodejs"
  local node_dir="${extract_dir}/node-${NODE_VERSION}-linux"

  case "$(dpkg --print-architecture 2>/dev/null || uname -m)" in
    amd64|x86_64) arch='x64' ;;
    arm64|aarch64) arch='arm64' ;;
    *) fail "当前架构暂不支持自动安装 Node.js：$(dpkg --print-architecture 2>/dev/null || uname -m)" ;;
  esac

  download_url="${NODE_DIST_MIRROR}/${NODE_VERSION}/node-${NODE_VERSION}-linux-${arch}.tar.xz"
  info "正在从镜像安装 Node.js：${download_url}"
  mkdir -p "$extract_dir"
  retry curl -fL "$download_url" -o "$archive_path"
  rm -rf "$node_dir"
  rm -rf "${extract_dir}/node-${NODE_VERSION}-linux-${arch}"
  tar -xJf "$archive_path" -C "$extract_dir"
  mv "${extract_dir}/node-${NODE_VERSION}-linux-${arch}" "$node_dir"
  ln -sfn "$node_dir/bin/node" /usr/local/bin/node
  ln -sfn "$node_dir/bin/npm" /usr/local/bin/npm
  ln -sfn "$node_dir/bin/npx" /usr/local/bin/npx
  ln -sfn "$node_dir/bin/corepack" /usr/local/bin/corepack
}

ensure_pnpm() {
  if command -v pnpm >/dev/null 2>&1; then
    info "已检测到 pnpm $(pnpm --version)。"
    return 0
  fi
  if command -v corepack >/dev/null 2>&1; then
    info "正在通过 Corepack 启用 pnpm。"
    corepack enable >/dev/null 2>&1 || true
    corepack prepare pnpm@10 --activate >/dev/null 2>&1 || true
  fi
  if ! command -v pnpm >/dev/null 2>&1; then
    info "Corepack 未提供可用的 pnpm，改用 npm 全局安装 pnpm。"
    retry npm install -g pnpm@10
  fi
  command -v pnpm >/dev/null 2>&1 || fail 'pnpm 安装失败。'
  info "pnpm 已就绪：$(pnpm --version)"
}

configure_package_registries() {
  if [[ -z "$NPM_REGISTRY" ]]; then
    return 0
  fi

  info "正在配置 npm/pnpm registry：${NPM_REGISTRY}"
  npm config set registry "$NPM_REGISTRY" >/dev/null
  run_user "npm config set registry \"$NPM_REGISTRY\" >/dev/null"
  run_user "pnpm config set registry \"$NPM_REGISTRY\" >/dev/null"
}

prepare_user_shell() {
  local bashrc="$USER_HOME/.bashrc"
  local profile="$USER_HOME/.profile"
  touch "$bashrc" "$profile"
  if ! grep -Fq 'export PNPM_HOME="$HOME/.local/share/pnpm"' "$profile"; then
    cat >> "$profile" <<'EOF'
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
EOF
  fi
  if ! grep -Fq 'export OPENCLAW_BUNDLED_PLUGINS_DIR="$HOME/openclaw-local-src/extensions"' "$profile"; then
    cat >> "$profile" <<'EOF'
export OPENCLAW_BUNDLED_PLUGINS_DIR="$HOME/openclaw-local-src/extensions"
EOF
  fi
  chown "$APP_USER:$APP_USER" "$bashrc" "$profile"
}

fetch_repo() {
  info "正在拉取 OpenClaw 源码：${REPO_URL} @ ${REPO_REF}"
  rm -rf "$TARGET_DIR"
  retry git init "$TARGET_DIR"
  retry git -C "$TARGET_DIR" remote add origin "$REPO_URL"
  retry git -C "$TARGET_DIR" fetch --depth 1 origin "$REPO_REF"
  git -C "$TARGET_DIR" checkout -f FETCH_HEAD >/dev/null 2>&1
  chown -R "$APP_USER:$APP_USER" "$TARGET_DIR"
}

install_repo_dependencies() {
  info "正在安装 OpenClaw 仓库依赖。"
  run_user "cd \"$TARGET_DIR\" && pnpm config set python /usr/bin/python3 >/dev/null"
  run_user "cd \"$TARGET_DIR\" && pnpm config set store-dir \"$USER_HOME/.pnpm-store\" >/dev/null"
  run_user "set -o pipefail; cd \"$TARGET_DIR\" && pnpm install --reporter=append-only 2>&1 | tee \"$INSTALL_LOG\""
  if grep -Fqi 'Ignored build scripts' "$INSTALL_LOG"; then
    warn '检测到 pnpm 需要审批构建脚本，接下来会打开审批界面。'
    warn '请在界面中批准列出的依赖，然后脚本会继续。'
    run_user "cd \"$TARGET_DIR\" && pnpm approve-builds"
    run_user "cd \"$TARGET_DIR\" && pnpm install --reporter=append-only"
  fi
}

build_repo() {
  info "正在构建前端资源（pnpm ui:build）。"
  run_user "set -o pipefail; cd \"$TARGET_DIR\" && pnpm ui:build 2>&1 | tee \"$UI_BUILD_LOG\""
  info "正在构建 OpenClaw 主项目（pnpm build）。"
  run_user "set -o pipefail; cd \"$TARGET_DIR\" && pnpm build 2>&1 | tee \"$BUILD_LOG\""
  [[ -f "${TARGET_DIR}/dist/index.js" ]] || fail "构建完成但未找到 dist/index.js，构建可能被截断或发生静默错误，请查看日志：${BUILD_LOG}"
  info "构建产物验证通过。"
}

link_cli() {
  info "正在把 openclaw CLI 链接到当前 Linux 用户环境。"
  run_user "cd \"$TARGET_DIR\" && pnpm link --global"
  run_user "openclaw --version"
}

enable_linger() {
  info "正在启用用户 linger，确保未登录时 systemd 用户服务也可运行。"
  loginctl enable-linger "$APP_USER" >/dev/null 2>&1 || warn 'enable-linger 执行失败，可稍后手动运行 sudo loginctl enable-linger "$USER"。'
}

run_onboard() {
  if [[ "$SKIP_ONBOARD" == "1" ]]; then
    info '按参数要求，已跳过 openclaw onboard。'
    return 0
  fi
  info '即将启动 OpenClaw 中文交互配置流程。'
  info '请按界面提示选择模型认证、渠道配置和网关服务安装。'
  run_user "cd \"$TARGET_DIR\" && openclaw onboard --install-daemon"
}

main() {
  configure_network
  ensure_user
  ensure_wsl_conf
  install_base_packages
  ensure_python_toolchain
  ensure_nodejs
  ensure_pnpm
  configure_package_registries
  prepare_user_shell
  fetch_repo
  install_repo_dependencies
  build_repo
  link_cli
  enable_linger
  run_onboard
  info 'WSL 内部署流程已完成。'
}

main "$@"
