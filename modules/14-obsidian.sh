#!/bin/bash
# DESCRIPTION: Obsidian 安装与升级 — 官方 Deb 包 + CLI 验证

set -e
source "$(dirname "$0")/../common.sh"

# ========== 路径常量 ==========

OBSIDIAN_CACHE_DIR="$CACHE_DIR/obsidian"
mkdir -p "$OBSIDIAN_CACHE_DIR"

# ========== 辅助函数 ==========

get_installed_obsidian_version() {
    dpkg -s obsidian 2>/dev/null | grep -i "^Version:" | awk '{print $2}'
}

get_latest_obsidian_version() {
    local releases_url="https://raw.githubusercontent.com/obsidianmd/obsidian-releases/master/desktop-releases.json"
    local version
    version=$(run_with_optional_proxy curl -fsSL "$releases_url" 2>/dev/null |
        grep -o '"latestVersion": *"[^"]*"' | head -1 | cut -d'"' -f4)
    [ -n "$version" ] && printf 'v%s\n' "$version"
}

get_obsidian_deb_url() {
    local version_tag="$1"
    local api_url="https://api.github.com/repos/obsidianmd/obsidian-releases/releases/tags/$version_tag"
    run_with_optional_proxy curl -fsSL "$api_url" 2>/dev/null |
        grep -o '"browser_download_url": *"[^"]*_amd64\.deb"' |
        head -1 | cut -d'"' -f4
}

# ========== 1. 获取版本信息 ==========

log_info "检查 Obsidian 版本..."

INSTALLED_VER=$(get_installed_obsidian_version)
if [ -n "$INSTALLED_VER" ] && ! upgrade_requested; then
    log_success "Obsidian 已安装: $INSTALLED_VER"
    log_info "默认模式不联网检查或升级 Obsidian"
    if command -v obsidian &>/dev/null; then
        log_success "Obsidian CLI 可用: $(command -v obsidian)"
    else
        log_info "如需 CLI，请在 Obsidian 设置 → 通用 → 命令行界面中启用"
    fi
    exit 0
fi
LATEST_VER=$(get_latest_obsidian_version)

if [ -z "$LATEST_VER" ]; then
    log_warn "无法获取最新版本信息，跳过"
    if [ -n "$INSTALLED_VER" ]; then
        log_info "当前已安装版本: $INSTALLED_VER"
    fi
    exit 0
fi

log_info "最新版本: $LATEST_VER"
[ -n "$INSTALLED_VER" ] && log_info "已安装版本: $INSTALLED_VER"

# ========== 2. 幂等性检查 ==========

# 去掉 tag 前缀 v 比较版本号
LATEST_NUM="${LATEST_VER#v}"
INSTALLED_NUM="${INSTALLED_VER#v}"

if [ "$INSTALLED_NUM" = "$LATEST_NUM" ]; then
    log_success "Obsidian 已是最新版本: $INSTALLED_VER"

    # 验证 CLI 可用
    if command -v obsidian &>/dev/null; then
        log_success "Obsidian CLI 可用: $(which obsidian)"
    else
        log_warn "Obsidian CLI 不在 PATH 中，尝试启用..."
        log_info "请在 Obsidian 设置 → 通用 → 命令行界面 中启用 CLI"
    fi

    exit 0
fi

# ========== 3. 下载 Deb 包 ==========

DEB_FILE="$OBSIDIAN_CACHE_DIR/obsidian_${LATEST_NUM}_amd64.deb"
DEB_URL=$(get_obsidian_deb_url "$LATEST_VER")
[ -n "$DEB_URL" ] || { log_error "未找到 Obsidian $LATEST_VER 的 amd64 Deb 资产"; exit 1; }

if [ -f "$DEB_FILE" ] && dpkg-deb --info "$DEB_FILE" &>/dev/null; then
    log_info "使用缓存的 Deb 包: $DEB_FILE"
else
    [ ! -e "$DEB_FILE" ] || { log_warn "删除无效的 Obsidian Deb 缓存"; rm -f "$DEB_FILE"; }
    log_info "下载 Obsidian ${LATEST_VER}..."
    if ! run_with_optional_proxy curl -fSL -o "$DEB_FILE" "$DEB_URL"; then
        log_error "下载失败: $DEB_URL"
        exit 1
    fi
    dpkg-deb --info "$DEB_FILE" &>/dev/null || { log_error "下载的 Deb 包校验失败"; exit 1; }
    log_success "下载完成: $DEB_FILE"
fi

# ========== 4. 安装 ==========

ensure_sudo

if [ -z "$INSTALLED_VER" ]; then
    log_info "安装 Obsidian ${LATEST_VER}..."
else
    log_info "升级 Obsidian: $INSTALLED_VER → $LATEST_VER"
fi

sudo apt-get install -y "$DEB_FILE"

# ========== 5. 验证 ==========

log_info "验证安装..."

NEW_VER=$(get_installed_obsidian_version)
if [ "$NEW_VER" = "$LATEST_NUM" ]; then
    log_success "Obsidian 安装成功: $NEW_VER"
else
    log_error "安装后版本不匹配: 期望 $LATEST_NUM, 实际 $NEW_VER"
    exit 1
fi

# 验证 CLI
if command -v obsidian &>/dev/null; then
    CLI_VER=$(obsidian version 2>/dev/null || echo "unknown")
    log_success "Obsidian CLI 可用: $(which obsidian) ($CLI_VER)"
else
    log_warn "Obsidian CLI 不在 PATH 中"
    log_info "请在 Obsidian 设置 → 通用 → 命令行界面 中启用 CLI"
    log_info "启用后 CLI 会自动链接到 ~/.local/bin/obsidian"
fi

log_success "Obsidian 安装完成"
