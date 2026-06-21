#!/bin/bash
# common.sh - Shared utilities for Homelab environment setup

# ========== 颜色日志 ==========
log_info()    { echo -e "\033[0;36mℹ️ $1\033[0m"; }
log_success() { echo -e "\033[0;32m✅ $1\033[0m"; }
log_warn()    { echo -e "\033[0;33m⚠️ $1\033[0m"; }
log_error()   { echo -e "\033[0;31m❌ $1\033[0m" >&2; }

# ========== 路径常量 ==========
# init.sh 已 cd 到 setup/ 目录，.. 即项目根
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="$PROJECT_ROOT/cache"
PACKAGES_DIR="$PROJECT_ROOT/packages"

# ========== 静默模式 ==========
SILENT="${HOMELAB_SILENT:-0}"

# ========== 交互工具 ==========

# 单选菜单: prompt_choice "提示语" "默认值" "选项1" "选项2" ...
# 返回用户选择的值
prompt_choice() {
    local msg="$1"; shift
    local default="$1"; shift
    local options=("$@")
    if [ "$SILENT" = "1" ]; then
        echo "$default"
        return
    fi
    echo ""
    echo -e "\033[0;33m  $msg\033[0m"
    for i in "${!options[@]}"; do
        if [ "${options[$i]}" = "$default" ]; then
            printf "    \033[0;32m[%d]\033[0m %s \033[0;32m(默认)\033[0m\n" "$((i+1))" "${options[$i]}"
        else
            printf "    \033[0;33m[%d]\033[0m %s\n" "$((i+1))" "${options[$i]}"
        fi
    done
    echo ""
    local choice
    read -rp "  请选择 [1-${#options[@]}]: " choice
    choice=${choice:-$default}
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
        echo "${options[$((choice-1))]}"
    else
        echo "$default"
    fi
}

# 是/否确认: prompt_yesno "提示语" "y/n"
# 返回 0=是, 1=否
prompt_yesno() {
    local msg="$1"
    local default="${2:-y}"
    if [ "$SILENT" = "1" ]; then
        [ "$default" = "y" ] && return 0 || return 1
    fi
    echo ""
    if [ "$default" = "y" ]; then
        read -rp "  $msg [Y/n]: " ans
        ans=${ans:-y}
    else
        read -rp "  $msg [y/N]: " ans
        ans=${ans:-n}
    fi
    [[ "$ans" =~ ^[Yy] ]]
}

# 文本输入: prompt_input "提示语" "默认值"
# 返回用户输入的值
prompt_input() {
    local msg="$1"
    local default="$2"
    if [ "$SILENT" = "1" ]; then
        echo "$default"
        return
    fi
    read -rp "  $msg [$default]: " input
    echo "${input:-$default}"
}

# 密码输入（隐藏回显）: prompt_secret "提示语"
# 返回用户输入的值；静默模式返回空字符串
prompt_secret() {
    local msg="$1"
    if [ "$SILENT" = "1" ]; then
        echo ""
        return
    fi
    local val val2
    read -rs -p "  $msg: " val
    echo ""
    read -rs -p "  请再次输入: " val2
    echo ""
    if [ "$val" != "$val2" ]; then
        log_error "两次输入不一致"
        return 1
    fi
    echo "$val"
}

