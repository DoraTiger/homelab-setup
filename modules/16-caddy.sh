#!/bin/bash
# DESCRIPTION: Caddy 安装 — 官方 Debian 包 + AliDNS DNS Provider

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MODULE_DIR/../common.sh"
source "$MODULE_DIR/../lib/caddy-install.sh"

CADDY_GPG_URL="https://dl.cloudsmith.io/public/caddy/stable/gpg.key"
CADDY_APT_URL="https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt"
CADDY_KEYRING="/usr/share/keyrings/caddy-stable-archive-keyring.gpg"
CADDY_SOURCE_LIST="/etc/apt/sources.list.d/caddy-stable.list"
CADDY_PLUGIN="github.com/caddy-dns/alidns"
CADDY_ARCHITECTURE="$(dpkg --print-architecture)"
CADDY_PACKAGE_DIR="$PACKAGES_DIR/caddy"
CADDY_CACHED_BINARY="$CADDY_PACKAGE_DIR/caddy-custom-alidns-$CADDY_ARCHITECTURE"
mkdir -p "$CADDY_PACKAGE_DIR"

install_caddy_package() {
    local temp_dir

    ensure_sudo
    sudo apt-get update -y
    sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gpg

    # 先在用户可写的临时目录验证下载内容，再安装到系统路径；不通过管道
    # 直接执行远端响应，也不在仓库中持久化软件源文件。
    temp_dir="$(mktemp -d)"
    run_with_optional_proxy curl -1sLf "$CADDY_GPG_URL" -o "$temp_dir/caddy.gpg.key"
    gpg --dearmor --yes -o "$temp_dir/caddy.gpg" "$temp_dir/caddy.gpg.key"
    run_with_optional_proxy curl -1sLf "$CADDY_APT_URL" -o "$temp_dir/caddy-stable.list"
    sudo install -m 644 -o root -g root "$temp_dir/caddy.gpg" "$CADDY_KEYRING"
    sudo install -m 644 -o root -g root "$temp_dir/caddy-stable.list" "$CADDY_SOURCE_LIST"
    rm -rf "$temp_dir"

    sudo apt-get update -y
    sudo apt-get install -y caddy
}

resolve_xcaddy() {
    local go_bin_dir go_path

    if command -v xcaddy >/dev/null 2>&1; then
        command -v xcaddy
        return 0
    fi
    go_bin_dir="$(go env GOBIN)"
    if [ -z "$go_bin_dir" ]; then
        go_path="$(go env GOPATH)"
        go_bin_dir="${go_path%%:*}/bin"
    fi
    [ -x "$go_bin_dir/xcaddy" ] || return 1
    printf '%s\n' "$go_bin_dir/xcaddy"
}

validate_caddy_build_prerequisites() {
    local go_version
    if ! command -v go >/dev/null 2>&1; then
        log_error "构建 AliDNS Provider 需要 Go，请先执行 05-golang.sh"
        return 1
    fi
    go_version="$(go env GOVERSION 2>/dev/null || true)"
    if ! caddy_go_version_supported "$go_version"; then
        log_error "构建 Caddy 需要 Go 1.25 或更高版本，当前为: ${go_version:-unknown}"
        log_info "请先执行: bash init.sh --silent --upgrade 05"
        return 1
    fi
}

install_alidns_caddy_binary() {
    local source_binary="$1" current_diversion

    caddy_binary_has_alidns "$source_binary" || { log_error "缓存的 Caddy 缺少 AliDNS Provider"; return 1; }

    ensure_sudo
    # 官方包负责 systemd、用户、目录和补全；自定义二进制通过 Debian 官方
    # 推荐的 diversion/alternatives 方式接管，避免软件包升级直接覆盖。
    current_diversion="$(dpkg-divert --list /usr/bin/caddy 2>/dev/null || true)"
    if [ -z "$current_diversion" ]; then
        sudo dpkg-divert --divert /usr/bin/caddy.default --rename /usr/bin/caddy
    elif ! grep -qF '/usr/bin/caddy.default' <<< "$current_diversion"; then
        log_error "检测到未知的 /usr/bin/caddy diversion，拒绝覆盖"
        return 1
    fi

    sudo install -m 755 -o root -g root "$source_binary" /usr/bin/caddy.custom
    sudo update-alternatives --install /usr/bin/caddy caddy /usr/bin/caddy.default 10
    sudo update-alternatives --install /usr/bin/caddy caddy /usr/bin/caddy.custom 50
    sudo update-alternatives --set caddy /usr/bin/caddy.custom
    sudo systemctl restart caddy
}

