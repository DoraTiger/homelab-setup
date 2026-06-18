#!/bin/bash
# DESCRIPTION: R 语言安装与配置 — CRAN 清华镜像 + r-base-dev

set -e
source "$(dirname "$0")/../common.sh"

# ========== sudo 权限 ==========

ensure_sudo() {
    if [ "$EUID" -eq 0 ]; then return 0; fi
    if ! command -v sudo &>/dev/null; then
        log_error "sudo 未安装，请先以 root 身份执行: apt install -y sudo"
        exit 1
    fi
    sudo -v 2>/dev/null || { log_error "sudo 验证失败"; exit 1; }
}

# ========== 检测发行版 ==========

IFS='|' read -r DISTRO CODENAME <<< "$(detect_distro)"
log_info "检测到发行版: $DISTRO ($CODENAME)"

# ========== 安装 R ==========

if command -v R &>/dev/null; then
    R_VER=$(R --version 2>/dev/null | head -n1)
    log_success "R 已安装: $R_VER"
else
    ensure_sudo

    if [ "$DISTRO" = "debian" ]; then
        log_info "配置 CRAN 清华镜像源..."

        # 添加 GPG 密钥
        sudo gpg --keyserver keyserver.ubuntu.com --recv-key '95C0FAF38DB3CCAD0C080A7BDC78B2DDEABC47B7' 2>/dev/null || \
            run_with_optional_proxy sudo gpg --keyserver keyserver.ubuntu.com --recv-key '95C0FAF38DB3CCAD0C080A7BDC78B2DDEABC47B7' 2>/dev/null
        sudo gpg --export '95C0FAF38DB3CCAD0C080A7BDC78B2DDEABC47B7' | \
            sudo tee /etc/apt/trusted.gpg.d/cran_debian_key.gpg > /dev/null

        # 添加 CRAN 源
        CRAN_REPO="deb https://mirrors.tuna.tsinghua.edu.cn/CRAN/bin/linux/debian ${CODENAME}-cran40/"
        if ! grep -qF "mirrors.tuna.tsinghua.edu.cn/CRAN" /etc/apt/sources.list.d/r-cran.list 2>/dev/null; then
            echo "$CRAN_REPO" | sudo tee /etc/apt/sources.list.d/r-cran.list > /dev/null
            log_success "CRAN 源已添加"
        else
            log_success "CRAN 源已存在"
        fi

        # 安装
        log_info "安装 R..."
        sudo apt-get update -y
        sudo apt-get install -y r-base-dev

    elif [ "$DISTRO" = "ubuntu" ]; then
        log_info "配置 CRAN 清华镜像源..."

        # 添加 GPG 密钥
        run_with_optional_proxy wget -qO- https://mirrors.tuna.tsinghua.edu.cn/CRAN/bin/linux/ubuntu/marutter_pubkey.asc | \
            gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/cran_ubuntu_key.gpg > /dev/null

        # 添加 CRAN 源
        CRAN_REPO="deb https://mirrors.tuna.tsinghua.edu.cn/CRAN/bin/linux/ubuntu/ ${CODENAME}-cran40/"
        if ! grep -qF "mirrors.tuna.tsinghua.edu.cn/CRAN" /etc/apt/sources.list.d/r-cran.list 2>/dev/null; then
            echo "$CRAN_REPO" | sudo tee /etc/apt/sources.list.d/r-cran.list > /dev/null
            log_success "CRAN 源已添加"
        else
            log_success "CRAN 源已存在"
        fi

        # 安装
        log_info "安装 R..."
        sudo apt-get update -y
        sudo apt-get install -y r-base-dev

    else
        log_error "不支持的发行版: $DISTRO"
        exit 1
    fi

    if command -v R &>/dev/null; then
        log_success "R 安装完成"
    else
        log_error "R 安装失败"
        exit 1
    fi
fi

# ========== 配置 CRAN 镜像 ==========

log_info "配置 R CRAN 镜像..."

R_PROFILE="$HOME/.Rprofile"
R_PROFILE_CONTENT='options("repos" = c(CRAN="https://mirrors.tuna.tsinghua.edu.cn/CRAN/"))'

if [ ! -f "$R_PROFILE" ] || ! grep -qF "mirrors.tuna.tsinghua.edu.cn/CRAN" "$R_PROFILE" 2>/dev/null; then
    if [ -f "$R_PROFILE" ]; then
        # 追加而非覆盖
        echo "" >> "$R_PROFILE"
        echo "$R_PROFILE_CONTENT" >> "$R_PROFILE"
    else
        echo "$R_PROFILE_CONTENT" > "$R_PROFILE"
    fi
    log_success "CRAN 镜像已配置"
else
    log_success "CRAN 镜像已是最新"
fi

# ========== 验证 ==========

echo ""
log_info "R: $(R --version 2>/dev/null | head -n1)"
log_info "CRAN 镜像: $(R --no-save -e 'getOption("repos")' 2>/dev/null | grep -oE 'https://[^ ]+')"
log_success "R 语言环境配置完成"
