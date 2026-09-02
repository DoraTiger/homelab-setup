# Homelab Setup 开发规范

## 支持边界

项目面向 Debian + Xfce。Xfce 用于减少服务器图形桌面开销；XRDP 因此需要显式隔离本地与远程 X11、D-Bus 和 Secret Service，并在 Xfce 启动链中配置 Fcitx5。不要将 GNOME 的默认会话假设直接复制到 XRDP 模块。

## 目录职责

- `common.sh`：所有模块的稳定公共入口，source 时不得写文件或访问网络。
- `lib/`：路径、交互、网络、配置和模块专用的可测试函数。
- `modules/`：仅存放 `{编号}-{名称}.sh` 可执行模块。
- `tests/unit/`：纯函数和单一行为测试。
- `tests/integration/`：临时 HOME、工作区或系统根中的组合行为测试。
- `tests/verify-environment.sh`：真实机器只读验收。
- `backup/`：setup 产生的迁移备份，不进入 Git。

## 路径

模块不得写死用户名或 `/home/<user>/workspace`。使用公共变量：

```text
SETUP_ROOT       当前 setup 仓库
WORKSPACE_ROOT   默认 $HOME/workspace，可配置
CACHE_DIR        持久化工具缓存
PACKAGES_DIR     下载包归档
BACKUP_DIR       $SETUP_ROOT/backup
KEYS_DIR         $SETUP_ROOT/keys
```

`PROJECT_ROOT` 仅为旧模块兼容别名，新代码不得使用。

`CACHE_DIR` 中只能放可删除重建的下载、构建和索引数据。用户安装的可执行文件、运行时版本和全局工具必须放在 `~/.local/bin`、`~/.local/opt`、`~/.local/share` 或各工具明确的持久化目录中。例如 Go 的 `GOMODCACHE/GOCACHE` 属于缓存，但 `GOBIN` 不属于缓存。

## 模块契约

模块必须以以下内容开头：

```bash
#!/bin/bash
# DESCRIPTION: 简短、准确的模块说明

set -e
source "$(dirname "$0")/../common.sh"
```

复杂模块按实际职责使用阶段注释：

```bash
# ========== 路径与常量 ==========
# ========== 辅助函数 ==========
# ========== 1. 安装 ==========
# ========== 2. 配置 ==========
# ========== 3. 可选升级 ==========
# ========== 4. 验证 ==========
```

注释解释幂等判断、安全边界和兼容原因，不逐行翻译命令。

## 默认执行与升级

默认执行只允许安装缺失组件、收敛配置和只读验证。已有组件的升级必须放在：

```bash
if upgrade_requested; then
    # upgrade existing component
fi
```

`HOMELAB_SILENT` 只控制交互，不能隐含升级。关键失败必须返回非零；只有明确的可选步骤可以警告后继续。

首次安装可以解析上游当前稳定版本。组件已经存在时，默认模式直接使用当前版本，不能仅为显示“是否最新”而访问上游。APT、SDKMAN、fnm、rustup、tlmgr 和桌面应用都遵循这一边界。

## 配置幂等性

配置处理依次判断：不存在、内容一致、语义已满足、已知旧版或冲突。内容或语义已满足时不得重写文件。未知用户配置保留并警告。

写入应先生成临时文件，以 `cmp` 判断变化，再做同文件系统原子替换。禁止无检查地 `echo >>`、按单个关键词删除整段配置或整体覆盖用户文件。

## 备份

只有确定内容将变化，并完成权限验证后，才能创建：

```text
$BACKUP_DIR/<module>/<timestamp>/
```

备份不得覆盖同名文件，不自动删除历史内容，不与 `cache/`、`packages/` 混用。下载缓存同样不由默认配置过程自动轮转或删除。失败操作不得留下空时间戳目录。

## 权限

模块复用 `ensure_sudo` 和 `run_as_root`，不得自行重复定义 sudo 函数。root 运行时直接执行特权命令；普通用户由公共层调用 sudo。

破坏性命令必须使用已解析的具体路径，拒绝空值、`/` 和未解析通配符。

## 测试

新增行为遵循测试先行：先观察测试因缺少行为而失败，再实现最小改动使其通过。测试应执行真实配置函数并断言文件、副作用和退出码，不只搜索源码文本。

```bash
# 隔离测试
bash tests/run.sh

# 隔离测试 + 当前机器环境矩阵
bash tests/run.sh --environment

# 全部 Shell 语法
find . -type f -name '*.sh' -not -path './backup/*' -print0 \
  | xargs -0 -n1 bash -n
```

严格 `--dry-run` 是后续独立能力。新增变更操作应优先通过公共函数形成可拦截边界，避免继续增加散落的直接写入。
