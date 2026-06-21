# Homelab Debian 环境配置

Debian 13 (trixie) Homelab 服务器的一键配置工具。通过模块化脚本实现开发环境、容器服务等基础配置的自动化部署，支持交互式选择和静默批量执行。

## 核心原则

1. **系统与用户分离** — 系统级工具通过 `apt` 安装，用户级工具解压到 `$HOME/.local/opt/`，不污染系统目录，便于备份和迁移
2. **缓存统一管理** — 包管理器缓存（apt、npm、pip、Go、conda）统一放在 `cache/` 下，重装系统不丢失，清理方便
3. **脚本全部幂等** — 每个模块脚本可反复执行：已安装的跳过、配置相同的跳过、PATH 已有的跳过，不会产生覆盖或冗余
4. **镜像源加速** — 包管理器统一配置国内镜像（清华源/阿里源），脚本内置幂等检查
5. **安装包归档** — 下载的 tar.gz/deb 统一存放在 `packages/` 的二级子目录中，按软件分类，便于离线部署
6. **交互/静默双模式** — 交互式菜单引导选择，也支持 `--silent` 参数用于自动化部署和远程执行

## 目录结构

```text
workspace/                    # 工作区根目录（不在本仓库内）
├── setup/                    # 本仓库
│   ├── common.sh             # 公共函数：日志、路径、交互工具
│   ├── init.sh               # 入口脚本：扫描模块、交互菜单、静默执行
│   ├── modules/              # 模块脚本，按编号顺序执行
│   │   ├── 00-ssh.sh
│   │   ├── 01-apt-sources.sh
│   │   └── ...
│   ├── keys/                 # 远程设备公钥（*.pub 不入库）
│   └── README.md
├── cache/                    # 运行时缓存（不在本仓库内，运行时自动创建）
│   ├── go/
│   ├── maven/
│   └── npm/
└── packages/                 # 安装包归档（不在本仓库内，运行时自动创建）
    ├── golang/
    └── miniconda/
```

> **注意**：`cache/` 和 `packages/` 目录在 `setup/` 同级创建，由脚本运行时自动生成，不属于本仓库。脚本通过 `common.sh` 中的 `$PROJECT_ROOT` 变量定位同级目录。

## 快速开始

```bash
# 克隆仓库
git clone https://github.com/DoraTiger/homelab-setup.git
cd homelab-setup

# 交互式菜单
bash init.sh

# 静默执行全部
bash init.sh --silent

# 使用代理
bash init.sh --proxy socks5://127.0.0.1:7890
```

## 使用方式

### 交互式菜单

```bash
bash init.sh
```

显示路径信息和模块列表，输入编号选择执行：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Homelab Debian 环境配置工具
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  项目路径:   /path/to/homelab-setup/..
  缓存目录:   /path/to/homelab-setup/../cache
  安装包:     /path/to/homelab-setup/../packages
  密钥目录:   /path/to/homelab-setup/keys
  代理状态:   未配置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  可用模块:
  ────────────────────────────────────────────────
    [ 0] 00-ssh.sh            SSH 密钥生成与 authorized_keys 配置
    [ 1] 01-apt-sources.sh    APT 源配置（清华/DEB822）
    [ 2] 02-git-config.sh     Git 全局配置
    ...
    [13] 13-zellij.sh         Zellij 终端复用器安装
    [14] 14-obsidian.sh       Obsidian 笔记工具安装
    [15] 15-zotero.sh         Zotero 文献管理安装
  ────────────────────────────────────────────────
    [a]  全部执行     [p]  配置代理     [q]  退出
```

### 静默模式

```bash
# 执行全部模块
bash init.sh --silent

# 执行指定模块（按编号）
bash init.sh --silent 1 3

# 单独执行某个模块
HOMELAB_SILENT=1 bash modules/00-ssh.sh
```

### 代理配置

网络受限时可通过代理确保下载稳定：

```bash
# 命令行参数：直接指定
bash init.sh --proxy socks5://127.0.0.1:7890
bash init.sh --proxy http://127.0.0.1:7890

# 静默模式 + 代理
bash init.sh --silent --proxy socks5://127.0.0.1:7890

# 交互式：启动后菜单选择 [p] 配置代理
bash init.sh
```

支持 `http://`、`https://`、`socks5://` 格式。模块中的 `wget`/`curl` 下载会自动走代理。

## 模块列表

