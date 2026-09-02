#!/bin/bash

set -euo pipefail

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODULE="$SETUP_ROOT/modules/04-miniconda.sh"

grep -q 'CONDA_PACKAGE_CACHE_DIR="\$CACHE_DIR/conda/pkgs"' "$MODULE" || {
    echo "FAIL: conda package cache must use workspace cache" >&2
    exit 1
}
grep -q 'PIP_CACHE_DIR="\$CACHE_DIR/pip"' "$MODULE" || {
    echo "FAIL: pip cache must use workspace cache" >&2
    exit 1
}
grep -q 'pkgs_dirs:' "$MODULE" || {
    echo "FAIL: .condarc must configure pkgs_dirs" >&2
    exit 1
}
grep -q 'cache-dir = ' "$MODULE" || {
    echo "FAIL: pip.conf must configure cache-dir" >&2
    exit 1
}

echo "PASS: Python package cache layout"
