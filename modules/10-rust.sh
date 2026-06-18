#!/bin/bash
# DESCRIPTION: Rust 环境配置 — rustup + 清华镜像 + crates.io 镜像

set -e
source "$(dirname "$0")/../common.sh"

# ========== 路径常量 ==========

RUSTUP_HOME="$HOME/.local/opt/rustup"
CARGO_HOME="$HOME/.local/opt/cargo"

export RUSTUP_HOME="$RUSTUP_HOME"
export CARGO_HOME="$CARGO_HOME"

# 清华镜像
export RUSTUP_DIST_SERVER="https://mirrors.tuna.tsinghua.edu.cn/rustup"
export RUSTUP_UPDATE_ROOT="https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup"

# ========== 1. 安装 rustup ==========

if [ -f "$CARGO_HOME/bin/rustup" ]; then
    log_success "rustup 已安装: $CARGO_HOME"
else
    log_info "安装 rustup..."

    # 从清华镜像直接下载 rustup-init 二进制
    RUSTUP_INIT_URL="https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup/dist/x86_64-unknown-linux-gnu/rustup-init"
    TMP_INIT="$(mktemp)"
    if curl -fsSL -o "$TMP_INIT" "$RUSTUP_INIT_URL"; then
        chmod +x "$TMP_INIT"
        # 确保环境变量传递给 rustup-init
        export RUSTUP_HOME="$RUSTUP_HOME"
        export CARGO_HOME="$CARGO_HOME"
        export RUSTUP_DIST_SERVER="https://mirrors.tuna.tsinghua.edu.cn/rustup"
        export RUSTUP_UPDATE_ROOT="https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup"
        "$TMP_INIT" -y --no-modify-path \
            --default-toolchain stable \
            --default-host x86_64-unknown-linux-gnu
        rm -f "$TMP_INIT"
        log_success "rustup 安装完成"
    else
        rm -f "$TMP_INIT"
        log_error "rustup-init 下载失败"
        exit 1
    fi
fi

# 确保 cargo/rustup 在 PATH 中
export PATH="$CARGO_HOME/bin:$PATH"

# ========== 2. 安装/更新 stable 工具链 ==========

log_info "检查 Rust stable 工具链..."
rustup install stable 2>/dev/null || true
rustup default stable 2>/dev/null || true
log_success "Rust stable: $(rustc --version)"

# ========== 3. 配置 crates.io 镜像 ==========

log_info "配置 crates.io 清华镜像..."

CARGO_CONFIG_DIR="$CARGO_HOME"
mkdir -p "$CARGO_CONFIG_DIR"

CARGO_CONFIG_FILE="$CARGO_CONFIG_DIR/config.toml"
CARGO_CONFIG_CONTENT="[source.crates-io]
replace-with = 'tuna'

[source.tuna]
registry = 'https://mirrors.tuna.tsinghua.edu.cn/crates.io-index'"

if [ ! -f "$CARGO_CONFIG_FILE" ] || ! grep -qF "mirrors.tuna.tsinghua.edu.cn/crates.io-index" "$CARGO_CONFIG_FILE" 2>/dev/null; then
    if [ -f "$CARGO_CONFIG_FILE" ]; then
        # 追加镜像配置
        echo "" >> "$CARGO_CONFIG_FILE"
        echo "[source.crates-io]" >> "$CARGO_CONFIG_FILE"
        echo "replace-with = 'tuna'" >> "$CARGO_CONFIG_FILE"
        echo "" >> "$CARGO_CONFIG_FILE"
        echo "[source.tuna]" >> "$CARGO_CONFIG_FILE"
        echo "registry = 'https://mirrors.tuna.tsinghua.edu.cn/crates.io-index'" >> "$CARGO_CONFIG_FILE"
    else
        echo "$CARGO_CONFIG_CONTENT" > "$CARGO_CONFIG_FILE"
    fi
    log_success "crates.io 镜像已配置"
else
    log_success "crates.io 镜像已是最新"
fi

# ========== 4. 环境变量 ==========

log_info "配置 Rust shell 环境..."

RUST_ENV_FILE="$HOME/.bashrc.d/rust.sh"
mkdir -p "$HOME/.bashrc.d"

RUST_ENV_CONTENT="# Rust environment (managed by homelab setup)
export RUSTUP_HOME=\"$RUSTUP_HOME\"
export CARGO_HOME=\"$CARGO_HOME\"
export PATH=\"\$CARGO_HOME/bin:\$PATH\"
export RUSTUP_DIST_SERVER=\"https://mirrors.tuna.tsinghua.edu.cn/rustup\"
export RUSTUP_UPDATE_ROOT=\"https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup\""

if [ ! -f "$RUST_ENV_FILE" ] || [ "$(cat "$RUST_ENV_FILE")" != "$RUST_ENV_CONTENT" ]; then
    echo "$RUST_ENV_CONTENT" > "$RUST_ENV_FILE"
    log_success "Rust 环境变量已写入 $RUST_ENV_FILE"
else
    log_success "Rust 环境变量已是最新"
fi

ensure_bashrc_d_loader

# ========== 5. 升级 ==========

log_info "检查 rustup 升级..."
rustup update stable 2>/dev/null || true

# ========== 验证 ==========

echo ""
log_info "rustup: $(rustup --version 2>/dev/null | head -n1)"
log_info "rustc: $(rustc --version)"
log_info "cargo: $(cargo --version)"
log_info "工具链: $(rustup show active-toolchain 2>/dev/null)"
log_info "crates.io 镜像: 清华源"
log_success "Rust 环境配置完成"
