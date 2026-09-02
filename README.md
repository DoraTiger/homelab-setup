# Homelab Debian 环境配置

面向 Debian 13 (trixie) + Xfce 的 Homelab 环境配置工具。Xfce 用于降低服务器图形桌面的资源开销；相应地，XRDP 模块会显式处理本地/远程并发会话、D-Bus、密钥环和中文输入法集成。

## 核心原则

1. **系统与用户分离** — 系统级工具通过 `apt` 安装，用户级工具解压到 `$HOME/.local/opt/`，不污染系统目录，便于备份和迁移
2. **开发缓存统一管理** — npm、pip、Go、Conda 和 Maven 的可重建缓存统一放在 `cache/`；APT 保持 Debian 的系统缓存约定
3. **默认收敛、显式升级** — 默认只安装缺失组件并收敛配置，已有组件的升级由 `--upgrade` 显式开启
4. **镜像源加速** — 包管理器统一配置国内镜像（清华源/阿里源），脚本内置幂等检查
5. **安装包归档** — 下载的 tar.gz/deb 统一存放在 `packages/` 的二级子目录中，按软件分类，便于离线部署
6. **交互/静默双模式** — 交互式菜单引导选择，也支持 `--silent` 参数用于自动化部署和远程执行

## 目录结构

```text
workspace/                    # 工作区根目录（不在本仓库内）
├── setup/                    # 本仓库
│   ├── common.sh             # 稳定公共入口
│   ├── lib/                  # 路径、交互、配置及模块辅助函数
│   ├── init.sh               # 入口脚本：扫描模块、交互菜单、静默执行
│   ├── modules/              # 仅存放可执行模块
│   │   ├── 00-ssh.sh
│   │   ├── 01-apt-sources.sh
│   │   └── ...
│   ├── tests/                # 单元、集成和真实环境只读验证
│   ├── backup/               # setup 迁移备份（Git 忽略）
│   ├── keys/                 # 远程设备公钥（*.pub 不入库）
│   ├── .homelab.local        # 本机工作区选择（Git 忽略）
│   └── README.md
├── cache/                    # 运行时缓存（不在本仓库内，运行时自动创建）
│   ├── conda/pkgs/
│   ├── go/
│   ├── maven/
│   ├── npm/
│   └── pip/
└── packages/                 # 安装包归档（不在本仓库内，运行时自动创建）
    ├── caddy/
    ├── code-server/
    ├── fnm/
    ├── golang/
    ├── miniconda/
    ├── obsidian/
    ├── rust/
    ├── sdkman/
    ├── texlive/
    ├── zellij/
    └── zotero/
```

仓库默认放在 `$HOME/workspace/setup`，但代码不会写死用户名或仓库路径。数据工作区默认是 `$HOME/workspace`，可在菜单中修改，也可通过 `--workspace-root` 或 `HOMELAB_WORKSPACE_ROOT` 覆盖。迁移备份始终保存在当前 setup 仓库的 `backup/` 中。

## 快速开始

```bash
# 克隆仓库
mkdir -p "$HOME/workspace"
git clone https://github.com/DoraTiger/homelab-setup.git "$HOME/workspace/setup"
cd "$HOME/workspace/setup"

# 交互式菜单
bash init.sh

# 静默执行全部
bash init.sh --silent

# 显式检查并升级已有组件
bash init.sh --upgrade

# 使用其他数据工作区
bash init.sh --workspace-root /data/homelab

# 使用代理
bash init.sh --proxy socks5://127.0.0.1:7890
```

## 使用方式

### 交互式菜单

```bash
bash init.sh
```

