#!/bin/bash
# DESCRIPTION: code-server 安装 — 官方 Debian 安装脚本

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MODULE_DIR/../common.sh"
source "$MODULE_DIR/../lib/code-server-install.sh"

CODE_SERVER_INSTALL_URL="https://code-server.dev/install.sh"

install_code_server() {
    local install_dir installer curl_home

    ensure_sudo
    # 官方脚本先下载到临时文件，下载成功后再执行，避免 curl | sh 在网络
    # 中断时执行不完整内容。Debian 上官方脚本会选择 deb 包安装方式。
    install_dir="$(mktemp -d)"
    installer="$install_dir/install.sh"
    curl_home="$install_dir/curl-home"
    if ! run_with_optional_proxy curl -fsSL "$CODE_SERVER_INSTALL_URL" -o "$installer"; then
        rm -rf "$install_dir"
        log_error "code-server 官方安装脚本下载失败"
        return 1
    fi
    prepare_code_server_curl_config "$curl_home"
    if ! CURL_HOME="$curl_home" timeout 900 sh "$installer"; then
        rm -rf "$install_dir"
        log_error "code-server 安装失败"
        return 1
    fi
    rm -rf "$install_dir"
}

code_server_bin="$(command -v code-server 2>/dev/null || true)"
if [ -n "$code_server_bin" ]; then
    log_success "code-server 已安装: $(code_server_version "$code_server_bin")"
    if upgrade_requested; then
        log_info "升级模式已开启，执行 code-server 官方安装器..."
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
