#!/bin/bash
# DESCRIPTION: Java + Maven 环境配置 — SDKMAN 管理 + 阿里云镜像加速
#
# sudo 依赖: 仅在 zip/unzip/curl 未安装时需要 sudo 权限安装系统依赖
#            SDKMAN 本身安装到用户目录，不需要 root

set -e
source "$(dirname "$0")/../common.sh"

# ========== 禁止 root ==========

if [ "$EUID" -eq 0 ]; then
    log_error "禁止以 root 身份运行 SDKMAN 安装"
    exit 1
fi

# ========== 路径常量 ==========

SDKMAN_DIR="$HOME/.local/opt/sdkman"
MAVEN_CACHE_DIR="$CACHE_DIR/maven"

mkdir -p "$MAVEN_CACHE_DIR"

# ========== 1. 安装 SDKMAN ==========

if [ -f "$SDKMAN_DIR/bin/sdkman-init.sh" ]; then
    log_success "SDKMAN 已安装: $SDKMAN_DIR"
else
    # 检查系统依赖（zip/unzip/curl），缺少时需要 sudo 安装
    MISSING=()
    for pkg in zip unzip curl; do
        dpkg -s "$pkg" &>/dev/null || MISSING+=("$pkg")
    done
    if [ ${#MISSING[@]} -gt 0 ]; then
        log_info "安装系统依赖: ${MISSING[*]}（需要 sudo 权限）"
        sudo apt-get install -y "${MISSING[@]}"
    fi

    log_info "安装 SDKMAN..."
    export SDKMAN_DIR="$SDKMAN_DIR"
    curl -s "https://get.sdkman.io" | bash
    log_success "SDKMAN 安装完成"
fi

# 加载 SDKMAN 环境
export SDKMAN_DIR="$SDKMAN_DIR"
# shellcheck source=/dev/null
source "$SDKMAN_DIR/bin/sdkman-init.sh"

# SDKMAN 自升级
log_info "检查 SDKMAN 升级..."
sdk selfupdate 2>/dev/null || true

# ========== 2. 配置 SDKMAN Shell ==========

log_info "配置 SDKMAN shell 环境..."

SDKMAN_ENV_FILE="$HOME/.bashrc.d/sdkman.sh"
mkdir -p "$HOME/.bashrc.d"

SDKMAN_ENV_CONTENT="# SDKMAN environment (managed by homelab setup)
export SDKMAN_DIR=\"$SDKMAN_DIR\"
[[ -s \"\$SDKMAN_DIR/bin/sdkman-init.sh\" ]] && source \"\$SDKMAN_DIR/bin/sdkman-init.sh\""

if [ ! -f "$SDKMAN_ENV_FILE" ] || [ "$(cat "$SDKMAN_ENV_FILE")" != "$SDKMAN_ENV_CONTENT" ]; then
    echo "$SDKMAN_ENV_CONTENT" > "$SDKMAN_ENV_FILE"
    log_success "SDKMAN 初始化已写入 $SDKMAN_ENV_FILE"
else
    log_success "SDKMAN 初始化已是最新"
fi

# 清理 .bashrc 和 .bash_profile 中的 SDKMAN 块
for rc_file in "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [ -f "$rc_file" ] && grep -qF "sdkman-init.sh" "$rc_file" 2>/dev/null; then
        log_info "从 $(basename $rc_file) 中移除 SDKMAN init 块..."
        sed -i '/#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!/,/sdkman-init\.sh/d' "$rc_file"
        log_success "已清理 $(basename $rc_file)"
    fi
done

# 确保 .bashrc 加载 .bashrc.d/
ensure_bashrc_d_loader

# ========== 3. 安装 Java ==========

log_info "检查 Java..."

# 优先尝试 Dragonwell 21，回退到 OpenJDK 21
JAVA_CANDIDATES=($(sdk list java 2>/dev/null | grep -E "21\.[0-9]+\.[0-9]+-tem" | head -3 | awk '{print $NF}'))

if [ ${#JAVA_CANDIDATES[@]} -eq 0 ]; then
    # 尝试 Dragonwell
    JAVA_CANDIDATES=($(sdk list java 2>/dev/null | grep -i "21.*albba" | head -3 | awk '{print $NF}'))
fi

if [ ${#JAVA_CANDIDATES[@]} -eq 0 ]; then
    # 最后回退到通用 21
    JAVA_CANDIDATES=($(sdk list java 2>/dev/null | grep -E "^\s*\|.*21\." | head -3 | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}'))
fi

if [ ${#JAVA_CANDIDATES[@]} -eq 0 ]; then
    log_error "未找到可用的 Java 21 版本"
    exit 1
fi

TARGET_JAVA="${JAVA_CANDIDATES[0]}"

# 检查是否已安装目标版本
JAVA_INSTALLED=false
if [ -d "$SDKMAN_DIR/candidates/java" ]; then
    for d in "$SDKMAN_DIR/candidates/java"/*/; do
        [ -d "$d" ] && [ "$(basename "$d")" = "$TARGET_JAVA" ] && JAVA_INSTALLED=true && break
    done
fi

if [ "$JAVA_INSTALLED" = false ]; then
    log_info "安装 Java: $TARGET_JAVA"
    sdk install java "$TARGET_JAVA"
    sdk default java "$TARGET_JAVA"
    log_success "Java 已安装并设为默认: $TARGET_JAVA"
else
    # 已安装 → 检查 current 链接是否有效
    CURRENT_JAVA=$(sdk current java 2>/dev/null | awk '{print $NF}')
    CURRENT_LINK="$SDKMAN_DIR/candidates/java/current"
    LINK_TARGET=$(readlink -f "$CURRENT_LINK" 2>/dev/null)

    if [ "$CURRENT_JAVA" != "$TARGET_JAVA" ] || [ ! -L "$CURRENT_LINK" ] || [ -z "$LINK_TARGET" ]; then
        sdk default java "$TARGET_JAVA"
        log_success "Java 已设为默认: $TARGET_JAVA"
    else
        log_success "Java 已是目标版本: $TARGET_JAVA"
        # Java 版本升级需手动操作: sdk install java <新版本>-tem
        # sdk upgrade java 会跨大版本（如 21→25），不自动执行
    fi
fi

# ========== 4. 安装 Maven ==========

log_info "检查 Maven..."

# 检查 Maven 是否已安装（检查 candidates 目录）
MAVEN_INSTALLED=false
if [ -d "$SDKMAN_DIR/candidates/maven" ]; then
    MAVEN_COUNT=$(ls -1 "$SDKMAN_DIR/candidates/maven" 2>/dev/null | grep -v "^current$" | wc -l)
    [ "$MAVEN_COUNT" -gt 0 ] && MAVEN_INSTALLED=true
fi

if [ "$MAVEN_INSTALLED" = false ]; then
    # 未安装 → 安装并设为默认
    log_info "安装 Maven..."
    sdk install maven
    NEW_MAVEN=$(sdk current maven 2>/dev/null | awk '{print $NF}')
    sdk default maven "$NEW_MAVEN"
    log_success "Maven 已安装并设为默认: $NEW_MAVEN"
else
    # 已安装 → 检查 current 符号链接是否有效
    CURRENT_MAVEN=$(sdk current maven 2>/dev/null | awk '{print $NF}')
    CURRENT_LINK="$SDKMAN_DIR/candidates/maven/current"
    LINK_TARGET=$(readlink -f "$CURRENT_LINK" 2>/dev/null)

    if [ -z "$CURRENT_MAVEN" ] || [ ! -L "$CURRENT_LINK" ] || [ -z "$LINK_TARGET" ]; then
        # 已安装但 current 链接异常（上次可能失败），重新设置
        # 取已安装的最新版本
        INSTALLED_VER=$(ls -1 "$SDKMAN_DIR/candidates/maven/" 2>/dev/null | grep -v "^current$" | sort -V | tail -n1)
        sdk default maven "$INSTALLED_VER"
        log_success "Maven 已设为默认: $INSTALLED_VER"
    else
        log_success "Maven 已安装: $CURRENT_MAVEN"
        # 尝试升级到最新版本
        log_info "检查 Maven 升级..."
        sdk upgrade maven 2>/dev/null || true
    fi
fi

# ========== 5. 配置 Maven 镜像 ==========

log_info "配置 Maven 阿里云镜像..."

MAVEN_SETTINGS_DIR="$HOME/.m2"
MAVEN_SETTINGS_FILE="$MAVEN_SETTINGS_DIR/settings.xml"

MAVEN_SETTINGS_CONTENT="<settings xmlns=\"http://maven.apache.org/SETTINGS/1.0.0\"
          xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"
          xsi:schemaLocation=\"http://maven.apache.org/SETTINGS/1.0.0
                              http://maven.apache.org/xsd/settings-1.0.0.xsd\">

  <localRepository>$MAVEN_CACHE_DIR/repository</localRepository>

  <mirrors>
    <mirror>
      <id>aliyunmaven</id>
      <mirrorOf>*</mirrorOf>
      <name>阿里云公共仓库</name>
      <url>https://maven.aliyun.com/repository/public</url>
    </mirror>
  </mirrors>

</settings>"

if [ ! -f "$MAVEN_SETTINGS_FILE" ] || [ "$(cat "$MAVEN_SETTINGS_FILE")" != "$MAVEN_SETTINGS_CONTENT" ]; then
    mkdir -p "$MAVEN_SETTINGS_DIR"
    echo "$MAVEN_SETTINGS_CONTENT" > "$MAVEN_SETTINGS_FILE"
    log_success "Maven settings.xml 已更新"
else
    log_success "Maven settings.xml 已是最新"
fi

# ========== 6. 验证 ==========

echo ""
log_info "Java: $(java -version 2>&1 | head -n1)"
log_info "Maven: $(mvn -v 2>/dev/null | head -n1)"
log_info "Maven 本地仓库: $MAVEN_CACHE_DIR/repository"
log_success "Java + Maven 配置完成"
