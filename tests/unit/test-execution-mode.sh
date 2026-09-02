#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$TEST_DIR/../.." && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }

if env -u HOMELAB_UPGRADE bash -c 'source "$1/common.sh"; upgrade_requested' _ "$SETUP_DIR"; then
    fail "unset upgrade mode enabled upgrades"
fi
if HOMELAB_UPGRADE=0 bash -c 'source "$1/common.sh"; upgrade_requested' _ "$SETUP_DIR"; then
    fail "zero upgrade mode enabled upgrades"
fi
HOMELAB_UPGRADE=1 bash -c 'source "$1/common.sh"; upgrade_requested' _ "$SETUP_DIR" || fail "explicit upgrade mode was ignored"
if HOMELAB_UPGRADE=invalid bash -c 'source "$1/common.sh"' _ "$SETUP_DIR" >/dev/null 2>&1; then
    fail "invalid upgrade mode was accepted"
fi

source "$SETUP_DIR/lib/cli.sh"
homelab_parse_init_args --silent
[ "$CLI_SILENT:$CLI_UPGRADE" = 1:0 ] || fail "silent mode implicitly enabled upgrades"
homelab_parse_init_args --upgrade
[ "$CLI_SILENT:$CLI_UPGRADE" = 0:1 ] || fail "--upgrade did not enable upgrade mode"

echo "PASS: upgrades require an explicit valid mode"
