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

export_proxy_environment() {
    [ -n "${PROXY_ADDR:-}" ] || return 0
    export http_proxy="$PROXY_ADDR" https_proxy="$PROXY_ADDR" all_proxy="$PROXY_ADDR"
    export HTTP_PROXY="$PROXY_ADDR" HTTPS_PROXY="$PROXY_ADDR" ALL_PROXY="$PROXY_ADDR"
}

validate_shell_script() {
    [ -s "$1" ] && head -n1 "$1" | grep -Eq '^#!.*/(env +)?(ba|d?a|z|k)?sh([[:space:]]|$)'
}

validate_tar_archive() {
    [ -s "$1" ] && tar -tf "$1" >/dev/null 2>&1
}

validate_zip_archive() {
    [ -s "$1" ] && unzip -tq "$1" >/dev/null 2>&1
}

validate_deb_package() {
    [ -s "$1" ] && dpkg-deb --info "$1" >/dev/null 2>&1
}

validate_elf_binary() {
    [ -s "$1" ] && [ "$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')" = '7f454c46' ]
}

migrate_legacy_package() {
    local legacy="$1" destination="$2" validator="${3:-}"

    [ -e "$legacy" ] || return 0
    if [ -e "$destination" ]; then
        return 0
    fi
    if [ ! -s "$legacy" ] || { [ -n "$validator" ] && ! "$validator" "$legacy"; }; then
        return 1
    fi
    mkdir -p "$(dirname "$destination")"
    mv "$legacy" "$destination"
    log_info "已迁移旧安装包缓存: $legacy → $destination"
}

find_latest_valid_package() {
    local package_dir="$1" pattern="$2" validator="${3:-}" candidate

    [ -d "$package_dir" ] || return 1
    while IFS= read -r candidate; do
        if [ -s "$candidate" ] && { [ -z "$validator" ] || "$validator" "$candidate"; }; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(find "$package_dir" -maxdepth 1 -type f -name "$pattern" -print | sort -Vr)
    return 1
}

run_with_optional_proxy() {
    local command_name="${1##*/}"
    local -a command_line=("$@")

    case "$command_name" in
        curl)
            command_line=("$1" --connect-timeout 10 --max-time 180 --retry 3 --retry-delay 2 --retry-all-errors "${@:2}")
            ;;
        wget)
            command_line=("$1" --timeout=30 --tries=3 "${@:2}")
            ;;
    esac

    if [ -n "${PROXY_ADDR:-}" ]; then
        http_proxy="$PROXY_ADDR" https_proxy="$PROXY_ADDR" all_proxy="$PROXY_ADDR" \
            HTTP_PROXY="$PROXY_ADDR" HTTPS_PROXY="$PROXY_ADDR" ALL_PROXY="$PROXY_ADDR" \
            "${command_line[@]}"
    else
        "${command_line[@]}"
    fi
}

download_package() {
    local url="$1" destination="$2" validator="${3:-}" partial attempt

    mkdir -p "$(dirname "$destination")"
    if [ -s "$destination" ] && { [ -z "$validator" ] || "$validator" "$destination"; }; then
        log_info "使用缓存的安装包: $destination"
        return 0
    fi

    partial="$destination.part"
    rm -f "$partial"
    for attempt in 1 2 3; do
        if command -v curl >/dev/null 2>&1; then
            run_with_optional_proxy curl --retry 0 -fL -o "$partial" "$url" || true
        elif command -v wget >/dev/null 2>&1; then
            run_with_optional_proxy wget --tries=1 -O "$partial" "$url" || true
        else
            log_error "下载需要 curl 或 wget"
            return 1
        fi

        if [ -s "$partial" ] && { [ -z "$validator" ] || "$validator" "$partial"; }; then
            mv -f "$partial" "$destination"
            log_success "安装包已缓存: $destination"
            return 0
        fi
        rm -f "$partial"
        [ "$attempt" -eq 3 ] || log_warn "下载失败，准备重试 ($attempt/3): $url"
    done

    log_error "下载失败或文件校验未通过: $url"
    return 1
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
        export PROXY_ADDR
        export_proxy_environment
        log_success "代理已启用: $proxy_input"
    else
        log_info "跳过代理配置"
    fi
}
