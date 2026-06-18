#!/bin/bash
# DESCRIPTION: CPAN 镜像配置 — 配置清华镜像源加速 Perl 模块安装

set -e
source "$(dirname "$0")/../common.sh"

# ========== 检查 Perl ==========

if ! command -v perl &>/dev/null; then
    log_error "Perl 未安装，请先安装: apt install -y perl"
    exit 1
fi

PERL_VER=$(perl -e 'print $^V')
log_info "Perl 版本: $PERL_VER"

# ========== 配置 CPAN 镜像 ==========

log_info "配置 CPAN 清华镜像..."

# 检查是否已配置
if perl -MCPAN -e 'CPAN::HandleConfig->load()' -e 'CPAN::HandleConfig->prettyprint("urllist")' 2>/dev/null | grep -qF "mirrors.tuna.tsinghua.edu.cn/CPAN/"; then
    log_success "CPAN 清华镜像已配置"
else
    # 静默配置：不触发交互式对话
    PERL_MM_USE_DEFAULT=1 perl -MCPAN -e '
        CPAN::HandleConfig->load();
        CPAN::HandleConfig->edit("urllist", "unshift", "https://mirrors.tuna.tsinghua.edu.cn/CPAN/");
        CPAN::HandleConfig->commit();
    ' 2>/dev/null || true
    log_success "CPAN 清华镜像已添加"
fi

# Perl 5.36+ 需要关闭 pushy_https 以兼容镜像站
if [ "$(perl -e 'print ($] >= 5.036)' 2>/dev/null)" = "1" ]; then
    perl -MCPAN -e '
        CPAN::HandleConfig->load();
        CPAN::HandleConfig->edit("pushy_https", 0);
        CPAN::HandleConfig->commit();
    ' 2>/dev/null || true
fi

# ========== 配置 local::lib 环境 ==========

log_info "配置 Perl local::lib..."

PERL_ENV_FILE="$HOME/.bashrc.d/perl.sh"
mkdir -p "$HOME/.bashrc.d"

# 检测 local::lib 是否已安装
if [ -d "$HOME/perl5/lib/perl5" ]; then
    PERL_ENV_CONTENT="# Perl environment (managed by homelab setup)
export PATH=\"\$HOME/perl5/bin:\$PATH\"
export PERL5LIB=\"\$HOME/perl5/lib/perl5\${PERL5LIB:+:\${PERL5LIB}}\"
export PERL_LOCAL_LIB_ROOT=\"\$HOME/perl5\${PERL_LOCAL_LIB_ROOT:+:\${PERL_LOCAL_LIB_ROOT}}\"
export PERL_MB_OPT=\"--install_base \\\\\"\\\$HOME/perl5\\\\\"\"
export PERL_MM_OPT=\"INSTALL_BASE=\$HOME/perl5\""

    if [ ! -f "$PERL_ENV_FILE" ] || [ "$(cat "$PERL_ENV_FILE")" != "$PERL_ENV_CONTENT" ]; then
        echo "$PERL_ENV_CONTENT" > "$PERL_ENV_FILE"
        log_success "Perl 环境变量已写入 $PERL_ENV_FILE"
    else
        log_success "Perl 环境变量已是最新"
    fi
else
    log_info "安装 local::lib..."
    PERL_MM_USE_DEFAULT=1 cpan local::lib 2>/dev/null || true
    if [ -d "$HOME/perl5/lib/perl5" ]; then
        log_success "local::lib 安装完成"
        # 写入环境变量
        PERL_ENV_CONTENT="# Perl environment (managed by homelab setup)
export PATH=\"\$HOME/perl5/bin:\$PATH\"
export PERL5LIB=\"\$HOME/perl5/lib/perl5\${PERL5LIB:+:\${PERL5LIB}}\"
export PERL_LOCAL_LIB_ROOT=\"\$HOME/perl5\${PERL_LOCAL_LIB_ROOT:+:\${PERL_LOCAL_LIB_ROOT}}\"
export PERL_MB_OPT=\"--install_base \\\\\"\\\$HOME/perl5\\\\\"\"
export PERL_MM_OPT=\"INSTALL_BASE=\$HOME/perl5\""
        echo "$PERL_ENV_CONTENT" > "$PERL_ENV_FILE"
        log_success "Perl 环境变量已写入 $PERL_ENV_FILE"
    else
        log_warn "local::lib 安装失败，跳过环境配置"
    fi
fi

ensure_bashrc_d_loader

# ========== 验证 ==========

echo ""
log_info "CPAN 镜像:"
perl -MCPAN -e 'CPAN::HandleConfig->load(); CPAN::HandleConfig->prettyprint("urllist")' 2>/dev/null | sed 's/^/    /'
log_success "CPAN 镜像配置完成"
