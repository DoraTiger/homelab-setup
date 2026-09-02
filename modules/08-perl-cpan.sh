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

# 直接检查 CPAN 配置结构，避免依赖 prettyprint 的输出格式和输出通道。
if perl -MCPAN -e '
    CPAN::HandleConfig->load();
    my $target = "https://mirrors.tuna.tsinghua.edu.cn/CPAN/";
    exit(grep { $_ eq $target } @{$CPAN::Config->{urllist} || []} ? 0 : 1);
' 2>/dev/null; then
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
if [ "$(perl -e 'print ($] >= 5.036)' 2>/dev/null)" = "1" ] &&
    ! perl -MCPAN -e 'CPAN::HandleConfig->load(); exit(($CPAN::Config->{pushy_https} // 1) == 0 ? 0 : 1)' 2>/dev/null; then
    perl -MCPAN -e '
        CPAN::HandleConfig->load();
        CPAN::HandleConfig->edit("pushy_https", 0);
        CPAN::HandleConfig->commit();
    ' 2>/dev/null || log_warn "无法更新 CPAN pushy_https 配置"
fi

# ========== 配置 local::lib 环境 ==========

log_info "配置 Perl local::lib..."

# 检测 local::lib 是否已安装
if [ -d "$HOME/perl5/lib/perl5" ]; then
    PERL_ENV_CONTENT="# Perl environment (managed by homelab setup)
homelab_path_prepend \"\$HOME/perl5/bin\"
homelab_var_prepend PERL5LIB \"\$HOME/perl5/lib/perl5\"
homelab_var_prepend PERL_LOCAL_LIB_ROOT \"\$HOME/perl5\"
export PERL_MB_OPT=\"--install_base \\\\\"\\\$HOME/perl5\\\\\"\"
export PERL_MM_OPT=\"INSTALL_BASE=\$HOME/perl5\""

    write_profile_env_file perl "$PERL_ENV_CONTENT"
else
    log_info "安装 local::lib..."
    PERL_MM_USE_DEFAULT=1 cpan local::lib 2>/dev/null || true
    if [ -d "$HOME/perl5/lib/perl5" ]; then
        log_success "local::lib 安装完成"
        # 写入环境变量
        PERL_ENV_CONTENT="# Perl environment (managed by homelab setup)
homelab_path_prepend \"\$HOME/perl5/bin\"
homelab_var_prepend PERL5LIB \"\$HOME/perl5/lib/perl5\"
homelab_var_prepend PERL_LOCAL_LIB_ROOT \"\$HOME/perl5\"
export PERL_MB_OPT=\"--install_base \\\\\"\\\$HOME/perl5\\\\\"\"
export PERL_MM_OPT=\"INSTALL_BASE=\$HOME/perl5\""
        write_profile_env_file perl "$PERL_ENV_CONTENT"
    else
        log_warn "local::lib 安装失败，跳过环境配置"
    fi
fi

# ========== 验证 ==========

echo ""
log_info "CPAN 镜像:"
perl -MCPAN -e 'CPAN::HandleConfig->load(); CPAN::HandleConfig->prettyprint("urllist")' 2>/dev/null | sed 's/^/    /'
log_success "CPAN 镜像配置完成"
