#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$TEST_DIR/../.." && pwd)"
CLI_LIB="$SETUP_DIR/lib/cli.sh"
[ -f "$CLI_LIB" ] || { echo "FAIL: CLI helper is missing: $CLI_LIB" >&2; exit 1; }
source "$CLI_LIB"

fail() { echo "FAIL: $1" >&2; exit 1; }

homelab_parse_init_args --silent --upgrade --proxy http://127.0.0.1:7890 --workspace-root /data/workspace 4 07
[ "$CLI_SILENT" = 1 ] || fail "--silent was not parsed"
[ "$CLI_UPGRADE" = 1 ] || fail "--upgrade was not parsed"
[ "$CLI_PROXY" = http://127.0.0.1:7890 ] || fail "--proxy consumed the wrong value"
[ "$CLI_WORKSPACE_ROOT" = /data/workspace ] || fail "--workspace-root consumed the wrong value"
[ "${CLI_SELECTORS[*]}" = '4 07' ] || fail "module selectors were not preserved"

homelab_parse_init_args 12
[ "$CLI_SILENT:$CLI_UPGRADE:${CLI_PROXY:-}:${CLI_WORKSPACE_ROOT:-}:${CLI_SELECTORS[*]}" = '0:0:::12' ] || fail "parser state leaked between calls"

if homelab_parse_init_args --proxy >/dev/null 2>&1; then fail "missing proxy value was accepted"; fi
if homelab_parse_init_args --workspace-root >/dev/null 2>&1; then fail "missing workspace value was accepted"; fi
if homelab_parse_init_args --unknown >/dev/null 2>&1; then fail "unknown option was accepted"; fi

modules=(
    "$SETUP_DIR/modules/04-miniconda.sh"
    "$SETUP_DIR/modules/07-nodejs.sh"
    "$SETUP_DIR/modules/12-xrdp.sh"
)
for selector in 4 04 miniconda 04-miniconda.sh; do
    resolved="$(homelab_resolve_module "$selector" "${modules[@]}")"
    [ "$resolved" = "${modules[0]}" ] || fail "selector $selector resolved incorrectly"
done
[ "$(homelab_resolve_module nodejs "${modules[@]}")" = "${modules[1]}" ] || fail "module name did not resolve"
if homelab_resolve_module missing "${modules[@]}" >/dev/null 2>&1; then fail "unknown module resolved successfully"; fi

unique="$(homelab_unique_modules "${modules[@]}" -- 4 miniconda 07 nodejs)"
expected="${modules[0]}
${modules[1]}"
[ "$unique" = "$expected" ] || fail "duplicate selectors were not stably deduplicated"

echo "PASS: CLI options and stable module selectors are parsed correctly"
