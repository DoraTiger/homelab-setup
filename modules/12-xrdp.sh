#!/bin/bash
# DESCRIPTION: XRDP 远程桌面配置 — XFCE 并发会话 + 独立密钥环 + Fcitx5

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MODULE_DIR/../common.sh"
source "$MODULE_DIR/../lib/xrdp-config.sh"

# ========== 路径与依赖常量 ==========

XRDP_PACKAGES=(
    xrdp xorgxrdp xfce4 xfce4-goodies dbus-x11
    gnome-keyring libsecret-1-0 libpam-gnome-keyring libsecret-tools
    fcitx5 fcitx5-chinese-addons fcitx5-frontend-all fcitx5-config-qt im-config
)

RUN_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
XRDP_BACKUP_DIR="$BACKUP_DIR/xrdp/$RUN_TIMESTAMP"
backup_ready=0

# ========== 辅助函数 ==========

ensure_backup_dir() {
    if [ "$backup_ready" -eq 0 ]; then
        # 所有迁移备份集中在工作区 backup/，不在 /etc、/var 或 HOME 中散落。
        install -d -m 700 "$XRDP_BACKUP_DIR"
        backup_ready=1
    fi
}

backup_system_file() {
    local source_file="$1"
    local backup_name="${2:-$(basename "$source_file")}"
    [ -e "$source_file" ] || return 0
    ensure_sudo
    ensure_backup_dir
    sudo cp -a "$source_file" "$XRDP_BACKUP_DIR/$backup_name"
    log_info "已备份系统配置: $XRDP_BACKUP_DIR/$backup_name"
}

backup_user_file() {
    local source_file="$1"
    local backup_name="${2:-$(basename "$source_file")}"
    [ -e "$source_file" ] || return 0
    ensure_backup_dir
    cp -a "$source_file" "$XRDP_BACKUP_DIR/$backup_name"
    log_info "已备份用户配置: $XRDP_BACKUP_DIR/$backup_name"
}

install_rendered_system_file() {
    local target_file="$1" mode="$2" renderer="$3"
    shift 3
    local temp_file content_changed=1 metadata_changed=1

    temp_file="$(mktemp)"
    "$renderer" "$@" > "$temp_file"
    if [ -f "$target_file" ] && cmp -s "$temp_file" "$target_file"; then
        content_changed=0
    fi
    if [ -f "$target_file" ] && [ "$(stat -c '%a:%U:%G' "$target_file")" = "$mode:root:root" ]; then
        metadata_changed=0
    fi

    if [ "$content_changed" -eq 0 ] && [ "$metadata_changed" -eq 0 ]; then
        log_success "系统配置已是最新: $target_file"
        rm -f "$temp_file"
        return 0
    fi
    [ "$content_changed" -eq 0 ] || backup_system_file "$target_file"
    ensure_sudo
    sudo install -m "$mode" -o root -g root "$temp_file" "$target_file"
    rm -f "$temp_file"
    log_success "系统配置已更新: $target_file"
}

configure_startwm() {
    local target_file="/etc/xrdp/startwm.sh"

    # 已具备私有 D-Bus 启动链时保留原文件，只收敛权限与所有权。
    if xrdp_startwm_is_usable "$target_file"; then
        if [ "$(stat -c '%a:%U:%G' "$target_file")" != "755:root:root" ]; then
            ensure_sudo
            sudo chown root:root "$target_file"
            sudo chmod 755 "$target_file"
            log_success "保留现有 XRDP startwm 内容并修正权限"
        else
            log_success "XRDP startwm 启动链已是最新"
        fi
        return 0
    fi

    install_rendered_system_file "$target_file" 755 render_xrdp_startwm
}

configure_sesman() {
    local target_file="/etc/xrdp/sesman.ini" temp_file
    [ -f "$target_file" ] || { log_error "未找到 XRDP 会话配置: $target_file"; return 1; }

    temp_file="$(mktemp)"
    # 在临时副本上只修改 [Sessions] 中的目标键，其他段落原样保留。
    cp "$target_file" "$temp_file"
    converge_xrdp_sessions "$temp_file"
    if cmp -s "$temp_file" "$target_file"; then
        log_success "XRDP 并发会话策略已是最新"
    else
        backup_system_file "$target_file" sesman.ini
        ensure_sudo
        sudo install -m 640 -o root -g xrdp "$temp_file" "$target_file"
        log_success "XRDP 并发会话策略已更新"
    fi
    rm -f "$temp_file"
}

configure_fcitx_profile() {
    local profile_file="$HOME/.profile" temp_file
    # 兼容用户已经手工配置但未带 homelab 标记的有效环境变量。
    if file_has_fcitx5_environment "$profile_file"; then
        log_success "Fcitx5 环境变量已配置"
        return 0
    fi

    temp_file="$(mktemp)"
    if [ -f "$profile_file" ]; then cp -a "$profile_file" "$temp_file"; fi
    ensure_fcitx_profile "$temp_file"
    backup_user_file "$profile_file" profile
    install -m "$(stat -c '%a' "$temp_file")" "$temp_file" "$profile_file"
    rm -f "$temp_file"
    log_success "Fcitx5 环境变量已写入: $profile_file"
}

