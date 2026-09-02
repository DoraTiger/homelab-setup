#!/bin/bash

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="${HOMELAB_TEST_ROOT:-$TESTS_DIR}"
RUN_ENVIRONMENT=0

if [ "$#" -gt 0 ]; then
    if [ "$#" -eq 1 ] && [ "$1" = --environment ]; then
        RUN_ENVIRONMENT=1
    else
        echo "Usage: bash tests/run.sh [--environment]" >&2
        exit 2
    fi
fi

mapfile -t test_files < <(
    find "$TEST_ROOT/unit" "$TEST_ROOT/integration" -maxdepth 1 -type f -name 'test-*.sh' 2>/dev/null | sort
)

passed=0
failed=0
for test_file in "${test_files[@]}"; do
    if output="$(bash "$test_file" 2>&1)"; then
        printf 'PASS  %s\n' "$test_file"
        passed=$((passed + 1))
    else
        printf 'FAIL  %s\n' "$test_file"
        printf '%s\n' "$output"
        failed=$((failed + 1))
    fi
done

if [ "$RUN_ENVIRONMENT" -eq 1 ]; then
    if output="$(bash "$TESTS_DIR/verify-environment.sh" 2>&1)"; then
        printf 'PASS  %s\n' "$TESTS_DIR/verify-environment.sh"
        printf '%s\n' "$output"
        passed=$((passed + 1))
    else
        printf 'FAIL  %s\n' "$TESTS_DIR/verify-environment.sh"
        printf '%s\n' "$output"
        failed=$((failed + 1))
    fi
fi

printf '\nSummary: %d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
