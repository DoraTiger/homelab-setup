#!/bin/bash
# DESCRIPTION: Zotero 安装与升级 — 官方 Tarball + 桌面快捷方式（用户级，无需 sudo）

set -e
source "$(dirname "$0")/../common.sh"

# ========== 路径常量 ==========

ZOTERO_INSTALL_DIR="$HOME/.local/opt/zotero"
ZOTERO_CACHE_DIR="$CACHE_DIR/zotero"
ZOTERO_DESKTOP_LINK="$HOME/.local/share/applications/zotero.desktop"
mkdir -p "$ZOTERO_CACHE_DIR" "$HOME/.local/opt" "$HOME/.local/share/applications"

# ========== 辅助函数 ==========

get_installed_zotero_version() {
    local ini="$ZOTERO_INSTALL_DIR/app/application.ini"
    if [ -f "$ini" ]; then
        grep "^Version=" "$ini" 2>/dev/null | cut -d'=' -f2
    fi
}

get_latest_zotero_version() {
    # 从下载页面的 JS JSON 数据中提取 Linux x86_64 版本号
    local page_url="https://www.zotero.org/download/"
    local page
    page=$(run_with_optional_proxy curl -fsSL "$page_url" 2>/dev/null)

    if [ -z "$page" ]; then
        echo ""
        return
    fi

    # 页面中嵌入了 JSON: "linux-x86_64":"9.0.4"
    local ver
    ver=$(echo "$page" | grep -oP '"linux-x86_64":"[^"]*"' | head -1 | cut -d'"' -f4)

    echo "$ver"
}

get_zotero_download_url() {
    # 通过重定向获取实际 tarball 下载地址
    local version="$1"
    local redirect_url
    redirect_url=$(run_with_optional_proxy curl -fsSL -o /dev/null -w "%{url_effective}" \
        --max-time 15 \
        "https://www.zotero.org/download/client/dl?channel=release&platform=linux-x86_64" 2>/dev/null)

    if [ -n "$redirect_url" ] && echo "$redirect_url" | grep -q "download.zotero.org"; then
        echo "$redirect_url"
    else
        # 回退：直接构造 download.zotero.org 地址（尝试 xz 和 bz2）
        echo "https://download.zotero.org/client/release/${version}/Zotero-${version}_linux-x86_64.tar.xz"
    fi
}

get_zotero_archive_ext() {
    # 根据 URL 判断压缩格式
    local url="$1"
    if echo "$url" | grep -q "\.tar\.xz"; then
        echo "xz"
    elif echo "$url" | grep -q "\.tar\.bz2"; then
        echo "bz2"
    else
        echo "xz"
    fi
}

# ========== 1. 获取版本信息 ==========

log_info "检查 Zotero 版本..."

INSTALLED_VER=$(get_installed_zotero_version)
LATEST_VER=$(get_latest_zotero_version)

if [ -z "$LATEST_VER" ]; then
    log_warn "无法获取最新版本信息，跳过"
    [ -n "$INSTALLED_VER" ] && log_info "当前已安装版本: $INSTALLED_VER"
    exit 0
fi

log_info "目标版本: Zotero $LATEST_VER"
[ -n "$INSTALLED_VER" ] && log_info "已安装版本: $INSTALLED_VER"

# ========== 2. 幂等性检查 ==========