| 编号 | 模块 | 说明 |
|------|------|------|
| 00 | ssh | SSH 密钥生成、authorized_keys 管理、权限设置 |
| 01 | apt-sources | APT 清华镜像源、基础工具安装、apt upgrade、chrony 时间同步 |
| 02 | git-config | Git 安装 + 用户名邮箱 + 默认分支 + 常用别名 |
| 03 | docker | Docker CE + Compose + Daemon 配置 + 镜像加速 |
| 04 | miniconda | Miniconda 安装 + conda/pip 清华镜像 + conda upgrade |
| 05 | golang | Go 多版本管理 + GOPROXY 国内加速 |
| 06 | java | SDKMAN + Java 21 + Maven + 阿里云镜像 |
| 07 | nodejs | fnm + Node.js LTS + npm 镜像加速 |
| 08 | perl-cpan | CPAN 清华镜像 + local::lib |
| 09 | r-lang | R 语言安装 + CRAN 清华镜像 |
| 10 | rust | rustup + Rust stable + crates.io 清华镜像 |
| 11 | texlive | TeX Live 全量安装 + 清华 CTAN 镜像 |
| 12 | xrdp | XRDP 远程桌面 + XFCE + polkit WiFi 修复 |
| 13 | zellij | Zellij 终端复用器 + GitHub 二进制安装 |
| 14 | obsidian | Obsidian 笔记工具 + Deb 包安装 + CLI 启用 |
| 15 | zotero | Zotero 文献管理 + Tarball 用户级安装 |

## 新增模块

在 `modules/` 下创建 `{序号}-{名称}.sh`，脚本第二行添加描述：

```bash
#!/bin/bash
# DESCRIPTION: 模块简要说明

set -e
source "$(dirname "$0")/../common.sh"

# 模块逻辑...
```

重启菜单后自动识别。模块按编号顺序执行。

## 模块开发规范

| 规范 | 说明 |
|------|------|
| 文件命名 | `{序号}-{名称}.sh`，序号决定执行顺序 |
| 描述声明 | 第二行 `# DESCRIPTION: 简要说明`，用于菜单展示 |
| 公共函数 | 通过 `source common.sh` 加载，使用 `log_info`/`log_success`/`log_warn`/`log_error` 输出 |
| 路径引用 | 使用 `$PROJECT_ROOT`（上级目录）、`$CACHE_DIR`（缓存）、`$PACKAGES_DIR`（安装包） |
| 静默模式 | 通过 `$HOMELAB_SILENT` 环境变量控制，使用 `prompt_choice`/`prompt_yesno`/`prompt_input` 等交互函数 |
| 幂等检查 | 安装前检测是否已存在，配置写入前比对内容 |
| 镜像配置 | 写入前检查是否已为最新内容，避免覆盖用户自定义配置 |
| 交互模式 | 使用 `prompt_*` 函数，静默模式自动使用默认值 |
| sudo 依赖 | 仅在必要时调用，日志中说明原因 |

## 交互工具

`common.sh` 提供以下通用交互函数：

```bash
# 单选菜单
type=$(prompt_choice "选择密钥类型:" "ed25519" "ed25519" "rsa-4096" "ecdsa")

# 是/否确认
if prompt_yesno "是否配置镜像源?" "y"; then ... fi

# 文本输入
name=$(prompt_input "用户名:" "$(whoami)")

# 密码输入（隐藏回显 + 二次确认）
pass=$(prompt_secret "请输入密码")

# 表格展示
prompt_table "文件名|类型|说明" "id_ed25519.pub|ed25519|本机密钥"
```

## 环境变量规划

模块按需设置环境变量，统一写入 `~/.bashrc.d/` 目录：

| 模块 | 文件 | 关键变量 |
|------|------|----------|
| miniconda | `conda.sh` | `PATH`（conda init） |
| golang | `go.sh` | `GOROOT`、`GOPATH`、`GOPROXY`、`GOCACHE`、`GOMODCACHE` |
| java | `sdkman.sh` | `SDKMAN_DIR`（SDKMAN 管理 JAVA_HOME、M2_HOME） |
| nodejs | `nodejs.sh` | `FNM_DIR`、npm global `PATH` |
| perl | `perl.sh` | `PERL5LIB`、`PERL_LOCAL_LIB_ROOT` |
| rust | `rust.sh` | `RUSTUP_HOME`、`CARGO_HOME` |
| texlive | `texlive.sh` | TeX Live `PATH`、`MANPATH`、`INFOPATH` |
| zellij | `zellij.sh` | 别名（`zj`/`zjl`/`zja`/`zjn`） |

## 许可证

[MIT License](LICENSE)
