#!/bin/bash
# DESCRIPTION: Miniconda 安装与配置 — Python 环境管理 + 清华镜像加速

set -e
source "$(dirname "$0")/../common.sh"

# ========== 禁止 root ==========

if [ "$EUID" -eq 0 ]; then
    log_error "禁止以 root 身份运行 Miniconda 安装"
    exit 1
fi

# ========== 路径常量 ==========

INSTALL_DIR="$HOME/.local/opt/miniconda3"
INSTALLER_DIR="$PACKAGES_DIR/miniconda"
INSTALLER="$INSTALLER_DIR/Miniconda3-latest-Linux-x86_64.sh"
MINICONDA_URL="https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh"
CONDA_PACKAGE_CACHE_DIR="$CACHE_DIR/conda/pkgs"
PIP_CACHE_DIR="$CACHE_DIR/pip"
CONDA_FORGE_CHANNEL="https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge/"
CONDA_MAIN_CHANNEL="https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main/"

mkdir -p "$CONDA_PACKAGE_CACHE_DIR" "$PIP_CACHE_DIR"

# ========== 配置镜像源 ==========

log_info "配置 conda/pip 清华镜像..."

# condarc
CONDA_CONF="$HOME/.condarc"
CONDA_CONF_CONTENT="channels:
  - $CONDA_FORGE_CHANNEL
  - $CONDA_MAIN_CHANNEL
show_channel_urls: true
channel_priority: strict
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
pkgs_dirs:
  - $CONDA_PACKAGE_CACHE_DIR"

if [ ! -f "$CONDA_CONF" ] || [ "$(cat "$CONDA_CONF")" != "$CONDA_CONF_CONTENT" ]; then
    echo "$CONDA_CONF_CONTENT" > "$CONDA_CONF"
    log_success "condarc 已更新"
else
    log_success "condarc 已是最新"
fi

# pip.conf
PIPCONF_DIR="$HOME/.pip"
PIPCONF_FILE="$PIPCONF_DIR/pip.conf"
PIPCONF_CONTENT="[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
cache-dir = $PIP_CACHE_DIR"

if [ ! -f "$PIPCONF_FILE" ] || [ "$(cat "$PIPCONF_FILE")" != "$PIPCONF_CONTENT" ]; then
    mkdir -p "$PIPCONF_DIR"
    echo "$PIPCONF_CONTENT" > "$PIPCONF_FILE"
    log_success "pip.conf 已更新"
else
    log_success "pip.conf 已是最新"
fi

# ========== 安装 Miniconda ==========

if [ -f "$INSTALL_DIR/bin/conda" ]; then
    CONDA_VER=$("$INSTALL_DIR/bin/conda" --version 2>/dev/null | awk '{print $2}')
    log_success "Miniconda 已安装: $CONDA_VER ($INSTALL_DIR)"

    if upgrade_requested; then
        # 只升级 base 环境；不修改用户创建的独立环境。
        log_info "升级模式已开启，更新 Miniconda base 环境..."
        "$INSTALL_DIR/bin/conda" update -n base --override-channels \
            -c "$CONDA_MAIN_CHANNEL" conda -y
        "$INSTALL_DIR/bin/conda" update -n base --all --override-channels \
            -c "$CONDA_FORGE_CHANNEL" -c "$CONDA_MAIN_CHANNEL" -y
        NEW_VER=$("$INSTALL_DIR/bin/conda" --version 2>/dev/null | awk '{print $2}')
        log_success "Miniconda 升级检查完成: $CONDA_VER → $NEW_VER"
    else
        log_info "默认模式保留现有 Miniconda 版本"
    fi
else
    # 下载安装包（缓存到 packages/）
    mkdir -p "$INSTALLER_DIR"
    download_package "$MINICONDA_URL" "$INSTALLER" validate_shell_script

    chmod +x "$INSTALLER"

    # 静默安装到 ~/.local/opt/miniconda3
    log_info "安装 Miniconda 到 $INSTALL_DIR ..."
    bash "$INSTALLER" -b -p "$INSTALL_DIR" >/dev/null
    log_success "Miniconda 安装完成"
fi

# ========== 初始化 Shell ==========

log_info "配置 conda shell 环境..."

CONDA_PROFILE_CONTENT="# Conda environment (managed by homelab setup)
homelab_path_prepend \"$INSTALL_DIR/bin\""
write_profile_env_file conda "$CONDA_PROFILE_CONTENT"

# 写入 .bashrc.d/conda.sh
CONDA_ENV_FILE="$HOME/.bashrc.d/conda.sh"
mkdir -p "$HOME/.bashrc.d"

CONDA_ENV_CONTENT="# Conda environment (managed by homelab setup)
# initialize conda for interactive shell
__conda_setup=\"\$('$INSTALL_DIR/bin/conda' 'shell.bash' 'hook' 2> /dev/null)\"
if [ \$? -eq 0 ]; then
    eval \"\$__conda_setup\"
else
    if [ -f \"$INSTALL_DIR/etc/profile.d/conda.sh\" ]; then
        . \"$INSTALL_DIR/etc/profile.d/conda.sh\"
    else
        export PATH=\"$INSTALL_DIR/bin:\$PATH\"
    fi
fi
unset __conda_setup"

if [ ! -f "$CONDA_ENV_FILE" ] || [ "$(cat "$CONDA_ENV_FILE")" != "$CONDA_ENV_CONTENT" ]; then
    echo "$CONDA_ENV_CONTENT" > "$CONDA_ENV_FILE"
    log_success "conda 初始化已写入 $CONDA_ENV_FILE"
else
    log_success "conda 初始化已是最新"
fi

# 从 .bashrc 中移除 conda init 块（如果存在）
CONDA_INIT_MARKER="# >>> conda initialize >>>"
if grep -qF "$CONDA_INIT_MARKER" "$HOME/.bashrc" 2>/dev/null; then
    log_info "从 .bashrc 中移除 conda init 块..."
    sed -i '/# >>> conda initialize >>>/,/# <<< conda initialize <<</d' "$HOME/.bashrc"
    log_success "已清理 .bashrc 中的 conda init 块"
fi

# 确保 .bashrc 加载 .bashrc.d/
ensure_bashrc_d_loader

# ========== 验证 ==========

echo ""
log_info "当前 conda 环境:"
"$INSTALL_DIR/bin/conda" info --base 2>/dev/null | sed 's/^/    /'
echo ""
log_info "激活方式: source ~/.bashrc 或 source $INSTALL_DIR/etc/profile.d/conda.sh"
log_success "Miniconda 配置完成"
