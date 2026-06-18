#!/bin/bash
# DESCRIPTION: Golang 环境配置 — 多版本管理 + GOPROXY 国内加速

set -e
source "$(dirname "$0")/../common.sh"

# ========== 禁止 root ==========

if [ "$EUID" -eq 0 ]; then
    log_error "禁止以 root 身份运行 Go 安装"
    exit 1
fi

# ========== 路径常量 ==========

GO_VERSIONS_DIR="$HOME/.local/opt/go/versions"
GO_CURRENT_LINK="$HOME/.local/opt/go/current"
GO_CACHE_DIR="$CACHE_DIR/go"
GO_PKG_DIR="$PACKAGES_DIR/golang"

mkdir -p "$GO_VERSIONS_DIR" "$GO_CACHE_DIR" "$GO_PKG_DIR"

# ========== 获取最新版本 ==========

log_info "检测 Go 最新版本..."

LATEST_GO_VERSION=""
if command -v timeout &>/dev/null; then
    LATEST_GO_VERSION=$(run_with_optional_proxy timeout 8s wget -qO- "https://go.dev/VERSION?m=text" 2>/dev/null | head -n1)
else
    LATEST_GO_VERSION=$(run_with_optional_proxy wget -qO- --timeout=8 "https://go.dev/VERSION?m=text" 2>/dev/null | head -n1)
fi
# go.dev 返回 "go1.26.4"，去掉 go 前缀
LATEST_GO_VERSION="${LATEST_GO_VERSION#go}"

# 扫描本地缓存的安装包
CACHED_LATEST=""
if ls "$GO_PKG_DIR"/go[0-9]*.linux-amd64.tar.gz &>/dev/null; then
    CACHED_LATEST=$(ls "$GO_PKG_DIR"/go[0-9]*.linux-amd64.tar.gz 2>/dev/null | \
        sed 's|.*/go\([0-9.]*\)\.linux-amd64\.tar\.gz|\1|' | sort -Vr | head -n1)
fi

# 确定目标版本
TARGET_VERSION=""
USE_CACHED=false

if [ -n "$LATEST_GO_VERSION" ]; then
    TARGET_VERSION="$LATEST_GO_VERSION"
elif [ -n "$CACHED_LATEST" ]; then
    log_warn "无法连接 go.dev，使用本地缓存版本: $CACHED_LATEST"
    TARGET_VERSION="$CACHED_LATEST"
    USE_CACHED=true
else
    log_error "无网络且 packages/golang/ 中无 Go 安装包"
    exit 1
fi

log_info "目标版本: $TARGET_VERSION"

# ========== 安装 ==========

TARGET_INSTALL_DIR="$GO_VERSIONS_DIR/$TARGET_VERSION"

if [ ! -d "$TARGET_INSTALL_DIR" ]; then
    GO_TAR_FILE="$GO_PKG_DIR/go${TARGET_VERSION}.linux-amd64.tar.gz"

    if [ "$USE_CACHED" = false ] && [ ! -f "$GO_TAR_FILE" ]; then
        log_info "下载 Go $TARGET_VERSION ..."
        DOWNLOAD_URL="https://dl.google.com/go/go${TARGET_VERSION}.linux-amd64.tar.gz"
        if ! run_with_optional_proxy wget -q --show-progress -O "$GO_TAR_FILE" "$DOWNLOAD_URL"; then
            if [ -n "$CACHED_LATEST" ]; then
                log_warn "下载失败，回退到缓存版本: $CACHED_LATEST"
                TARGET_VERSION="$CACHED_LATEST"
                GO_TAR_FILE="$GO_PKG_DIR/go${CACHED_LATEST}.linux-amd64.tar.gz"
            else
                log_error "下载失败且无缓存"
                rm -f "$GO_TAR_FILE"
                exit 1
            fi
        fi
    fi

    if [ ! -f "$GO_TAR_FILE" ]; then
        log_error "找不到安装包: $GO_TAR_FILE"
        exit 1
    fi

    log_info "安装 Go $TARGET_VERSION ..."
    mkdir -p "$TARGET_INSTALL_DIR"
    tar -C "$TARGET_INSTALL_DIR" --strip-components=1 -xzf "$GO_TAR_FILE"
    log_success "Go $TARGET_VERSION 安装完成"
else
    log_info "Go $TARGET_VERSION 已存在，跳过安装"
fi

# ========== 更新 current 软链接 ==========

CURRENT_TARGET=$(readlink -f "$GO_CURRENT_LINK" 2>/dev/null)
if [ "$CURRENT_TARGET" != "$TARGET_INSTALL_DIR" ]; then
    rm -f "$GO_CURRENT_LINK"
    ln -s "$TARGET_INSTALL_DIR" "$GO_CURRENT_LINK"
    log_info "已切换到 Go $TARGET_VERSION"
else
    log_success "当前已是 Go $TARGET_VERSION"
fi

# ========== 配置环境变量 ==========

GO_ENV_FILE="$HOME/.bashrc.d/go.sh"
mkdir -p "$HOME/.bashrc.d"

GO_ENV_CONTENT="# Go environment (managed by homelab setup)
export GOROOT=\"$GO_CURRENT_LINK\"
export GOPATH=\"$GO_CACHE_DIR\"
export GOBIN=\"\$GOPATH/bin\"
export PATH=\"\$GOROOT/bin:\$GOBIN:\$PATH\"
export GOPROXY=https://goproxy.cn,direct
export GOMODCACHE=\"\$GOPATH/mod\"
export GOCACHE=\"\$GOPATH/build\""

if [ ! -f "$GO_ENV_FILE" ] || [ "$(cat "$GO_ENV_FILE")" != "$GO_ENV_CONTENT" ]; then
    echo "$GO_ENV_CONTENT" > "$GO_ENV_FILE"
    log_success "环境变量已写入 $GO_ENV_FILE"
else
    log_success "环境变量已是最新"
fi

# 确保 .bashrc 加载 .bashrc.d/
ensure_bashrc_d_loader

# 当前 session 立即生效
export GOROOT="$GO_CURRENT_LINK"
export GOPATH="$GO_CACHE_DIR"
export GOBIN="$GOPATH/bin"
export PATH="$GOROOT/bin:$GOBIN:$PATH"
export GOPROXY=https://goproxy.cn,direct
export GOMODCACHE="$GOPATH/mod"
export GOCACHE="$GOPATH/build"

echo ""
log_success "Go 环境配置完成"
"$GO_CURRENT_LINK/bin/go" version | sed 's/^/    /'
