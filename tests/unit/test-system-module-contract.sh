#!/bin/bash

set -euo pipefail

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

for module in "$SETUP_ROOT/modules/03-docker.sh" "$SETUP_ROOT/modules/09-r-lang.sh"; do
    if grep -Eq '^ensure_sudo\(\)' "$module"; then
        fail "$(basename "$module") must use common.sh ensure_sudo"
    fi
done

grep -q 'if upgrade_requested; then' "$SETUP_ROOT/modules/01-apt-sources.sh" ||
    fail "APT package upgrades must require upgrade mode"
grep -q 'if upgrade_requested; then' "$SETUP_ROOT/modules/03-docker.sh" ||
    fail "Docker package upgrades must require upgrade mode"

if grep -q 'prompt_yesno "是否覆盖为推荐配置?" "y"' "$SETUP_ROOT/modules/03-docker.sh"; then
    fail "Docker must not overwrite a divergent daemon config by default"
fi

if grep -Eq '^[[:space:]]+local (name|key_type|comment)=' "$SETUP_ROOT/modules/00-ssh.sh"; then
    fail "SSH module contains function-only local declarations in main flow"
fi

grep -q 'openssh-client' "$SETUP_ROOT/modules/00-ssh.sh" ||
    fail "SSH module must satisfy its ssh-keygen dependency on a clean Debian system"

grep -q '静默模式未提供 Git 邮箱' "$SETUP_ROOT/modules/02-git-config.sh" ||
    fail "Git module must handle missing identity in silent mode"

echo "PASS: system module contract"
