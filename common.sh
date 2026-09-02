#!/bin/bash
# common.sh - Stable shared entrypoint for Homelab setup modules.

# ========== 公共库路径 ==========

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SETUP_ROOT/lib/paths.sh"
homelab_initialize_paths "$SETUP_ROOT"

# ========== 日志 ==========

log_info()    { echo -e "\033[0;36mℹ️ $1\033[0m"; }
log_success() { echo -e "\033[0;32m✅ $1\033[0m"; }
log_warn()    { echo -e "\033[0;33m⚠️ $1\033[0m"; }
log_error()   { echo -e "\033[0;31m❌ $1\033[0m" >&2; }

# ========== 执行模式 ==========

SILENT="${HOMELAB_SILENT:-0}"
HOMELAB_UPGRADE="${HOMELAB_UPGRADE:-0}"
case "$HOMELAB_UPGRADE" in
    0|1) ;;
    *)
        echo "HOMELAB_UPGRADE must be 0 or 1" >&2
        return 1 2>/dev/null || exit 1
        ;;
esac
export HOMELAB_UPGRADE

upgrade_requested() {
    [ "$HOMELAB_UPGRADE" = 1 ]
}

# ========== 分类辅助层 ==========

source "$SETUP_ROOT/lib/interaction.sh"
source "$SETUP_ROOT/lib/shell-env.sh"
source "$SETUP_ROOT/lib/network.sh"
source "$SETUP_ROOT/lib/config.sh"
source "$SETUP_ROOT/lib/cli.sh"

# When modules are invoked directly with PROXY_ADDR, propagate the proxy to
# package managers and installer subprocesses as well as direct curl/wget calls.
export_proxy_environment

# ========== 权限与工作区 ==========

ensure_sudo() {
    if [ "$EUID" -eq 0 ]; then return 0; fi
    if ! command -v sudo &>/dev/null; then
        log_error "sudo 未安装，请先以 root 身份执行: apt install -y sudo"
        return 1
    fi
    log_info "此步骤需要 sudo 权限"
    sudo -v 2>/dev/null || {
        log_error "sudo 验证失败，请确认用户已加入 sudo 组"
        return 1
    }
}

run_as_root() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        ensure_sudo || return 1
        sudo -- "$@"
    fi
}

ensure_workspace_ready() {
    if [ ! -d "$WORKSPACE_ROOT" ]; then
        log_error "工作区不存在: $WORKSPACE_ROOT"
        return 1
    fi
}