build_and_install_alidns_caddy() {
    local xcaddy_bin build_dir build_output

    if ! xcaddy_bin="$(resolve_xcaddy)"; then
        log_info "安装 xcaddy..."
        go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
        xcaddy_bin="$(resolve_xcaddy)" || { log_error "xcaddy 安装后不可用"; return 1; }
    fi

    build_dir="$(mktemp -d)"
    build_output="$build_dir/caddy"
    log_info "构建包含 AliDNS Provider 的 Caddy..."
    if ! XCADDY_SUDO=0 "$xcaddy_bin" build --output "$build_output" --with "$CADDY_PLUGIN"; then
        rm -rf "$build_dir"
        log_error "自定义 Caddy 构建失败"
        return 1
    fi
    if ! caddy_binary_has_alidns "$build_output"; then
        rm -rf "$build_dir"
        log_error "构建产物缺少 dns.providers.alidns"
        return 1
    fi

    archive_caddy_binary "$build_output" "$CADDY_CACHED_BINARY"
    rm -rf "$build_dir"
    log_success "自定义 Caddy 已归档: $CADDY_CACHED_BINARY"
    install_alidns_caddy_binary "$CADDY_CACHED_BINARY"
}

caddy_bin="$(command -v caddy 2>/dev/null || true)"
# 无论标准 Caddy 是否已安装，只要还缺 AliDNS Provider，就必须先确认
# 构建工具链，避免前置条件不满足时留下半完成的系统安装。
if { [ -z "$caddy_bin" ] || ! caddy_binary_has_alidns "$caddy_bin"; } && \
    ! caddy_binary_has_alidns "$CADDY_CACHED_BINARY"; then
    validate_caddy_build_prerequisites
fi

if [ -z "$caddy_bin" ]; then
    log_info "安装 Caddy 官方 Debian 包..."
    install_caddy_package
    caddy_bin="$(command -v caddy)"
fi

if caddy_binary_has_alidns "$caddy_bin"; then
    log_success "Caddy 已包含 AliDNS Provider"
    if ! caddy_binary_has_alidns "$CADDY_CACHED_BINARY"; then
        archive_caddy_binary "$caddy_bin" "$CADDY_CACHED_BINARY"
        log_success "当前自定义 Caddy 已归档: $CADDY_CACHED_BINARY"
    fi
    if upgrade_requested; then
        # caddy upgrade 会按当前 build-info 保留已有插件，避免 xcaddy 仅重建
        # AliDNS 时删除用户自行加入的其他模块。
        log_info "升级模式已开启，使用 Caddy 保留现有插件升级..."
        ensure_sudo
        sudo "$caddy_bin" upgrade
        sudo systemctl restart caddy
        archive_caddy_binary "$caddy_bin" "$CADDY_CACHED_BINARY"
        log_success "升级后的自定义 Caddy 已归档: $CADDY_CACHED_BINARY"
    else
        log_info "默认模式保留现有 Caddy 版本"
    fi
else
    if caddy_binary_has_alidns "$CADDY_CACHED_BINARY"; then
        log_info "使用缓存的 AliDNS Caddy: $CADDY_CACHED_BINARY"
        install_alidns_caddy_binary "$CADDY_CACHED_BINARY"
    else
        build_and_install_alidns_caddy
    fi
    caddy_bin="$(command -v caddy)"
fi

caddy_binary_has_alidns "$caddy_bin" || { log_error "Caddy AliDNS Provider 验证失败"; exit 1; }
log_info "Caddy: $("$caddy_bin" version 2>/dev/null)"
log_info "模块: dns.providers.alidns"
log_success "Caddy 安装完成"
render_caddy_next_steps
