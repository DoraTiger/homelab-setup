#!/bin/bash
# init.sh - Unified entrypoint for Homelab Debian environment setup

set -e

cd "$(dirname "$0")"
source ./common.sh

# ========== 1. 参数与工作区 ==========

homelab_parse_init_args "$@" || exit 1

if [ "$CLI_HELP" = 1 ]; then
    cat <<'EOF'
Usage: bash init.sh [OPTIONS] [MODULE ...]

Configure a Debian + Xfce homelab environment. Without arguments, the
interactive module menu is displayed.

Options:
  -h, --help                   Show this help and exit
  -s, --silent                 Run without interactive prompts
  -u, --upgrade                Explicitly upgrade installed components
      --proxy URL              Use an HTTP, HTTPS, or SOCKS5 proxy
      --workspace-root PATH    Select the data workspace root

MODULE selectors:
  A module can be selected by number, name, or full filename, for example:
  03  docker  03-docker.sh

Examples:
  bash init.sh
  bash init.sh --silent 03 11 12
  bash init.sh --silent nodejs golang
  bash init.sh --silent --upgrade 07
  bash init.sh --workspace-root /data/homelab
EOF
    exit 0
fi

SILENT="$CLI_SILENT"
HOMELAB_UPGRADE="$CLI_UPGRADE"
PROXY_ADDR="$CLI_PROXY"
MODULE_ARGS=("${CLI_SELECTORS[@]}")
export HOMELAB_SILENT="$SILENT" HOMELAB_UPGRADE
if [ -n "$PROXY_ADDR" ]; then
    export PROXY_ADDR
    export_proxy_environment
fi

if [ -n "$CLI_WORKSPACE_ROOT" ]; then
    homelab_write_local_workspace "$SETUP_ROOT/.homelab.local" "$CLI_WORKSPACE_ROOT"
    HOMELAB_WORKSPACE_ROOT="$(homelab_normalize_absolute_path "$CLI_WORKSPACE_ROOT" "$HOME")"
    export HOMELAB_WORKSPACE_ROOT
    homelab_initialize_paths "$SETUP_ROOT"
fi

# ========== 2. 扫描模块 ==========

declare -a MODULES=()
declare -A DESCRIPTIONS=()
shopt -s nullglob
for module_file in modules/*.sh; do
    description="$(grep -m1 '^# DESCRIPTION:' "$module_file" | sed 's/^# DESCRIPTION: //')"
    MODULES+=("$module_file")
    DESCRIPTIONS["$module_file"]="${description:-无描述}"
done
shopt -u nullglob
[ "${#MODULES[@]}" -gt 0 ] || { log_error "未发现模块"; exit 1; }

resolve_selections() {
    local selector resolved
    local -A seen=()
    SELECTED_MODULES=()
    for selector in "$@"; do
        resolved="$(homelab_resolve_module "$selector" "${MODULES[@]}")" || return 1
        if [ -z "${seen[$resolved]:-}" ]; then
            SELECTED_MODULES+=("$resolved")
            seen[$resolved]=1
        fi
    done
}

run_modules() {
    local selected=("$@") module_file current=0 total="${#selected[@]}"
    for module_file in "${selected[@]}"; do
        current=$((current + 1))
        log_info "▶ [$current/$total] $(basename "$module_file") — ${DESCRIPTIONS[$module_file]}"
        echo "──────────────────────────────────────────────────"
        bash "$module_file"
        echo "──────────────────────────────────────────────────"
    done
}

# ========== 3. 静默执行 ==========

if [ "$SILENT" = 1 ]; then
    if [ "${#MODULE_ARGS[@]}" -eq 0 ]; then
        SELECTED_MODULES=("${MODULES[@]}")
    else
        resolve_selections "${MODULE_ARGS[@]}" || exit 1
    fi
    run_modules "${SELECTED_MODULES[@]}"
    log_success "全部完成"
    exit 0
fi

# ========== 4. 交互菜单 ==========

show_menu() {
    local module_file name prefix
    clear
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Homelab Debian + Xfce 环境配置"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Setup:    $SETUP_ROOT"
    echo "  工作区:   $WORKSPACE_ROOT"
    echo "  缓存:     $CACHE_DIR"
    echo "  安装包:   $PACKAGES_DIR"
    echo "  备份:     $BACKUP_DIR"
    echo "  代理:     ${PROXY_ADDR:-未配置}"
    echo "  升级模式: $([ "$HOMELAB_UPGRADE" = 1 ] && echo 开启 || echo 关闭)"
    echo "──────────────────────────────────────────────────"
    for module_file in "${MODULES[@]}"; do
        name="$(basename "$module_file")"
        prefix="${name%%-*}"
        printf '  [%2s] %-24s %s\n' "$prefix" "$name" "${DESCRIPTIONS[$module_file]}"
    done
    echo "──────────────────────────────────────────────────"
    echo "  [a] 全部  [p] 代理  [u] 升级模式  [w] 工作区  [q] 退出"
}

while true; do
    show_menu
    read -rp "请选择: " input
    case "$input" in
        q|Q|quit|exit) log_info "已退出"; exit 0 ;;
        p|P|proxy) setup_proxy; read -rp "按回车返回菜单..." _ ;;
        u|U|upgrade)
            if [ "$HOMELAB_UPGRADE" = 1 ]; then HOMELAB_UPGRADE=0; else HOMELAB_UPGRADE=1; fi
            export HOMELAB_UPGRADE
            ;;
        w|W|workspace)
            workspace_input="$(prompt_input "工作区路径" "$WORKSPACE_ROOT")"
            homelab_write_local_workspace "$SETUP_ROOT/.homelab.local" "$workspace_input"
            HOMELAB_WORKSPACE_ROOT="$(homelab_normalize_absolute_path "$workspace_input" "$HOME")"
            export HOMELAB_WORKSPACE_ROOT
            homelab_initialize_paths "$SETUP_ROOT"
            ;;
        a|A|all) run_modules "${MODULES[@]}"; break ;;
        *)
            read -ra selectors <<< "$input"
            if ! resolve_selections "${selectors[@]}"; then
                read -rp "按回车返回菜单..." _
                continue
            fi
            run_modules "${SELECTED_MODULES[@]}"
            break
            ;;
    esac
done

log_success "选中的模块已全部完成"