显示 Setup、工作区、缓存、备份、代理和升级模式。模块编号来自文件名前缀，新增模块不会改变旧编号含义。菜单中的 `[u]` 切换升级模式，`[w]` 修改并保存本机工作区。

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Homelab Debian + Xfce 环境配置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Setup:      /home/user/workspace/setup
  工作区:     /home/user/workspace
  缓存:       /home/user/workspace/cache
  备份:       /home/user/workspace/setup/backup
  升级模式:   关闭
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  可用模块:
  ────────────────────────────────────────────────
    [00] 00-ssh.sh            SSH 密钥生成与 authorized_keys 配置
    [01] 01-apt-sources.sh    APT 源配置（清华/DEB822）
    [02] 02-git-config.sh     Git 全局配置
    ...
    [13] 13-zellij.sh         Zellij 终端复用器安装
    [14] 14-obsidian.sh       Obsidian 笔记工具安装
    [15] 15-zotero.sh         Zotero 文献管理安装
    [16] 16-caddy.sh          Caddy + AliDNS Provider 安装
    [17] 17-code-server.sh    code-server GitHub Deb 安装
  ────────────────────────────────────────────────
    [a] 全部  [p] 代理  [u] 升级模式  [w] 工作区  [q] 退出
```

### 静默模式

```bash
# 执行全部模块
bash init.sh --silent

# 按稳定编号、名称或完整文件名选择模块
bash init.sh --silent 04 nodejs 12-xrdp.sh

# 单独执行某个模块
HOMELAB_SILENT=1 bash modules/00-ssh.sh

# 单模块显式升级
HOMELAB_UPGRADE=1 bash modules/07-nodejs.sh
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

持久安装包统一保存到 `packages/<模块>/`。公共下载函数会先验证并复用本地
文件；需要下载时先写入同目录的 `.part` 文件，应用超时、重试和代理策略，
验证成功后再原子替换正式文件。这样下载中断不会破坏已有缓存。由 npm、pip、
Go、Conda、Maven 等包管理器产生的可重建依赖仍保存在 `cache/`。

早期版本写入 `cache/obsidian/` 和 `cache/zotero/` 的有效安装包会在需要时迁移到
`packages/`；无效文件不会覆盖新的持久缓存。

## 模块列表

| 编号 | 模块 | 说明 |
|------|------|------|
| 00 | ssh | SSH 密钥生成、authorized_keys 管理、权限设置 |
| 01 | apt-sources | APT 清华镜像源、基础工具安装、chrony 时间同步；升级模式下执行系统升级 |
| 02 | git-config | Git 安装 + 用户名邮箱 + 默认分支 + 常用别名 |
| 03 | docker | Docker CE + Compose + Daemon 配置 + 镜像加速 |
| 04 | miniconda | Miniconda 安装 + conda/pip 清华镜像；升级模式下更新 base 环境 |
| 05 | golang | Go 多版本管理 + GOPROXY 国内加速 |
| 06 | java | SDKMAN + Java 21 + Maven + 阿里云镜像 |
| 07 | nodejs | fnm + Node.js LTS + npm 镜像加速 |
| 08 | perl-cpan | CPAN 清华镜像 + local::lib |
| 09 | r-lang | R 语言安装 + CRAN 清华镜像 |
| 10 | rust | rustup + Rust stable + crates.io 清华镜像 |
| 11 | texlive | TeX Live 全量安装 + 清华 CTAN 镜像 |
| 12 | xrdp | XRDP + XFCE 并发会话、独立密钥环与 Fcitx5 中文输入 |
| 13 | zellij | Zellij 终端复用器 + GitHub 二进制安装；升级模式下检查新版 |
| 14 | obsidian | Obsidian 笔记工具 + Deb 包安装 + CLI 验证；升级模式下检查新版 |
| 15 | zotero | Zotero 文献管理 + Tarball 用户级安装；升级模式下检查新版 |
| 16 | caddy | Caddy 官方 Debian 包 + xcaddy 构建 AliDNS DNS Provider；构建前检查 Go 1.25+ |
| 17 | code-server | code-server 官方 GitHub Deb 安装并持久缓存；仅输出 localhost 与 Caddy HTTPS 配置参考 |

### Caddy 与 code-server

这两个模块不收集域名或 AliDNS AccessKey，也不修改 Caddyfile 或 code-server
配置。code-server 模块不启动服务；其官方 Deb 保存在
`packages/code-server/`。Caddy 首次安装或替换自定义二进制时会重启
Caddy，以启用 AliDNS Provider。Caddy 模块仅在缺少
`dns.providers.alidns` 且没有有效的本地归档时使用 Go/xcaddy 构建自定义二进制，
构建结果保存在 `packages/caddy/`；因此建议先执行 Go
模块，或直接按编号顺序执行：

