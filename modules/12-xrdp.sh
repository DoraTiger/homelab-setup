#!/bin/bash
# DESCRIPTION: XRDP 远程桌面配置 — XFCE 桌面 + polkit WiFi 修复

set -e
source "$(dirname "$0")/../common.sh"

# ========== sudo 权限 ==========

ensure_sudo() {
    if [ "$EUID" -eq 0 ]; then return 0; fi
    if ! command -v sudo &>/dev/null; then
        log_error "sudo 未安装"
        exit 1
    fi
    sudo -v 2>/dev/null || { log_error "sudo 验证失败"; exit 1; }
}

# ========== 安装 XRDP ==========

if dpkg -s xrdp &>/dev/null; then
    log_success "XRDP 已安装"
else
    log_info "安装 XRDP..."
    ensure_sudo
    sudo apt-get update -y
    sudo apt-get install -y xrdp
    log_success "XRDP 安装完成"
fi

# ========== 配置 xsession ==========

log_info "配置 xsession..."

XSESSION_FILE="$HOME/.xsession"
if [ -f "$XSESSION_FILE" ] && grep -q "startxfce4" "$XSESSION_FILE" 2>/dev/null; then
    log_success "xsession 已配置"
else
    echo "startxfce4" > "$XSESSION_FILE"
    chmod +x "$XSESSION_FILE"
    log_success "xsession 已写入: startxfce4"
fi

# ========== 修复 XRDP WiFi 扫描授权问题 ==========

log_info "检查 polkit WiFi 修复..."

POLKIT_RULE="/etc/polkit-1/rules.d/50-networkmanager.rules"
POLKIT_CONTENT='polkit.addRule(function(action, subject) {
    if (
        subject.isInGroup("sudo") &&
        action.id.indexOf("org.freedesktop.NetworkManager") == 0
    ) {
        return polkit.Result.YES;
    }
});'

if [ -f "$POLKIT_RULE" ] && grep -qF "org.freedesktop.NetworkManager" "$POLKIT_RULE" 2>/dev/null; then
    log_success "polkit WiFi 修复已配置"
else
    ensure_sudo
    echo "$POLKIT_CONTENT" | sudo tee "$POLKIT_RULE" > /dev/null
    log_success "polkit WiFi 修复已添加"

    # 重启相关服务
    sudo systemctl restart polkit 2>/dev/null || true
    sudo systemctl restart NetworkManager 2>/dev/null || true
    log_info "polkit 和 NetworkManager 已重启"
fi

# ========== 启用 XRDP 服务 ==========

log_info "配置 XRDP 服务..."

if systemctl is-enabled xrdp &>/dev/null; then
    log_success "XRDP 服务已启用"
else
    ensure_sudo
    sudo systemctl enable xrdp
    log_success "XRDP 服务已设为开机自启"
fi

if systemctl is-active xrdp &>/dev/null; then
    log_success "XRDP 服务运行中"
else
    ensure_sudo
    sudo systemctl start xrdp
    log_success "XRDP 服务已启动"
fi

# ========== 验证 ==========

echo ""
log_info "XRDP 状态: $(systemctl is-active xrdp 2>/dev/null)"
log_info "监听端口: $(ss -tlnp | grep :3389 | awk '{print $4}')"
log_info "桌面环境: XFCE4"
log_info "连接方式: 远程桌面客户端 → $(hostname -I | awk '{print $1}'):3389"
log_success "XRDP 配置完成"