if [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
    log_success "Zotero 已是最新版本: $INSTALLED_VER"

    # 验证桌面快捷方式
    if [ -L "$ZOTERO_DESKTOP_LINK" ] && [ -f "$ZOTERO_DESKTOP_LINK" ]; then
        log_success "桌面快捷方式已配置"
    else
        log_warn "桌面快捷方式缺失，重新创建..."
        cd "$ZOTERO_INSTALL_DIR" && ./set_launcher_icon 2>/dev/null || true
        ln -sf "$ZOTERO_INSTALL_DIR/zotero.desktop" "$ZOTERO_DESKTOP_LINK"
        log_success "桌面快捷方式已重建"
    fi

    exit 0
fi

# ========== 3. 下载 Tarball ==========

TARBALL_URL=$(get_zotero_download_url "$LATEST_VER")
ARCHIVE_EXT=$(get_zotero_archive_ext "$TARBALL_URL")
TARBALL_FILE="$ZOTERO_CACHE_DIR/Zotero-${LATEST_VER}_linux-x86_64.tar.${ARCHIVE_EXT}"

if [ -f "$TARBALL_FILE" ]; then
    log_info "使用缓存的 Tarball: $TARBALL_FILE"
else
    log_info "下载 Zotero ${LATEST_VER}..."
    if ! run_with_optional_proxy curl -fSL -o "$TARBALL_FILE" "$TARBALL_URL"; then
        log_error "下载失败: $TARBALL_URL"
        exit 1
    fi
    log_success "下载完成: $TARBALL_FILE"
fi

# ========== 4. 解压安装 ==========

EXTRACT_DIR="$ZOTERO_CACHE_DIR/extract"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"

if [ -z "$INSTALLED_VER" ]; then
    log_info "安装 Zotero ${LATEST_VER}..."
else
    log_info "升级 Zotero: $INSTALLED_VER → $LATEST_VER"
fi

log_info "解压 Tarball..."
case "$ARCHIVE_EXT" in
    xz)  tar -xJf "$TARBALL_FILE" -C "$EXTRACT_DIR" ;;
    bz2) tar -xjf "$TARBALL_FILE" -C "$EXTRACT_DIR" ;;
    *)   tar -xf "$TARBALL_FILE" -C "$EXTRACT_DIR" ;;
esac

# 找到解压后的目录
EXTRACTED=$(find "$EXTRACT_DIR" -maxdepth 1 -type d -name "Zotero*" | head -1)
if [ -z "$EXTRACTED" ] || [ ! -f "$EXTRACTED/zotero" ]; then
    log_error "解压失败：找不到 Zotero 可执行文件"
    exit 1
fi

# 备份旧版本
if [ -d "$ZOTERO_INSTALL_DIR" ]; then
    BACKUP_DIR="${ZOTERO_INSTALL_DIR}.bak.$(date +%s)"
    log_info "备份旧版本: $BACKUP_DIR"
    mv "$ZOTERO_INSTALL_DIR" "$BACKUP_DIR"
fi

# 安装（用户目录，无需 sudo）
mv "$EXTRACTED" "$ZOTERO_INSTALL_DIR"
log_success "Zotero 已安装到 $ZOTERO_INSTALL_DIR"

# ========== 5. 配置桌面快捷方式 ==========

log_info "配置桌面快捷方式..."
cd "$ZOTERO_INSTALL_DIR"
./set_launcher_icon 2>/dev/null || true
ln -sf "$ZOTERO_INSTALL_DIR/zotero.desktop" "$ZOTERO_DESKTOP_LINK"
log_success "桌面快捷方式已创建: $ZOTERO_DESKTOP_LINK"

# ========== 6. 验证 ==========

log_info "验证安装..."

NEW_VER=$(get_installed_zotero_version)
if [ -n "$NEW_VER" ]; then
    log_success "Zotero 安装成功: $NEW_VER"
elif [ -x "$ZOTERO_INSTALL_DIR/zotero" ]; then
    log_success "Zotero 可执行文件存在: $ZOTERO_INSTALL_DIR/zotero"
else
    log_error "Zotero 安装失败"
    exit 1
fi

if [ -L "$ZOTERO_DESKTOP_LINK" ] && [ -f "$ZOTERO_DESKTOP_LINK" ]; then
    log_success "桌面快捷方式验证通过"
else
    log_warn "桌面快捷方式可能需要重新创建"
fi

# ========== 7. 清理 ==========

rm -rf "$EXTRACT_DIR"

# 保留最近 2 个 tarball
cd "$ZOTERO_CACHE_DIR" 2>/dev/null && \
    ls -t Zotero_*.tar.* 2>/dev/null | tail -n +3 | xargs -r rm -f

# 清理旧的备份（保留最近 1 个）
OLD_BAK=$(ls -dt "$HOME/.local/opt/zotero.bak."* 2>/dev/null | tail -n +2)
if [ -n "$OLD_BAK" ]; then
    log_info "清理旧版本备份..."
    echo "$OLD_BAK" | xargs -r rm -rf
fi

log_success "Zotero 安装完成"