```bash
bash init.sh --silent 05 16 17
```

安装完成后，模块会在终端输出无真实域名和凭据的配置模板。AliDNS 凭据应由
用户另行写入权限受限的 `/etc/caddy/alidns.env`，不得放入仓库或 Caddyfile。

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
| 公共函数 | 通过 `source ../common.sh` 加载；公共实现位于根目录 `lib/` |
| 路径引用 | 使用 `$SETUP_ROOT`、`$WORKSPACE_ROOT`、`$CACHE_DIR`、`$PACKAGES_DIR`、`$BACKUP_DIR` |
| 静默模式 | 通过 `$HOMELAB_SILENT` 环境变量控制，使用 `prompt_choice`/`prompt_yesno`/`prompt_input` 等交互函数 |
| 升级模式 | 仅在 `upgrade_requested` 成功时升级已有组件 |
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

环境配置按是否可在非交互 shell 中安全执行分为两层：

```text
~/.profile.d/*.sh   # PATH 与普通环境变量，登录/非交互/交互 shell 共用
~/.bashrc.d/*.sh    # hook、补全与 alias，仅交互 Bash 加载
```

`~/.profile` 和 `.bashrc` 通过受管加载器读取 `~/.profile.d/`；同时设置
`BASH_ENV`，让后续 `bash -c` 子进程继承同一环境。加载器会对 PATH 执行去重。

各模块的主要配置如下：

| 模块 | 文件 | 关键变量 |
|------|------|----------|
| miniconda | profile + bashrc | Conda/Python PATH；`conda activate` hook 仅交互加载 |
| golang | profile | `GOROOT`；`GOBIN` 使用 `~/.local/bin`；`GOPATH`、`GOCACHE`、`GOMODCACHE` 使用工作区缓存 |
| java | profile + bashrc | Java/Maven PATH；SDKMAN 完整初始化仅交互加载 |
| nodejs | profile + bashrc | fnm/Node/npm PATH；fnm `--use-on-cd` 仅交互加载 |
| perl | profile | `PERL5LIB`、`PERL_LOCAL_LIB_ROOT` |
| rust | profile | `RUSTUP_HOME`、`CARGO_HOME` |
| texlive | profile | `TEXLIVE_DIR`、`PATH`、`MANPATH`、`INFOPATH` |
| zellij | bashrc | 命令通过 `~/.local/bin` 暴露；别名仅交互加载 |

Conda 环境与解释器保存在 `~/.local/opt/miniconda3`，可删除重建的软件包缓存位于 `cache/conda/pkgs`；pip 下载缓存位于 `cache/pip`。项目虚拟环境和项目内 `node_modules` 仍由各项目自行管理，不移动到共享缓存。

### fnm 目录约定

Node.js 模块将 fnm 程序与版本数据分开管理：

```text
~/.local/opt/fnm/fnm       # fnm 可执行文件
~/.local/share/fnm/        # Node.js 版本、别名与下载数据
~/.local/npm-global/       # npm 全局包
```

`FNM_INSTALL_DIR` 指向程序目录，`FNM_DIR` 指向版本数据目录。模块检测到旧版
`~/.local/opt/fnm/node-versions` 或 `~/.local/opt/fnm/aliases` 时，会将其移动到
带时间戳的 `~/.local/opt/fnm-legacy-data-*` 备份目录，不覆盖规范数据目录，也不
直接删除旧版本。

Node.js 目录布局的回归测试：

```bash
bash tests/unit/test-nodejs-layout.sh
```

XRDP 配置收敛与幂等迁移测试：

```bash
bash tests/integration/test-xrdp-config.sh
```

完整 shell 加载与环境矩阵验证：

```bash
bash tests/run.sh
bash tests/run.sh --environment
```

完整模块开发契约见 [DEVELOPMENT.md](DEVELOPMENT.md)。

## 许可证

[MIT License](LICENSE)
