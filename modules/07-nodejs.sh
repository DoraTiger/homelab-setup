#!/bin/bash
# DESCRIPTION: Node.js 环境配置 — fnm 版本管理 + npmmirror 加速

set -e
source "$(dirname "$0")/../common.sh"
source "$(dirname "$0")/../lib/nodejs-env.sh"

# ========== 禁止 root ==========

if [ "$EUID" -eq 0 ]; then
    log_error "禁止以 root 身份运行 Node.js 安装"
    exit 1
fi

# ========== 路径常量 ==========

FNM_INSTALL_DIR="$HOME/.local/opt/fnm"
FNM_DATA_DIR="$HOME/.local/share/fnm"
FNM_PACKAGE_DIR="$PACKAGES_DIR/fnm"
FNM_INSTALLER="$FNM_PACKAGE_DIR/install.sh"
NPM_CACHE_DIR="$CACHE_DIR/npm"
NPM_PREFIX_DIR="$HOME/.local/npm-global"
TARGET_NODE_VERSION="lts/*"

mkdir -p "$FNM_INSTALL_DIR" "$FNM_DATA_DIR" "$FNM_PACKAGE_DIR" "$NPM_CACHE_DIR" "$NPM_PREFIX_DIR"

if [ -e "$FNM_INSTALL_DIR/node-versions" ] || [ -e "$FNM_INSTALL_DIR/aliases" ]; then
    FNM_LEGACY_BACKUP="$HOME/.local/opt/fnm-legacy-data-$(date +%Y%m%d%H%M%S)"
    log_info "检测到旧版 fnm 数据目录，迁移到: $FNM_LEGACY_BACKUP"
    migrate_legacy_fnm_data "$FNM_INSTALL_DIR" "$FNM_DATA_DIR" "$FNM_LEGACY_BACKUP"
    log_success "旧版 fnm 数据已备份，规范数据目录保持为: $FNM_DATA_DIR"
fi

# ========== 1. 安装 fnm ==========

if [ -f "$FNM_INSTALL_DIR/fnm" ]; then
    log_success "fnm 已安装: $FNM_INSTALL_DIR"

    if upgrade_requested; then
        # fnm 官方安装器负责原位更新可执行文件，不迁移版本数据目录。
        log_info "升级模式已开启，检查 fnm..."
        FNM_SCRIPT_URL="https://raw.githubusercontent.com/Schniz/fnm/refs/heads/master/.ci/install.sh"
        OLD_VER=$("$FNM_INSTALL_DIR/fnm" --version 2>/dev/null)
        if download_package "$FNM_SCRIPT_URL" "$FNM_INSTALLER" validate_shell_script 2>/dev/null; then
            if run_with_optional_proxy bash "$FNM_INSTALLER" --install-dir "$FNM_INSTALL_DIR" --skip-shell >/dev/null 2>&1; then
                NEW_VER=$("$FNM_INSTALL_DIR/fnm" --version 2>/dev/null)
                log_success "fnm 升级检查完成: $OLD_VER → $NEW_VER"
            else
                log_warn "fnm 升级失败，保留当前版本: $OLD_VER"
            fi
        else
            log_warn "fnm 升级脚本下载失败，保持当前版本: $OLD_VER"
        fi
    else
        log_info "默认模式保留现有 fnm 版本"
    fi
else
    log_info "安装 fnm..."
    FNM_SCRIPT_URL="https://raw.githubusercontent.com/Schniz/fnm/refs/heads/master/.ci/install.sh"
    if ! download_package "$FNM_SCRIPT_URL" "$FNM_INSTALLER" validate_shell_script; then
        log_error "下载 fnm 安装脚本失败"
        exit 1
    fi

    run_with_optional_proxy bash "$FNM_INSTALLER" --install-dir "$FNM_INSTALL_DIR" --skip-shell

    export PATH="$FNM_INSTALL_DIR:$PATH"

    if ! command -v fnm &>/dev/null; then
        log_error "fnm 安装后不可用，请检查 $FNM_INSTALL_DIR"
        exit 1
    fi

    log_success "fnm 安装完成"
fi

export FNM_INSTALL_DIR="$FNM_INSTALL_DIR"
export FNM_DIR="$FNM_DATA_DIR"
export PATH="$FNM_INSTALL_DIR:$PATH"
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
elif upgrade_requested; then
    log_info "升级模式已开启，检查 Node.js LTS..."
    FNM_NODE_DIST_MIRROR="https://npmmirror.com/mirrors/node" \
        fnm install "$TARGET_NODE_VERSION" 2>/dev/null || true
    fnm upgrade 2>/dev/null || true
else
    log_info "默认模式保留现有 Node.js 版本"
fi

DEFAULT_NODE_LINK="$FNM_DATA_DIR/aliases/default"
if [ ! -L "$DEFAULT_NODE_LINK" ] || [ ! -x "$DEFAULT_NODE_LINK/bin/node" ]; then
    fnm default "$TARGET_NODE_VERSION"
    log_success "Node.js 默认版本已设为 $TARGET_NODE_VERSION"
else
    log_success "Node.js 默认版本链接有效"
fi
export PATH="$DEFAULT_NODE_LINK/bin:$PATH"

# ========== 3. 配置 npm ==========

log_info "配置 npm..."

npm_config_set_if_needed() {
    local key="$1" expected="$2" current
    current=$(npm config get "$key" 2>/dev/null || echo "")
    [ "$current" = "$expected" ] || npm config set "$key" "$expected"
}

npm_config_set_if_needed prefix "$NPM_PREFIX_DIR"
npm_config_set_if_needed cache "$NPM_CACHE_DIR"
npm_config_set_if_needed registry https://registry.npmmirror.com

if upgrade_requested; then
    log_info "升级模式已开启，更新 npm..."
    npm install -g npm@latest 2>/dev/null || log_warn "npm 升级失败，保留当前版本"
fi

# ========== 4. 环境变量 ==========

log_info "配置 Node.js shell 环境..."

NODE_ENV_FILE="$HOME/.bashrc.d/nodejs.sh"
mkdir -p "$HOME/.bashrc.d"

NODE_PROFILE_CONTENT="$(render_nodejs_profile_env "$HOME")"
write_profile_env_file nodejs "$NODE_PROFILE_CONTENT"

NODE_ENV_CONTENT="$(render_nodejs_interactive_env)"

if [ ! -f "$NODE_ENV_FILE" ] || [ "$(cat "$NODE_ENV_FILE")" != "$NODE_ENV_CONTENT" ]; then
    echo "$NODE_ENV_CONTENT" > "$NODE_ENV_FILE"
    log_success "Node.js 环境变量已写入 $NODE_ENV_FILE"
else
    log_success "Node.js 环境变量已是最新"
fi

ensure_bashrc_d_loader

# ========== 5. 验证 ==========

export PATH="$FNM_INSTALL_DIR:$NPM_PREFIX_DIR/bin:$PATH"
eval "$(fnm env --use-on-cd 2>/dev/null)" || true

echo ""
log_info "Node.js: $(node -v 2>/dev/null)"
log_info "npm: $(npm -v 2>/dev/null)"
log_info "npm 全局模块: $NPM_PREFIX_DIR"
log_info "npm 缓存: $NPM_CACHE_DIR"
log_info "Registry: $(npm config get registry 2>/dev/null)"
log_success "Node.js 环境配置完成"