# 表格展示: prompt_table "标题1|标题2|..." "值1|值2|..." ...
# 竖线分隔列，自动对齐
prompt_table() {
    local header="$1"; shift
    local rows=("$@")
    IFS='|' read -ra hdr_cols <<< "$header"
    local ncols=${#hdr_cols[@]}

    # 计算每列最大宽度
    local -a widths=()
    for c in "${hdr_cols[@]}"; do
        widths+=(${#c})
    done
    for row in "${rows[@]}"; do
        IFS='|' read -ra cells <<< "$row"
        for i in $(seq 0 $((ncols-1))); do
            [ ${#cells[$i]} -gt ${widths[$i]} ] && widths[$i]=${#cells[$i]}
        done
    done

    # 构建分隔线
    local sep="  +"
    for w in "${widths[@]}"; do
        local i
        for ((i=0; i<w+2; i++)); do sep+="-"; done
        sep+="+"
    done

    # 打印表头
    echo "$sep"
    local hdr_line="  |"
    for i in $(seq 0 $((ncols-1))); do
        printf -v cell "%-$((widths[i]+1))s " "${hdr_cols[$i]}"
        hdr_line+="${cell}|"
    done
    echo -e "\033[0;36m${hdr_line}\033[0m"
    echo "$sep"

    # 打印数据行
    for row in "${rows[@]}"; do
        IFS='|' read -ra cells <<< "$row"
        local line="  |"
        for i in $(seq 0 $((ncols-1))); do
            printf -v cell "%-$((widths[i]+1))s " "${cells[$i]}"
            line+="${cell}|"
        done
        echo "$line"
    done
    echo "$sep"
}

# ========== 工具函数 ==========

# sudo 权限检查
ensure_sudo() {
    if [ "$EUID" -eq 0 ]; then
        return 0
    fi
    if ! command -v sudo &>/dev/null; then
        log_error "sudo 未安装，请先以 root 身份执行: apt install -y sudo"
        exit 1
    fi
    log_info "此步骤需要 sudo 权限"
    sudo -v 2>/dev/null || {
        log_error "sudo 验证失败，请确认用户已加入 sudo 组"
        exit 1
    }
}

ensure_workspace_ready() {
    if [ ! -d "$PROJECT_ROOT" ]; then
        log_error "Project root not found at $PROJECT_ROOT"
        exit 1
    fi
}

# 确保 .bashrc 加载 .bashrc.d/ 目录下的脚本
ensure_bashrc_d_loader() {
    mkdir -p "$HOME/.bashrc.d"
    if ! grep -qF 'Load environment snippets' "$HOME/.bashrc" 2>/dev/null; then
        cat <<'SNIPPET' >> "$HOME/.bashrc"

# Load environment snippets
if [ -d "$HOME/.bashrc.d" ]; then
    for f in "$HOME"/.bashrc.d/*.sh; do
        [ -f "$f" ] && . "$f"
    done
fi
SNIPPET
        log_success ".bashrc.d 加载逻辑已写入 .bashrc"
    fi
}

detect_distro() {
    local distro codename
    if command -v lsb_release &> /dev/null; then
        distro=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
        codename=$(lsb_release -cs)
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        distro=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
        codename="$VERSION_CODENAME"
    else
        log_warn "Unable to detect distro, assuming ubuntu/noble"
        distro="ubuntu"
        codename="noble"
    fi
    echo "$distro|$codename"
}

run_with_optional_proxy() {
    if [ -n "${PROXY_ADDR:-}" ]; then
        HTTP_PROXY="$PROXY_ADDR" \
        HTTPS_PROXY="$PROXY_ADDR" \
        ALL_PROXY="$PROXY_ADDR" \
        "$@"
    else
        "$@"
    fi
}

# 代理配置（交互式或环境变量）
# 支持 http/https/socks5:// 格式
setup_proxy() {
    # 已有环境变量则跳过
    if [ -n "${PROXY_ADDR:-}" ]; then
        log_info "使用环境变量代理: $PROXY_ADDR"
        return
    fi

    # 静默模式跳过
    if [ "$SILENT" = "1" ]; then
        return
    fi

    echo ""
    log_info "代理配置（可选，直接回车跳过）"
    echo -e "  支持格式: \033[0;36mhttp://host:port\033[0m 或 \033[0;36msocks5://host:port\033[0m"
    read -rp "  代理地址: " proxy_input

    if [ -n "$proxy_input" ]; then
        export PROXY_ADDR="$proxy_input"
        export HTTP_PROXY="$proxy_input"
        export HTTPS_PROXY="$proxy_input"
        export ALL_PROXY="$proxy_input"
        log_success "代理已启用: $proxy_input"
    else
        log_info "跳过代理配置"
    fi
}
