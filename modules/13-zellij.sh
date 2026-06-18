#!/bin/bash
# DESCRIPTION: Zellij 终端复用器安装 — 预编译二进制 + 配置

set -e
source "$(dirname "$0")/../common.sh"

# ========== 路径常量 ==========

ZELLJ_DIR="$HOME/.local/opt/zellij"
ZELLJ_PKG_DIR="$PACKAGES_DIR/zellij"

mkdir -p "$ZELLJ_PKG_DIR"

# ========== 安装 Zellij ==========

if [ -f "$ZELLJ_DIR/zellij" ]; then
    log_success "Zellij 已安装: $ZELLJ_DIR"
else
    log_info "安装 Zellij..."

    # 从 GitHub Releases 下载预编译二进制（musl 静态链接，无依赖）
    ZELLJ_URL="https://github.com/zellij-org/zellij/releases/latest/download/zellij-x86_64-unknown-linux-musl.tar.gz"
    ZELLJ_TAR="$ZELLJ_PKG_DIR/zellij-x86_64-unknown-linux-musl.tar.gz"

    if [ ! -f "$ZELLJ_TAR" ]; then
        log_info "下载 Zellij..."
        run_with_optional_proxy curl -fsSL -o "$ZELLJ_TAR" "$ZELLJ_URL"
        log_success "安装包已缓存: $ZELLJ_TAR"
    else
        log_info "使用缓存的安装包: $ZELLJ_TAR"
    fi

    mkdir -p "$ZELLJ_DIR"
    tar -xzf "$ZELLJ_TAR" -C "$ZELLJ_DIR"
    chmod +x "$ZELLJ_DIR/zellij"

    if ! "$ZELLJ_DIR/zellij" --version &>/dev/null; then
        log_error "Zellij 安装验证失败"
        exit 1
    fi

    log_success "Zellij 安装完成"
fi

# ========== 升级 ==========

log_info "检查 Zellij 升级..."
ZELLJ_LATEST_URL="https://github.com/zellij-org/zellij/releases/latest/download/zellij-x86_64-unknown-linux-musl.tar.gz"
OLD_VER=$("$ZELLJ_DIR/zellij" --version 2>/dev/null | head -n1)

# 下载到临时文件比对版本
TMP_TAR="$(mktemp)"
if run_with_optional_proxy curl -fsSL -o "$TMP_TAR" "$ZELLJ_LATEST_URL" 2>/dev/null; then
    TMP_DIR="$(mktemp -d)"
    tar -xzf "$TMP_TAR" -C "$TMP_DIR" 2>/dev/null
    if [ -f "$TMP_DIR/zellij" ]; then
        NEW_VER=$("$TMP_DIR/zellij" --version 2>/dev/null | head -n1)
        if [ "$OLD_VER" != "$NEW_VER" ]; then
            rm -f "$ZELLJ_DIR/zellij"
            mv "$TMP_DIR/zellij" "$ZELLJ_DIR/zellij"
            chmod +x "$ZELLJ_DIR/zellij"
            # 更新缓存
            mv "$TMP_TAR" "$ZELLJ_PKG_DIR/zellij-x86_64-unknown-linux-musl.tar.gz"
            log_success "Zellij 已升级: $OLD_VER → $NEW_VER"
        else
            log_success "Zellij 已是最新版本: $OLD_VER"
        fi
        rm -rf "$TMP_DIR"
    fi
else
    log_warn "Zellij 升级检查失败，保持当前版本: $OLD_VER"
fi
rm -f "$TMP_TAR"

# ========== 配置 ==========

log_info "配置 Zellij..."

ZELLJ_CONFIG_DIR="$HOME/.config/zellij"
mkdir -p "$ZELLJ_CONFIG_DIR"

# 默认配置
ZELLJ_CONFIG_FILE="$ZELLJ_CONFIG_DIR/config.kdl"
if [ ! -f "$ZELLJ_CONFIG_FILE" ]; then
    cat > "$ZELLJ_CONFIG_FILE" <<'EOF'
default_shell "bash"

keybindings {
    unbind "Ctrl b"
    unbind "Ctrl o"
}

theme "dracula"
EOF
    log_success "Zellij 默认配置已写入"
else
    log_success "Zellij 配置已存在"
fi

# ========== 符号链接到 ~/.local/bin ==========

LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

if [ -L "$LOCAL_BIN/zellij" ] && [ "$(readlink "$LOCAL_BIN/zellij")" = "$ZELLJ_DIR/zellij" ]; then
    log_success "符号链接已存在: $LOCAL_BIN/zellij"
else
    ln -sf "$ZELLJ_DIR/zellij" "$LOCAL_BIN/zellij"
    log_success "符号链接已创建: $LOCAL_BIN/zellij → $ZELLJ_DIR/zellij"
fi

# ========== 别名配置 ==========

log_info "配置 Zellij 别名..."

ZELLJ_ALIAS_FILE="$HOME/.bashrc.d/zellij.sh"
mkdir -p "$HOME/.bashrc.d"

ZELLJ_ALIAS_CONTENT='alias zj="zellij"
alias zjl="zellij list-sessions"    # 快速列出所有会话
alias zja="zellij attach"           # 快速附加到已有会话
alias zjn="zellij -s"               # 快速新建命名会话'

if [ ! -f "$ZELLJ_ALIAS_FILE" ] || [ "$(cat "$ZELLJ_ALIAS_FILE")" != "$ZELLJ_ALIAS_CONTENT" ]; then
    echo "$ZELLJ_ALIAS_CONTENT" > "$ZELLJ_ALIAS_FILE"
    log_success "Zellij 别名已写入 $ZELLJ_ALIAS_FILE"
else
    log_success "Zellij 别名已是最新"
fi

# ========== 验证 ==========

export PATH="$ZELLJ_DIR:$PATH"
echo ""
log_info "Zellij: $("$ZELLJ_DIR/zellij" --version 2>/dev/null)"
log_info "安装目录: $ZELLJ_DIR"
log_info "配置文件: $ZELLJ_CONFIG_FILE"
log_success "Zellij 配置完成"
