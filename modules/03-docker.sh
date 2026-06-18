#!/bin/bash
# DESCRIPTION: Docker 安装与配置 — Docker CE + Docker Compose + 国内镜像加速

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

# ========== 清理旧版本 ==========

if dpkg -l docker.io podman-docker 2>/dev/null | grep -q "^ii"; then
    echo ""
    log_warn "检测到旧版 Docker/Podman 残留:"
    dpkg -l | grep -E "docker\.io|podman-docker" | awk '{print "    " $2 " (" $3 ")"}'
    echo ""
    if prompt_yesno "是否卸载旧版 Docker/Podman?" "n"; then
        ensure_sudo
        sudo apt remove -y docker.io docker-compose docker-doc podman-docker containerd runc 2>/dev/null || true
        log_success "旧版已卸载"
    else
        log_info "跳过旧版清理"
    fi
fi

# ========== 检测 Docker 安装状态 ==========

if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
    log_success "Docker 已安装: $DOCKER_VER"

    COMPOSE_VER=$(docker compose version 2>/dev/null | awk '{print $NF}')
    [ -n "$COMPOSE_VER" ] && log_success "Docker Compose: $COMPOSE_VER"

    # 尝试升级
    log_info "检查 Docker 升级..."
    ensure_sudo
    sudo apt-get update -y -qq
    UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -E "docker-ce|containerd|docker-compose|docker-buildx" | head -n1)
    if [ -n "$UPGRADABLE" ]; then
        log_info "发现 Docker 新版本，正在升级..."
        sudo apt-get install --only-upgrade -y docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin
        log_success "Docker 升级完成"
    else
        log_success "Docker 已是最新版本"
    fi
else
    # 安装 Docker CE
    log_info "安装 Docker CE..."
    ensure_sudo

    # 安装依赖
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl

    # 添加 GPG 密钥
    sudo install -m 0755 -d /etc/apt/keyrings
    run_with_optional_proxy curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # 添加清华镜像源
    sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.gpg
EOF

    # 安装
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    log_success "Docker CE 安装完成"
fi

# ========== 配置 Docker Daemon ==========

log_info "配置 Docker Daemon..."

DOCKER_DAEMON="/etc/docker/daemon.json"
SUDO=""
[ "$EUID" -ne 0 ] && SUDO="sudo"

# 构建配置（幂等：比对内容再写入）
DAEMON_CONFIG=$(cat <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ]
}
EOF
)

if [ -f "$DOCKER_DAEMON" ]; then
    # 简单比对（去掉空白后比较）
    EXISTING=$(cat "$DOCKER_DAEMON" | tr -d '[:space:]')
    NEW=$(echo "$DAEMON_CONFIG" | tr -d '[:space:]')
    if [ "$EXISTING" = "$NEW" ]; then
        log_success "Docker Daemon 配置已是最新，跳过"
    else
        log_warn "Docker Daemon 配置已存在但内容不同"
        if prompt_yesno "是否覆盖为推荐配置?" "y"; then
            $SUDO cp "$DOCKER_DAEMON" "${DOCKER_DAEMON}.bak"
            echo "$DAEMON_CONFIG" | $SUDO tee "$DOCKER_DAEMON" > /dev/null
            $SUDO systemctl restart docker
            log_success "Docker Daemon 已重启"
        fi
    fi
else
    echo "$DAEMON_CONFIG" | $SUDO tee "$DOCKER_DAEMON" > /dev/null
    $SUDO systemctl restart docker
    log_success "Docker Daemon 已配置并重启"
fi

# ========== 将当前用户加入 docker 组 ==========

if ! groups "$USER" | grep -qw docker; then
    log_info "将 $USER 加入 docker 组"
    ensure_sudo
    sudo usermod -aG docker "$USER"
    log_success "用户已加入 docker 组，重新登录后生效"
else
    log_success "$USER 已在 docker 组中"
fi

log_success "Docker 配置完成"
