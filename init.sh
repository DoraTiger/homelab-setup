#!/bin/bash
# init.sh - Unified entrypoint for Homelab Debian environment setup
#
# 用法:
#   bash init.sh                     # 交互式菜单
#   bash init.sh --silent            # 静默执行全部模块
#   bash init.sh --silent 1 3        # 静默执行第 1、3 个模块
#   bash init.sh --proxy socks5://127.0.0.1:7890  # 指定代理

set -e

cd "$(dirname "$0")"
source ./common.sh

# ========== 参数解析 ==========
SILENT=0
MODULE_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --silent|-s) SILENT=1 ;;
        --proxy)     shift; PROXY_ADDR="$1" ;;
        *)           MODULE_ARGS+=("$arg") ;;
    esac
done

export HOMELAB_SILENT="$SILENT"
[ -n "${PROXY_ADDR:-}" ] && export PROXY_ADDR

# ========== 扫描模块 ==========
declare -a MODULES=()
declare -A DESCRIPTIONS=()

shopt -s nullglob
for f in modules/*.sh; do
    name=$(basename "$f")
    desc=$(grep -m1 '^# DESCRIPTION:' "$f" | sed 's/^# DESCRIPTION: //')
    MODULES+=("$name")
    DESCRIPTIONS["$name"]="${desc:-无描述}"
done
shopt -u nullglob

if [ ${#MODULES[@]} -eq 0 ]; then
    log_warn "未发现任何模块脚本 (modules/*.sh)"
    exit 0
fi

# ========== 执行模块 ==========
run_modules() {
    local selected=("$@")
    local total=${#selected[@]}
    local current=0

    for mod in "${selected[@]}"; do
        current=$((current + 1))
        log_info "▶ [$current/$total] 执行: $mod — ${DESCRIPTIONS[$mod]}"
        echo "──────────────────────────────────────────────────"
        bash "modules/$mod"
        echo "──────────────────────────────────────────────────"
        log_success "✓ $mod 完成"
    done
}

# ========== 静默模式 ==========
if [ "$SILENT" = "1" ]; then
    [ -n "${PROXY_ADDR:-}" ] && log_info "代理: $PROXY_ADDR"
    if [ ${#MODULE_ARGS[@]} -eq 0 ]; then
        log_info "静默模式: 执行全部 ${#MODULES[@]} 个模块"
        run_modules "${MODULES[@]}"
    else
        selected=()
        for num in "${MODULE_ARGS[@]}"; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#MODULES[@]}" ]; then
                selected+=("${MODULES[$((num-1))]}")
            else
                log_warn "无效模块编号: $num，已忽略"
            fi
        done
        [ ${#selected[@]} -eq 0 ] && { log_error "无有效模块"; exit 1; }
        run_modules "${selected[@]}"
    fi
    echo ""
    log_success "🎉 全部完成!"
    exit 0
fi

# ========== 交互菜单 ==========
show_menu() {
    clear
    local root=$(cd .. && pwd)
    local proxy_status="\033[0;33m未配置\033[0m"
    [ -n "${PROXY_ADDR:-}" ] && proxy_status="\033[0;32m$PROXY_ADDR\033[0m"

    echo ""
    echo -e "\033[0;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[0;36m  Homelab Debian 环境配置工具\033[0m"
    echo -e "\033[0;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "  项目路径:   $root"
    echo -e "  缓存目录:   $root/cache"
    echo -e "  安装包:     $root/packages"
    echo -e "  密钥目录:   $root/setup/keys"
    echo -e "  代理状态:   $proxy_status"
    echo -e "\033[0;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    echo -e "\033[0;33m  可用模块:\033[0m"
    echo "  ────────────────────────────────────────────────"
    for i in "${!MODULES[@]}"; do
        printf "    \033[0;32m[%2d]\033[0m %-24s %s\n" "$i" "${MODULES[$i]}" "${DESCRIPTIONS[${MODULES[$i]}]}"
    done
    echo "  ────────────────────────────────────────────────"
    echo -e "    \033[0;33m[a]\033[0m  全部执行     \033[0;33m[p]\033[0m  配置代理     \033[0;33m[q]\033[0m  退出"
    echo ""
}

while true; do
    show_menu
    read -rp "请选择: " input

    case "$input" in
        q|Q|quit|exit)
            log_info "已退出"
            exit 0
            ;;
        p|P|proxy)
            setup_proxy
            read -rp "按回车返回菜单..." _
            ;;
        a|A|all)
            run_modules "${MODULES[@]}"
            break
            ;;
        *)
            selected=()
            for num in $input; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 0 ] && [ "$num" -lt "${#MODULES[@]}" ]; then
                    selected+=("${MODULES[$num]}")
                else
                    log_warn "无效选择: $num，已忽略"
                fi
            done
            if [ ${#selected[@]} -eq 0 ]; then
                log_warn "未选择任何有效模块"
                read -rp "按回车返回..." _
                continue
            fi
            run_modules "${selected[@]}"
            break
            ;;
    esac
done

echo ""
log_success "🎉 选中的模块已全部完成!"
