#!/bin/bash
# DESCRIPTION: code-server 安装 — 官方 GitHub Deb 包

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MODULE_DIR/../common.sh"
source "$MODULE_DIR/../lib/code-server-install.sh"

CODE_SERVER_RELEASE_API="https://api.github.com/repos/coder/code-server/releases/latest"
CODE_SERVER_PACKAGE_DIR="$PACKAGES_DIR/code-server"

install_code_server() {
    local architecture cached_deb release_json deb_url deb_file

    ensure_sudo
    mkdir -p "$CODE_SERVER_PACKAGE_DIR"
    architecture="$(dpkg --print-architecture)"
    case "$architecture" in
        amd64|arm64) ;;
        *) log_error "code-server 暂不支持当前架构: $architecture"; return 1 ;;
    esac

    cached_deb="$(find_latest_valid_package "$CODE_SERVER_PACKAGE_DIR" \
        "code-server_*_${architecture}.deb" validate_deb_package || true)"

    if [ -n "$cached_deb" ] && ! upgrade_requested; then
        deb_file="$cached_deb"
        log_info "使用缓存的安装包: $deb_file"
    else
        release_json="$(run_with_optional_proxy curl -fsSL "$CODE_SERVER_RELEASE_API" 2>/dev/null || true)"
        deb_url="$(printf '%s\n' "$release_json" | code_server_deb_url_from_release_json "$architecture" || true)"
        if [ -n "$deb_url" ]; then
            deb_file="$CODE_SERVER_PACKAGE_DIR/${deb_url##*/}"
            if ! download_package "$deb_url" "$deb_file" validate_deb_package; then
                [ -n "$cached_deb" ] || return 1
                log_warn "新版下载失败，回退到缓存安装包: $cached_deb"
                deb_file="$cached_deb"
            fi
        elif [ -n "$cached_deb" ]; then
            log_warn "无法获取最新版本，回退到缓存安装包: $cached_deb"
            deb_file="$cached_deb"
        else
            log_error "无法获取 code-server Deb 下载地址，且本地无有效缓存"
            return 1
        fi
    fi

    sudo apt-get install -y "$deb_file"
}

code_server_bin="$(command -v code-server 2>/dev/null || true)"
if [ -n "$code_server_bin" ]; then
    log_success "code-server 已安装: $(code_server_version "$code_server_bin")"
    if upgrade_requested; then
        log_info "升级模式已开启，检查 code-server 官方 Deb 包..."
        install_code_server
    else
        log_info "默认模式保留现有 code-server 版本"
    fi
else
    log_info "安装 code-server..."
    install_code_server
fi

code_server_bin="$(command -v code-server 2>/dev/null || true)"
[ -n "$code_server_bin" ] || { log_error "code-server 安装后不可用"; exit 1; }
log_info "code-server: $(code_server_version "$code_server_bin")"
log_success "code-server 安装完成"
service_user="${USER:-$(id -un)}"
render_code_server_next_steps "$service_user"
