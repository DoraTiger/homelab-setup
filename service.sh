#!/bin/bash
# service.sh - Explicit entrypoint for stateful service deployments.

set -e

cd "$(dirname "$0")"
source ./common.sh

SILENT=0
HOMELAB_UPGRADE=0
SERVICE_GROUP=""
SERVICE_SELECTORS=()
CLI_WORKSPACE_ROOT=""

show_help() {
    cat <<'EOF'
Usage: bash service.sh [OPTIONS] GROUP SERVICE [...]

Prepare a stateful service deployment. Services are never selected or run by
default; both the group and at least one service selector must be explicit in
silent mode.

Options:
  -h, --help                   Show this help and exit
  -s, --silent                 Run without interactive prompts
  -u, --upgrade                Pull newer images before converging services
      --workspace-root PATH    Select the data workspace root
      --proxy URL              Export an HTTP, HTTPS, or SOCKS5 proxy

Available services:
  docker  00-guacamole.sh      Apache Guacamole Compose deployment skeleton

Examples:
  bash service.sh
  bash service.sh --silent docker 00
  bash service.sh --silent docker guacamole
  bash service.sh --silent --upgrade docker 00
  bash service.sh --silent --workspace-root /data/homelab docker 00
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h) show_help; exit 0 ;;
        --silent|-s) SILENT=1; shift ;;
        --upgrade|-u) HOMELAB_UPGRADE=1; shift ;;
        --workspace-root)
            [ "$#" -ge 2 ] && [ -n "$2" ] || { log_error "--workspace-root 需要路径"; exit 1; }
            CLI_WORKSPACE_ROOT="$2"; shift 2 ;;
        --proxy)
            [ "$#" -ge 2 ] && [ -n "$2" ] || { log_error "--proxy 需要地址"; exit 1; }
            PROXY_ADDR="$2"; export PROXY_ADDR; export_proxy_environment; shift 2 ;;
        -*) log_error "未知选项: $1"; exit 1 ;;
        *)
            if [ -z "$SERVICE_GROUP" ]; then
                SERVICE_GROUP="$1"
            else
                SERVICE_SELECTORS+=("$1")
            fi
            shift
            ;;
    esac
done

export HOMELAB_UPGRADE

if [ -n "$CLI_WORKSPACE_ROOT" ]; then
    homelab_write_local_workspace "$SETUP_ROOT/.homelab.local" "$CLI_WORKSPACE_ROOT"
    HOMELAB_WORKSPACE_ROOT="$(homelab_normalize_absolute_path "$CLI_WORKSPACE_ROOT" "$HOME")"
    export HOMELAB_WORKSPACE_ROOT
    homelab_initialize_paths "$SETUP_ROOT"
fi

select_group_interactively() {
    local group_dir group_name
    echo "可用服务组:"
    for group_dir in services/*; do
        [ -d "$group_dir" ] || continue
        group_name="$(basename "$group_dir")"
        printf '  %-12s %s\n' "$group_name" "$group_dir"
    done
    read -rp "请选择服务组: " SERVICE_GROUP
}

if [ -z "$SERVICE_GROUP" ]; then
    if [ "$SILENT" = 1 ]; then
        log_error "静默模式必须显式指定服务组和服务，例如: docker 00"
        exit 1
    fi
    select_group_interactively
fi

case "$SERVICE_GROUP" in
    ''|*/*|.*|*'..'*) log_error "无效服务组: $SERVICE_GROUP"; exit 1 ;;
esac

SERVICE_DIR="$SETUP_ROOT/services/$SERVICE_GROUP"
[ -d "$SERVICE_DIR" ] || { log_error "未知服务组: $SERVICE_GROUP"; exit 1; }

declare -a SERVICES=()
declare -A DESCRIPTIONS=()
shopt -s nullglob
for service_file in "$SERVICE_DIR"/*.sh; do
    description="$(grep -m1 '^# DESCRIPTION:' "$service_file" | sed 's/^# DESCRIPTION: //')"
    SERVICES+=("$service_file")
    DESCRIPTIONS["$service_file"]="${description:-无描述}"
done
shopt -u nullglob
[ "${#SERVICES[@]}" -gt 0 ] || { log_error "服务组中没有可执行服务: $SERVICE_GROUP"; exit 1; }

if [ "${#SERVICE_SELECTORS[@]}" -eq 0 ]; then
    if [ "$SILENT" = 1 ]; then
        log_error "静默模式必须显式指定至少一个服务"
        exit 1
    fi
    echo "可用 $SERVICE_GROUP 服务:"
    for service_file in "${SERVICES[@]}"; do
        service_name="$(basename "$service_file")"
        printf '  [%2s] %-24s %s\n' "${service_name%%-*}" "$service_name" "${DESCRIPTIONS[$service_file]}"
    done
    read -rp "请选择服务（可用空格分隔）: " input
    read -ra SERVICE_SELECTORS <<< "$input"
fi

[ "${#SERVICE_SELECTORS[@]}" -gt 0 ] || { log_error "未选择服务"; exit 1; }

mapfile -t SELECTED_SERVICES < <(
    homelab_unique_modules "${SERVICES[@]}" -- "${SERVICE_SELECTORS[@]}"
) || exit 1
[ "${#SELECTED_SERVICES[@]}" -gt 0 ] || { log_error "未选择服务"; exit 1; }

current=0
total="${#SELECTED_SERVICES[@]}"
for service_file in "${SELECTED_SERVICES[@]}"; do
    current=$((current + 1))
    log_info "▶ [$current/$total] $SERVICE_GROUP/$(basename "$service_file") — ${DESCRIPTIONS[$service_file]}"
    echo "──────────────────────────────────────────────────"
    HOMELAB_SILENT="$SILENT" bash "$service_file"
    echo "──────────────────────────────────────────────────"
done

log_success "选中的服务部署文件已准备完成"
