#!/bin/bash
# DESCRIPTION: APT 软件源配置 — 配置清华镜像源并安装基础工具

set -e
source "$(dirname "$0")/../common.sh"

# ========== 检测发行版 ==========

IFS='|' read -r DISTRO CODENAME <<< "$(detect_distro)"
log_info "检测到发行版: $DISTRO ($CODENAME)"

# ========== 幂等性检查 ==========

check_tsinghua_configured() {
    local configured=false

    # 检查传统格式
    if grep -q "mirrors.tuna.tsinghua.edu.cn" /etc/apt/sources.list 2>/dev/null; then
        configured=true
    fi

    # 检查 DEB822 格式
    if ls /etc/apt/sources.list.d/*.sources &>/dev/null; then
        if grep -rq "mirrors.tuna.tsinghua.edu.cn" /etc/apt/sources.list.d/*.sources 2>/dev/null; then
            configured=true
        fi
    fi

    echo "$configured"
}

check_components_complete() {
    local sources_file="$1"
    if [ ! -f "$sources_file" ]; then
        echo "false"
        return
    fi
    # 检查是否包含 contrib non-free non-free-firmware
    if grep -q "contrib" "$sources_file" 2>/dev/null && \
       grep -q "non-free" "$sources_file" 2>/dev/null && \
       grep -q "non-free-firmware" "$sources_file" 2>/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

TSINGHUA_CONFIGURED=$(check_tsinghua_configured)

if [ "$TSINGHUA_CONFIGURED" = "true" ]; then
    COMPONENTS_OK=$(check_components_complete /etc/apt/sources.list)
    if [ "$COMPONENTS_OK" = "true" ]; then
        log_success "清华 APT 源已完整配置，跳过"
    else
        log_warn "清华源已配置但组件不完整（缺少 contrib/non-free），跳过源配置"
        log_warn "如需补全组件，请手动编辑 /etc/apt/sources.list"
    fi
else
    TSINGHUA_CONFIGURED="false"
fi

# ========== 配置源 ==========

if [ "$TSINGHUA_CONFIGURED" != "true" ]; then
    ensure_sudo

    # 自动探测配置格式
    detect_format() {
        if [ -f /etc/apt/sources.list.d/debian.sources ]; then
            echo "deb822"
        elif [ -f /etc/apt/sources.list ] && [ -s /etc/apt/sources.list ]; then
            echo "traditional"
        else
            echo "traditional"
        fi
    }

    if [ "$DISTRO" = "debian" ]; then
        FORMAT=$(detect_format)
        log_info "检测到配置格式: $FORMAT"
    else
        FORMAT="deb822"
    fi

    # 备份现有配置
    if [ -f /etc/apt/sources.list ] && [ "$TSINGHUA_CONFIGURED" = "false" ]; then
        sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
        log_info "已备份原配置: /etc/apt/sources.list.bak"
    fi

    if [ "$DISTRO" = "debian" ]; then
        SECURITY_LINE="deb https://security.debian.org/debian-security ${CODENAME}-security main contrib non-free non-free-firmware"

        if [ "$FORMAT" = "traditional" ]; then
            log_info "使用传统格式配置 Debian $CODENAME 源"
            sudo tee /etc/apt/sources.list > /dev/null <<EOF
# Debian $CODENAME - 清华镜像源
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $CODENAME main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $CODENAME-updates main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $CODENAME-backports main contrib non-free non-free-firmware

# 安全更新（官方源，不走镜像以保证时效性）
$SECURITY_LINE
EOF
        else
            log_info "使用 DEB822 格式配置 Debian $CODENAME 源"
            sudo tee /etc/apt/sources.list.d/debian.sources > /dev/null <<EOF
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/debian
Suites: $CODENAME $CODENAME-updates $CODENAME-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# 安全更新（官方源）
Types: deb
URIs: https://security.debian.org/debian-security
Suites: ${CODENAME}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
            # 确认新文件写入成功后，再禁用旧的 sources.list
            if [ -s /etc/apt/sources.list.d/debian.sources ]; then
                if [ -f /etc/apt/sources.list ]; then
                    sudo mv /etc/apt/sources.list /etc/apt/sources.list.disabled
                    log_info "已禁用旧的 /etc/apt/sources.list"
                fi
            else
                log_error "debian.sources 写入失败，保留原 sources.list"
                exit 1
            fi
        fi

    elif [ "$DISTRO" = "ubuntu" ]; then
        log_info "配置 Ubuntu $CODENAME 清华源 (DEB822)"
        sudo tee /etc/apt/sources.list.d/ubuntu-tuna.sources > /dev/null <<EOF
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/ubuntu/
Suites: $CODENAME $CODENAME-updates $CODENAME-backports $CODENAME-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
    else
        log_warn "不支持的发行版: $DISTRO，跳过源配置"
        exit 0
    fi

    # 更新索引
    log_info "正在更新软件包索引..."
    sudo apt clean
    sudo apt update -y
fi

# ========== 安装基础工具 ==========

log_info "检查基础工具..."
ensure_sudo

BASE_TOOLS=(
    curl wget git vim make
    build-essential
    net-tools
    btop fastfetch
    apt-transport-https ca-certificates gnupg
)

TO_INSTALL=()
for tool in "${BASE_TOOLS[@]}"; do
    if ! dpkg -s "$tool" &>/dev/null; then
        TO_INSTALL+=("$tool")
    fi
done

if [ ${#TO_INSTALL[@]} -gt 0 ]; then
    log_info "安装基础工具: ${TO_INSTALL[*]}"
    sudo apt install -y "${TO_INSTALL[@]}"
    log_success "基础工具安装完成"
else
    log_success "基础工具已全部安装，跳过"
fi

# ========== 升级已安装的软件包 ==========

log_info "检查软件包升级..."
ensure_sudo
sudo apt-get update -y -qq
UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -v "Listing" | head -n1)
if [ -n "$UPGRADABLE" ]; then
    log_info "发现可升级的软件包，正在升级..."
    sudo apt upgrade -y
    log_success "软件包升级完成"
else
    log_success "所有软件包已是最新版本"
fi

log_success "APT 源配置完成"
