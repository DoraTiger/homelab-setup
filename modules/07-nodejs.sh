#!/bin/bash
# DESCRIPTION: Node.js 环境配置 — fnm 版本管理 + npmmirror 加速

set -e
source "$(dirname "$0")/../common.sh"

# ========== 禁止 root ==========

if [ "$EUID" -eq 0 ]; then
    log_error "禁止以 root 身份运行 Node.js 安装"
    exit 1
fi

# ========== 路径常量 ==========

FNM_DIR="$HOME/.local/opt/fnm"
NPM_CACHE_DIR="$CACHE_DIR/npm"
NPM_PREFIX_DIR="$HOME/.local/npm-global"
TARGET_NODE_VERSION="lts/*"

mkdir -p "$NPM_CACHE_DIR" "$NPM_PREFIX_DIR"

# ========== 1. 安装 fnm ==========

if [ -f "$FNM_DIR/fnm" ]; then
    log_success "fnm 已安装: $FNM_DIR"

    # 升级 fnm：重新下载安装脚本覆盖（幂等）
    log_info "检查 fnm 升级..."
    FNM_SCRIPT_URL="https://raw.githubusercontent.com/Schniz/fnm/refs/heads/master/.ci/install.sh"
    TMP_SCRIPT="$(mktemp)"
    OLD_VER=$("$FNM_DIR/fnm" --version 2>/dev/null)
    if run_with_optional_proxy curl -fsSL "$FNM_SCRIPT_URL" -o "$TMP_SCRIPT" 2>/dev/null; then
        bash "$TMP_SCRIPT" --install-dir "$FNM_DIR" --skip-shell >/dev/null 2>&1
        NEW_VER=$("$FNM_DIR/fnm" --version 2>/dev/null)
        rm -f "$TMP_SCRIPT"
        if [ "$OLD_VER" != "$NEW_VER" ]; then
            log_success "fnm 已升级: $OLD_VER → $NEW_VER"
        else
            log_success "fnm 已是最新版本"
        fi
    else
        rm -f "$TMP_SCRIPT" 2>/dev/null
        log_warn "fnm 升级脚本下载失败，保持当前版本: $OLD_VER"
    fi
else
    log_info "安装 fnm..."
    FNM_SCRIPT_URL="https://raw.githubusercontent.com/Schniz/fnm/refs/heads/master/.ci/install.sh"
    TMP_SCRIPT="$(mktemp)"

    if ! run_with_optional_proxy curl -fsSL "$FNM_SCRIPT_URL" -o "$TMP_SCRIPT"; then
        log_error "下载 fnm 安装脚本失败"
        rm -f "$TMP_SCRIPT" 2>/dev/null
        exit 1
    fi

    bash "$TMP_SCRIPT" --install-dir "$FNM_DIR" --skip-shell
    rm -f "$TMP_SCRIPT"

    export PATH="$FNM_DIR:$PATH"

    if ! command -v fnm &>/dev/null; then
        log_error "fnm 安装后不可用，请检查 $FNM_DIR"
        exit 1
    fi

    log_success "fnm 安装完成"
fi

export FNM_DIR="$FNM_DIR"
export PATH="$FNM_DIR:$PATH"
eval "$(fnm env --use-on-cd 2>/dev/null)" || true

# ========== 2. 安装 Node.js ==========

log_info "检查 Node.js..."

# 获取已安装版本列表（排除 system）
INSTALLED_VERSIONS=$(fnm list 2>/dev/null | grep -v "system" | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+" || echo "")

if [ -z "$INSTALLED_VERSIONS" ]; then
    NEED_INSTALL=true
else
    NEED_INSTALL=false
fi

if [ "$NEED_INSTALL" = true ]; then
    log_info "安装 Node.js $TARGET_NODE_VERSION（使用 npmmirror 加速）..."
    FNM_NODE_DIST_MIRROR="https://npmmirror.com/mirrors/node" \
        fnm install "$TARGET_NODE_VERSION"
else
    # 已安装 → 升级到最新 LTS
    log_info "检查 Node.js 升级..."
    FNM_NODE_DIST_MIRROR="https://npmmirror.com/mirrors/node" \
        fnm install "$TARGET_NODE_VERSION" 2>/dev/null || true
    fnm upgrade 2>/dev/null || true
fi

CURRENT_VERSION=$(fnm current 2>/dev/null || echo "")
DEFAULT_VERSION=$(fnm default 2>/dev/null || echo "")

if [ "$CURRENT_VERSION" != "$TARGET_NODE_VERSION" ] || [ "$DEFAULT_VERSION" != "$TARGET_NODE_VERSION" ]; then
    fnm use "$TARGET_NODE_VERSION"
    fnm default "$TARGET_NODE_VERSION"
    log_success "Node.js 默认版本已设为 $TARGET_NODE_VERSION"
else
    log_success "Node.js 已是目标版本: $TARGET_NODE_VERSION"
fi

# ========== 3. 配置 npm ==========

log_info "配置 npm..."

npm config set prefix "$NPM_PREFIX_DIR" 2>/dev/null
npm config set cache "$NPM_CACHE_DIR" 2>/dev/null
npm config set registry https://registry.npmmirror.com 2>/dev/null

# 升级 npm 到最新版
log_info "检查 npm 升级..."
npm install -g npm@latest 2>/dev/null || true

# ========== 4. 环境变量 ==========

log_info "配置 Node.js shell 环境..."

NODE_ENV_FILE="$HOME/.bashrc.d/nodejs.sh"
mkdir -p "$HOME/.bashrc.d"

NODE_ENV_CONTENT="# Node.js environment (managed by homelab setup)
export FNM_DIR=\"$FNM_DIR\"
export PATH=\"\$FNM_DIR:\$PATH\"
eval \"\$(fnm env --use-on-cd)\" >/dev/null 2>&1
export PATH=\"$NPM_PREFIX_DIR/bin:\$PATH\""

if [ ! -f "$NODE_ENV_FILE" ] || [ "$(cat "$NODE_ENV_FILE")" != "$NODE_ENV_CONTENT" ]; then
    echo "$NODE_ENV_CONTENT" > "$NODE_ENV_FILE"
    log_success "Node.js 环境变量已写入 $NODE_ENV_FILE"
else
    log_success "Node.js 环境变量已是最新"
fi

ensure_bashrc_d_loader

# ========== 5. 验证 ==========

export PATH="$FNM_DIR:$NPM_PREFIX_DIR/bin:$PATH"
eval "$(fnm env --use-on-cd 2>/dev/null)" || true

echo ""
log_info "Node.js: $(node -v 2>/dev/null)"
log_info "npm: $(npm -v 2>/dev/null)"
log_info "npm 全局模块: $NPM_PREFIX_DIR"
log_info "npm 缓存: $NPM_CACHE_DIR"
log_info "Registry: $(npm config get registry 2>/dev/null)"
log_success "Node.js 环境配置完成"
