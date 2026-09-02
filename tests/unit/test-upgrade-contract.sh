#!/bin/bash

set -euo pipefail

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

modules=(
    04-miniconda.sh 05-golang.sh 06-java.sh 07-nodejs.sh
    10-rust.sh 11-texlive.sh 13-zellij.sh 14-obsidian.sh 15-zotero.sh
)

for name in "${modules[@]}"; do
    grep -q 'upgrade_requested' "$SETUP_ROOT/modules/$name" ||
        fail "$name does not honor explicit upgrade mode"
done

echo "PASS: language and tool upgrade contract"
