#!/bin/bash

detect_distro() {
    local distro codename
    if command -v lsb_release &>/dev/null; then
        distro="$(lsb_release -is | tr '[:upper:]' '[:lower:]')"
        codename="$(lsb_release -cs)"
    elif [ -f /etc/os-release ]; then
        distro="$(. /etc/os-release; echo "${ID,,}")"
        codename="$(. /etc/os-release; echo "$VERSION_CODENAME")"
    else
        log_warn "无法检测发行版，默认使用 ubuntu/noble"
        distro="ubuntu"
        codename="noble"
    fi
    echo "$distro|$codename"
}

run_with_optional_proxy() {
    if [ -n "${PROXY_ADDR:-}" ]; then
        HTTP_PROXY="$PROXY_ADDR" HTTPS_PROXY="$PROXY_ADDR" ALL_PROXY="$PROXY_ADDR" "$@"
    else
        "$@"
    fi
}

setup_proxy() {
    local proxy_input
    if [ -n "${PROXY_ADDR:-}" ]; then log_info "使用环境变量代理: $PROXY_ADDR"; return; fi
    if [ "$SILENT" = "1" ]; then return; fi
    echo ""
    log_info "代理配置（可选，直接回车跳过）"
    read -rp "  代理地址: " proxy_input
    if [ -n "$proxy_input" ]; then
        PROXY_ADDR="$proxy_input"
        export PROXY_ADDR HTTP_PROXY="$proxy_input" HTTPS_PROXY="$proxy_input" ALL_PROXY="$proxy_input"
        log_success "代理已启用: $proxy_input"
    else
        log_info "跳过代理配置"
    fi
}
