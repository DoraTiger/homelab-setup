#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$TEST_DIR/../.." && pwd)"
HELPER="$SETUP_DIR/lib/nodejs-env.sh"

if [ ! -f "$HELPER" ]; then
    echo "FAIL: Node.js environment renderer is missing: $HELPER" >&2
    exit 1
fi

source "$HELPER"

fixture_home="/tmp/homelab-nodejs-home"
if ! declare -F render_nodejs_profile_env >/dev/null || ! declare -F render_nodejs_interactive_env >/dev/null; then
    echo "FAIL: Node.js profile and interactive renderers are not separated" >&2
    exit 1
fi

actual="$(render_nodejs_profile_env "$fixture_home")"

expected="# Node.js environment (managed by homelab setup)
export FNM_INSTALL_DIR=\"$fixture_home/.local/opt/fnm\"
export FNM_DIR=\"$fixture_home/.local/share/fnm\"
homelab_path_prepend \"\$FNM_INSTALL_DIR\"
homelab_path_prepend \"\$FNM_DIR/aliases/default/bin\"
homelab_path_prepend \"$fixture_home/.local/npm-global/bin\""

if [ "$actual" != "$expected" ]; then
    echo "FAIL: rendered Node.js environment does not separate fnm binary and data directories" >&2
    diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true
    exit 1
fi

interactive="$(render_nodejs_interactive_env)"
expected_interactive="# Node.js interactive environment (managed by homelab setup)
eval \"\$(fnm env --use-on-cd)\" >/dev/null 2>&1"
if [ "$interactive" != "$expected_interactive" ]; then
    echo "FAIL: fnm use-on-cd hook is not isolated to the interactive environment" >&2
    exit 1
fi

echo "PASS: fnm binary and data directories are separated"

if ! declare -F migrate_legacy_fnm_data >/dev/null; then
    echo "FAIL: legacy fnm data migration is missing" >&2
    exit 1
fi

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

install_dir="$fixture_root/opt/fnm"
data_dir="$fixture_root/share/fnm"
backup_dir="$fixture_root/backup/fnm-data"
mkdir -p "$install_dir/node-versions/v20/installation" "$install_dir/aliases"
mkdir -p "$data_dir/node-versions/v24/installation" "$data_dir/aliases"
printf 'legacy-node\n' > "$install_dir/node-versions/v20/installation/VERSION"
printf 'canonical-node\n' > "$data_dir/node-versions/v24/installation/VERSION"
ln -s "$install_dir/node-versions/v20/installation" "$install_dir/aliases/default"
ln -s "$data_dir/node-versions/v24/installation" "$data_dir/aliases/default"

migrate_legacy_fnm_data "$install_dir" "$data_dir" "$backup_dir"

if [ ! -f "$data_dir/node-versions/v24/installation/VERSION" ]; then
    echo "FAIL: canonical fnm data was changed during migration" >&2
    exit 1
fi

if [ -e "$install_dir/node-versions" ] || [ -e "$install_dir/aliases" ]; then
    echo "FAIL: legacy fnm data remains in the binary directory" >&2
    exit 1
fi

if [ ! -f "$backup_dir/node-versions/v20/installation/VERSION" ] || [ ! -L "$backup_dir/aliases/default" ]; then
    echo "FAIL: legacy fnm data was not preserved in the backup directory" >&2
    exit 1
fi

echo "PASS: legacy fnm data is moved to a recoverable backup"
