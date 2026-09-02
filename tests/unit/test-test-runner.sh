#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$TEST_DIR/../.." && pwd)"
RUNNER="$SETUP_DIR/tests/run.sh"
[ -f "$RUNNER" ] || { echo "FAIL: test runner is missing: $RUNNER" >&2; exit 1; }

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT
mkdir -p "$fixture_root/unit" "$fixture_root/integration"
printf '#!/bin/bash\necho PASS-A\n' > "$fixture_root/unit/test-a.sh"
printf '#!/bin/bash\necho FAIL-B\nexit 1\n' > "$fixture_root/integration/test-b.sh"
chmod +x "$fixture_root/unit/test-a.sh" "$fixture_root/integration/test-b.sh"

if HOMELAB_TEST_ROOT="$fixture_root" bash "$RUNNER" > "$fixture_root/output" 2>&1; then
    echo "FAIL: runner ignored a failing test" >&2
    exit 1
fi
grep -q 'PASS.*test-a.sh' "$fixture_root/output" || { echo "FAIL: runner omitted passing test" >&2; exit 1; }
grep -q 'FAIL.*test-b.sh' "$fixture_root/output" || { echo "FAIL: runner omitted failing test" >&2; exit 1; }
grep -q '1 passed, 1 failed' "$fixture_root/output" || { echo "FAIL: runner summary is incorrect" >&2; exit 1; }

echo "PASS: test runner reports and propagates failures"
