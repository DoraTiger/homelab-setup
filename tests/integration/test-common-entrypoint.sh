#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$TEST_DIR/../.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT
mkdir -p "$fixture_root/home"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

before="$(find "$fixture_root/home" -mindepth 1 -printf '%P\n' | sort)"
HOME="$fixture_root/home"
HOMELAB_WORKSPACE_ROOT="$fixture_root/workspace"
export HOME HOMELAB_WORKSPACE_ROOT
source "$SETUP_DIR/common.sh"
after="$(find "$fixture_root/home" -mindepth 1 -printf '%P\n' | sort)"

[ "$before" = "$after" ] || fail "sourcing common.sh created user files"
[ "$SETUP_ROOT" = "$SETUP_DIR" ] || fail "common.sh resolved the wrong setup root"
[ "$WORKSPACE_ROOT" = "$fixture_root/workspace" ] || fail "common.sh ignored the workspace override"
[ "$BACKUP_DIR" = "$SETUP_DIR/backup" ] || fail "common.sh exposed the wrong backup directory"

required_functions=(
    log_info log_success log_warn log_error
    prompt_choice prompt_yesno prompt_input prompt_secret prompt_table
    ensure_sudo run_as_root ensure_workspace_ready
    ensure_bashrc_d_loader ensure_shell_env_loader write_profile_env_file
    detect_distro run_with_optional_proxy setup_proxy
)
for function_name in "${required_functions[@]}"; do
    declare -F "$function_name" >/dev/null || fail "common facade is missing $function_name"
done

echo "PASS: common.sh is a side-effect-free compatible facade"
