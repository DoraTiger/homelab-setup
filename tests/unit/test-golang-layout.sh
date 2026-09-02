#!/bin/bash

set -euo pipefail

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODULE="$SETUP_ROOT/modules/05-golang.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

grep -q 'GO_BIN_DIR="\$HOME/.local/bin"' "$MODULE" ||
    fail "Go binary directory must use the persistent user binary directory"
grep -q 'export GOBIN="\$GO_BIN_DIR"' "$MODULE" ||
    fail "GOBIN must use the persistent user binary directory"

if grep -q 'export GOBIN="\\\$GOPATH/bin"' "$MODULE"; then
    fail "GOBIN must not be stored below the disposable GOPATH cache"
fi

grep -Fq 'export GOMODCACHE=\"\$GOPATH/mod\"' "$MODULE" ||
    fail "Go module downloads must remain in the workspace cache"
grep -Fq 'export GOCACHE=\"\$GOPATH/build\"' "$MODULE" ||
    fail "Go build cache must remain in the workspace cache"

echo "PASS: Go persistent/cache layout"
