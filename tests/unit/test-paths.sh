#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$TEST_DIR/../.." && pwd)"
PATHS_LIB="$SETUP_DIR/lib/paths.sh"

if [ ! -f "$PATHS_LIB" ]; then
    echo "FAIL: path helper is missing: $PATHS_LIB" >&2
    exit 1
fi

source "$PATHS_LIB"

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT
mkdir -p "$fixture_root/home" "$fixture_root/setup"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

unset HOMELAB_WORKSPACE_ROOT HOMELAB_CACHE_DIR HOMELAB_PACKAGES_DIR HOMELAB_BACKUP_DIR
HOME="$fixture_root/home"
export HOME
homelab_initialize_paths "$fixture_root/setup"

[ "$SETUP_ROOT" = "$fixture_root/setup" ] || fail "SETUP_ROOT did not follow the repository location"
[ "$WORKSPACE_ROOT" = "$fixture_root/home/workspace" ] || fail "default workspace was not below HOME"
[ "$CACHE_DIR" = "$fixture_root/home/workspace/cache" ] || fail "default cache path is incorrect"
[ "$PACKAGES_DIR" = "$fixture_root/home/workspace/packages" ] || fail "default package path is incorrect"
[ "$BACKUP_DIR" = "$fixture_root/setup/backup" ] || fail "backup escaped the setup repository"
[ "$KEYS_DIR" = "$fixture_root/setup/keys" ] || fail "keys path escaped the setup repository"
[ "$PROJECT_ROOT" = "$WORKSPACE_ROOT" ] || fail "PROJECT_ROOT compatibility alias is incorrect"

local_config="$fixture_root/setup/.homelab.local"
payload_file="$fixture_root/payload-ran"
cat > "$local_config" <<EOF
# local configuration
UNKNOWN_KEY=/do/not/use
touch $payload_file
HOMELAB_WORKSPACE_ROOT=$fixture_root/config-workspace
EOF

unset HOMELAB_WORKSPACE_ROOT
homelab_initialize_paths "$fixture_root/setup"
[ "$WORKSPACE_ROOT" = "$fixture_root/config-workspace" ] || fail "local workspace configuration was not read"
[ ! -e "$payload_file" ] || fail "local configuration was executed as shell code"

HOMELAB_WORKSPACE_ROOT="$fixture_root/environment-workspace"
export HOMELAB_WORKSPACE_ROOT
homelab_initialize_paths "$fixture_root/setup"
[ "$WORKSPACE_ROOT" = "$fixture_root/environment-workspace" ] || fail "environment override did not win"

unset HOMELAB_WORKSPACE_ROOT
homelab_write_local_workspace "$local_config" "$fixture_root/saved workspace"
[ "$(cat "$local_config")" = "HOMELAB_WORKSPACE_ROOT=$fixture_root/saved workspace" ] || fail "local configuration writer emitted unexpected content"
[ "$(stat -c '%a' "$local_config")" = "600" ] || fail "local configuration mode is not private"
mtime_before="$(stat -c '%Y' "$local_config")"
sleep 1
homelab_write_local_workspace "$local_config" "$fixture_root/saved workspace"
[ "$(stat -c '%Y' "$local_config")" = "$mtime_before" ] || fail "unchanged local configuration was rewritten"

if homelab_write_local_workspace "$local_config" $'bad\npath' 2>/dev/null; then
    fail "newline-containing workspace path was accepted"
fi

echo "PASS: paths are dynamic, restricted, and idempotent"
