#!/bin/bash
# DESCRIPTION: TeX Live 安装与配置 — 全量安装 + 清华 CTAN 镜像

set -e
source "$(dirname "$0")/../common.sh"

# ========== 路径常量 ==========

TEXLIVE_YEAR="2026"
TEXLIVE_DIR="$HOME/.local/opt/texlive/$TEXLIVE_YEAR"
TEXLIVE_BIN="$TEXLIVE_DIR/bin/x86_64-linux"
CTAN_REPO="https://mirrors.tuna.tsinghua.edu.cn/CTAN/systems/texlive/tlnet"

# ========== 检查依赖 ==========

if ! command -v perl &>/dev/null; then
    log_error "Perl 未安装，请先执行 08-perl-cpan 模块"
    exit 1
fi

# ========== 安装 TeX Live ==========

if [ -f "$TEXLIVE_BIN/tex" ]; then
    log_success "TeX Live 已安装: $TEXLIVE_DIR"
else
    log_info "安装 TeX Live（全量安装，约需 10-20 分钟）..."

    INSTALLER_DIR="$PACKAGES_DIR/texlive"
    mkdir -p "$INSTALLER_DIR"

    # 下载 install-tl.zip
    INSTALLER_ZIP="$INSTALLER_DIR/install-tl.zip"
    if [ ! -f "$INSTALLER_ZIP" ]; then
        log_info "下载 install-tl.zip..."
        run_with_optional_proxy curl -fsSL -o "$INSTALLER_ZIP" \
            "$CTAN_REPO/install-tl.zip"
        log_success "安装包已缓存: $INSTALLER_ZIP"
    else
        log_info "使用缓存的安装包: $INSTALLER_ZIP"
    fi

    # 解压
    INSTALLER_TMP="$INSTALLER_DIR/install-tl-tmp"
    rm -rf "$INSTALLER_TMP"
    mkdir -p "$INSTALLER_TMP"
    unzip -q -o "$INSTALLER_ZIP" -d "$INSTALLER_TMP"

    # 找到 install-tl 脚本
    INSTALLER_SCRIPT=$(find "$INSTALLER_TMP" -name "install-tl" -type f | head -n1)
    if [ -z "$INSTALLER_SCRIPT" ]; then
        log_error "找不到 install-tl 脚本"
        rm -rf "$INSTALLER_TMP"
        exit 1
    fi

    # 生成 profile 文件
    PROFILE="$INSTALLER_TMP/texlive.profile"
    cat > "$PROFILE" <<EOF
# TeX Live profile (managed by homelab setup)
selected_scheme scheme-full
TEXDIR $TEXLIVE_DIR
TEXMFCONFIG ~/.texlive/${TEXLIVE_YEAR}/texmf-config
TEXMFHOME ~/texmf
TEXMFLOCAL ~/.texlive/${TEXLIVE_YEAR}/texmf-local
TEXMFSYSCONFIG ~/.texlive/${TEXLIVE_YEAR}/texmf-config
TEXMFSYSVAR ~/.texlive/${TEXLIVE_YEAR}/texmf-var
TEXMFVAR ~/.texlive/${TEXLIVE_YEAR}/texmf-var
binary_x86_64-linux 1
instopt_adjustpath 0
instopt_adjustrepo 1
instopt_letter 0
instopt_portable 0
instopt_write18_restricted 1
tlpdbopt_autobackup 0
tlpdbopt_create_formats 1
tlpdbopt_desktop_integration 0
tlpdbopt_file_assocs 0
tlpdbopt_generate_updmap 1
tlpdbopt_install_docfiles 1
tlpdbopt_install_srcfiles 1
tlpdbopt_post_code 1
tlpdbopt_sys_bin /usr/local/bin
tlpdbopt_sys_info /usr/local/share/info
tlpdbopt_sys_man /usr/local/share/man
tlpdbopt_w32_multi_user 0
EOF

    # 执行安装
    log_info "开始安装（全量方案，首次安装约 10-20 分钟）..."
    perl "$INSTALLER_SCRIPT" \
        --profile="$PROFILE" \
        --repository="$CTAN_REPO" \
        --texdir="$TEXLIVE_DIR"

    # 清理临时文件
    rm -rf "$INSTALLER_TMP"

    if [ -f "$TEXLIVE_BIN/tex" ]; then
        log_success "TeX Live 安装完成"
    else
        log_error "TeX Live 安装失败"
        exit 1
    fi
fi

# ========== 配置环境变量 ==========

log_info "配置 TeX Live shell 环境..."

TEX_ENV_FILE="$HOME/.bashrc.d/texlive.sh"
mkdir -p "$HOME/.bashrc.d"

TEX_ENV_CONTENT="# TeX Live environment (managed by homelab setup)
export PATH=\"$TEXLIVE_BIN:\$PATH\"
export MANPATH=\"\$TEXLIVE_DIR/texmf-dist/doc/man:\$MANPATH\"
export INFOPATH=\"\$TEXLIVE_DIR/texmf-dist/doc/info:\$INFOPATH\""

if [ ! -f "$TEX_ENV_FILE" ] || [ "$(cat "$TEX_ENV_FILE")" != "$TEX_ENV_CONTENT" ]; then
    echo "$TEX_ENV_CONTENT" > "$TEX_ENV_FILE"
    log_success "TeX Live 环境变量已写入 $TEX_ENV_FILE"
else
    log_success "TeX Live 环境变量已是最新"
fi

ensure_bashrc_d_loader

# ========== 配置 tlmgr 镜像 ==========

log_info "配置 tlmgr 清华镜像..."

export PATH="$TEXLIVE_BIN:$PATH"
if command -v tlmgr &>/dev/null; then
    # 设置仓库源
    tlmgr option repository "$CTAN_REPO" 2>/dev/null || true
    # 关闭自动备份（节省空间）
    tlmgr option autobackup 0 2>/dev/null || true
    log_success "tlmgr 镜像已配置: $CTAN_REPO"
else
    log_warn "tlmgr 未找到，跳过镜像配置"
fi

# ========== 升级 ==========

log_info "检查 TeX Live 升级..."
export PATH="$TEXLIVE_BIN:$PATH"
tlmgr update --all 2>/dev/null || true

# ========== 验证 ==========

echo ""
log_info "TeX Live: $(tex --version 2>/dev/null | head -n1)"
log_info "tlmgr: $(tlmgr --version 2>/dev/null | head -n1)"
log_info "安装目录: $TEXLIVE_DIR"
log_info "清华镜像: $CTAN_REPO"
log_success "TeX Live 环境配置完成"
