#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$TEST_DIR/../.." && pwd)"
CONFIG_LIB="$SETUP_DIR/lib/config.sh"
[ -f "$CONFIG_LIB" ] || { echo "FAIL: config helper is missing: $CONFIG_LIB" >&2; exit 1; }

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT
SETUP_ROOT="$fixture_root/setup"
BACKUP_DIR="$SETUP_ROOT/backup"
mkdir -p "$SETUP_ROOT" "$fixture_root/target"
source "$CONFIG_LIB"

fail() { echo "FAIL: $1" >&2; exit 1; }

source_file="$fixture_root/source"
target_file="$fixture_root/target/config"
printf 'same\n' > "$source_file"
printf 'same\n' > "$target_file"
mtime_before="$(stat -c '%Y' "$target_file")"
sleep 1
homelab_atomic_install_user "$source_file" "$target_file" 640
[ "$(stat -c '%Y' "$target_file")" = "$mtime_before" ] || fail "identical target was rewritten"

printf 'old\n' > "$target_file"
homelab_backup_user_file demo 20260902-120000 "$target_file"
[ "$(cat "$BACKUP_DIR/demo/20260902-120000/config")" = old ] || fail "user backup did not preserve old content"
homelab_atomic_install_user "$source_file" "$target_file" 640
[ "$(cat "$target_file")" = same ] || fail "atomic user install did not update content"
[ "$(stat -c '%a' "$target_file")" = 640 ] || fail "atomic user install ignored explicit mode"

tree_before="$(find "$BACKUP_DIR" -printf '%P\n' | sort)"
homelab_backup_user_file absent 20260902-120001 "$fixture_root/missing"
tree_after="$(find "$BACKUP_DIR" -printf '%P\n' | sort)"
[ "$tree_before" = "$tree_after" ] || fail "missing source created an empty backup directory"

collision_source="$fixture_root/collision"
printf 'different\n' > "$collision_source"
if homelab_backup_user_file demo 20260902-120000 "$collision_source" config 2>/dev/null; then
    fail "backup collision overwrote an existing backup"
fi
[ "$(cat "$BACKUP_DIR/demo/20260902-120000/config")" = old ] || fail "backup collision changed preserved content"

if homelab_backup_path '../escape' 20260902-120000 config >/dev/null 2>&1; then
    fail "unsafe backup module name was accepted"
fi
if homelab_atomic_install_user "$source_file" / 600 >/dev/null 2>&1; then
    fail "filesystem root was accepted as an install target"
fi

[ -z "$(find "$fixture_root/target" -maxdepth 1 -name '.homelab.*' -print -quit)" ] || fail "temporary install file was left behind"

echo "PASS: configuration writes and backups are safe and idempotent"