configure_fcitx_autostart() {
    local autostart_file="$HOME/.config/autostart/fcitx5.desktop" temp_file
    # 有效的用户自启动文件保持不动；仅修复缺失或不可用配置。
    if fcitx5_autostart_is_usable "$autostart_file"; then
        log_success "Fcitx5 Xfce 自启动已配置"
        return 0
    fi

    temp_file="$(mktemp)"
    render_fcitx5_autostart > "$temp_file"
    backup_user_file "$autostart_file" fcitx5.desktop
    install -d -m 700 "$(dirname "$autostart_file")"
    install -m 644 "$temp_file" "$autostart_file"
    rm -f "$temp_file"
    log_success "Fcitx5 Xfce 自启动已写入: $autostart_file"
}

cleanup_known_legacy_files() {
    local xsession_file="$HOME/.xsession"
    local polkit_file="/etc/polkit-1/rules.d/50-networkmanager.rules"
    local known_polkit_content

    if [ -f "$xsession_file" ]; then
        if [ "$(cat "$xsession_file")" = "startxfce4" ]; then
            ensure_backup_dir
            migrate_known_legacy_file "$xsession_file" startxfce4 "$XRDP_BACKUP_DIR"
            log_info "旧版 .xsession 已移入备份目录"
        else
            log_warn "保留非受管 .xsession，请自行确认: $xsession_file"
        fi
    fi

    known_polkit_content='polkit.addRule(function(action, subject) {
    if (
        subject.isInGroup("sudo") &&
        action.id.indexOf("org.freedesktop.NetworkManager") == 0
    ) {
        return polkit.Result.YES;
    }
});'
    if [ -f "$polkit_file" ]; then
        if [ "$(cat "$polkit_file")" = "$known_polkit_content" ]; then
            ensure_backup_dir
            sudo mv "$polkit_file" "$XRDP_BACKUP_DIR/50-networkmanager.rules.removed"
            log_info "旧版 NetworkManager Polkit 规则已移入备份目录"
        else
            log_warn "保留非受管 Polkit 规则，请自行审查: $polkit_file"
        fi
    fi
}

validate_pam_keyring() {
    local pam_file="/etc/pam.d/xrdp-sesman"
    if grep -Eq '^[[:space:]-]*auth[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so' "$pam_file" 2>/dev/null &&
        grep -Eq '^[[:space:]-]*session[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so([[:space:]]+auto_start)?' "$pam_file" 2>/dev/null; then
        log_success "XRDP PAM 密钥环集成已存在"
    else
        log_warn "未自动修改 PAM：$pam_file 缺少完整的 pam_gnome_keyring 配置"
    fi
}

# ========== 1. 安装核心依赖 ==========

log_info "检查 XRDP、Xfce、密钥环与 Fcitx5 依赖..."
missing_packages=()
for package_name in "${XRDP_PACKAGES[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q '^install ok installed$'; then
        missing_packages+=("$package_name")
    fi
done
if [ "${#missing_packages[@]}" -gt 0 ]; then
    ensure_sudo
    log_info "安装缺少的软件包: ${missing_packages[*]}"
    sudo apt-get update
    sudo apt-get install -y "${missing_packages[@]}"
else
    log_success "XRDP 核心依赖均已安装"
fi

# ========== 2. 配置并发 XRDP 会话 ==========

configure_sesman

# ========== 3. 配置私有 D-Bus 与密钥环 ==========

configure_startwm
install_rendered_system_file /usr/local/bin/xrdp-xfce-session 755 render_xrdp_xfce_session

# ========== 4. 配置 Fcitx5 中文输入 ==========

configure_fcitx_profile
configure_fcitx_autostart

# ========== 5. 清理已知旧版受管配置 ==========

# 只有内容与旧模块完全一致时才迁移；用户自行维护的文件只提示、不修改。
cleanup_known_legacy_files

# ========== 6. 检查 PAM 密钥环集成 ==========

# Debian 软件包通常已提供 PAM 配置；这里仅验证，避免自动改写认证链。
validate_pam_keyring

# ========== 7. 启用 XRDP 服务 ==========

# 仅在需要时启用或首次启动服务。配置更新后不自动 restart/reload，
# 避免中断已经存在的本地或 RDP 会话。
if systemctl is-enabled xrdp >/dev/null 2>&1; then
    log_success "XRDP 服务已设为开机自启"
else
    ensure_sudo
    sudo systemctl enable xrdp
    log_success "XRDP 服务已设为开机自启"
fi
if systemctl is-active xrdp >/dev/null 2>&1; then
    log_success "XRDP 服务正在运行（未执行 reload/restart）"
else
    ensure_sudo
    sudo systemctl start xrdp
    log_success "XRDP 服务已启动"
fi

# ========== 8. 完成提示 ==========

log_success "XRDP 核心配置已完成"
log_info "请在方便时自行建立新 RDP 会话，验证中文输入与密钥环持久化"
