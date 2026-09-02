#!/bin/bash

set -euo pipefail

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

for option in --help -h; do
    if ! output="$(bash "$SETUP_ROOT/init.sh" "$option" 2>&1)"; then
        printf '%s\n' "$output" >&2
        fail "$option did not exit successfully"
    fi

    case "$output" in
        *'Usage:'*'--silent'*'--upgrade'*'--proxy'*'--workspace-root'*'MODULE'*) ;;
        *) printf '%s\n' "$output" >&2; fail "$option omitted required usage information" ;;
    esac

    case "$output" in
        *'▶ ['*|*'全部完成'*) fail "$option executed setup modules" ;;
    esac
done

echo "PASS: root help describes the CLI without executing modules"
