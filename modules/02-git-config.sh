#!/bin/bash
# DESCRIPTION: Git 全局配置 — 安装 + 用户名邮箱 + 默认分支 + 常用别名

set -e
source "$(dirname "$0")/../common.sh"

# ========== 检查安装 ==========

if ! command -v git &>/dev/null; then
    log_info "安装 Git..."
    ensure_sudo
    sudo apt-get update -y
    sudo apt-get install -y git
    log_success "Git 安装完成"
fi

log_info "Git 版本: $(git --version)"

# ========== 配置用户名邮箱 ==========

log_info "配置 Git 用户信息..."

CURRENT_NAME=$(git config --global user.name 2>/dev/null || echo "")
CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

if [ -n "$CURRENT_NAME" ] && [ -n "$CURRENT_EMAIL" ]; then
    log_success "Git 用户已配置: $CURRENT_NAME <$CURRENT_EMAIL>"
    if prompt_yesno "是否修改?" "n"; then
        GIT_NAME=$(prompt_input "用户名:" "$CURRENT_NAME")
        GIT_EMAIL=$(prompt_input "邮箱:" "$CURRENT_EMAIL")
        git config --global user.name "$GIT_NAME"
        git config --global user.email "$GIT_EMAIL"
        log_success "Git 用户信息已更新"
    fi
else
    GIT_NAME=$(prompt_input "用户名:" "$(whoami)")
    GIT_EMAIL=$(prompt_input "邮箱:" "")
    if [ -z "$GIT_EMAIL" ]; then
        log_error "邮箱不能为空"
        exit 1
    fi
    git config --global user.name "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
    log_success "Git 用户信息已配置"
fi

# ========== 默认分支 ==========

log_info "配置默认分支..."

CURRENT_BRANCH=$(git config --global init.defaultBranch 2>/dev/null || echo "")
if [ "$CURRENT_BRANCH" = "main" ]; then
    log_success "默认分支已是 main"
else
    INIT_BRANCH=$(prompt_choice "默认分支名称:" "main" "main" "master")
    git config --global init.defaultBranch "$INIT_BRANCH"
    log_success "默认分支设为: $INIT_BRANCH"
fi

# ========== 常用配置 ==========

log_info "配置 Git 常用选项..."

git config --global pull.rebase true
git config --global fetch.prune true
git config --global diff.colorMoved zebra
git config --global core.autocrlf input
git config --global core.editor vim

log_success "Git 常用选项已配置"

# ========== 常用别名 ==========

log_info "配置 Git 别名..."

git config --global alias.st status
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.ci commit
git config --global alias.lg "log --oneline --graph --decorate -20"
git config --global alias.last "log -1 --stat"
git config --global alias.unstage "reset HEAD --"

log_success "Git 别名已配置"

# ========== 验证 ==========

echo ""
log_info "Git 用户: $(git config --global user.name) <$(git config --global user.email)>"
log_info "默认分支: $(git config --global init.defaultBranch)"
log_info "Pull 策略: $(git config --global pull.rebase)"
log_success "Git 配置完成"
