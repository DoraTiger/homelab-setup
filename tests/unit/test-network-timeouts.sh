#!/bin/bash

set -euo pipefail

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/bin"
command_log="$fixture/commands.log"
export HOMELAB_TEST_COMMAND_LOG="$command_log"

for command_name in curl wget; do
    command_path="$fixture/bin/$command_name"
    printf '%s\n' '#!/bin/bash' 'printf "%s\\t" "$(basename "$0")" >> "$HOMELAB_TEST_COMMAND_LOG"' \
        'printf "%s " "$@" >> "$HOMELAB_TEST_COMMAND_LOG"' \
        'printf "\\n" >> "$HOMELAB_TEST_COMMAND_LOG"' > "$command_path"
    chmod +x "$command_path"
done

PATH="$fixture/bin:$PATH"
source "$SETUP_ROOT/lib/network.sh"

run_with_optional_proxy curl -fsSL https://example.invalid/archive.tar.gz
run_with_optional_proxy wget -qO- https://example.invalid/version.txt

curl_line="$(sed -n '1p' "$command_log")"
wget_line="$(sed -n '2p' "$command_log")"

case "$curl_line" in
    *'--connect-timeout 10'*'--max-time 180'*) ;;
    *) echo "FAIL: curl downloads do not receive bounded timeouts: $curl_line" >&2; exit 1 ;;
esac

case "$wget_line" in
    *'--timeout=30'*'--tries=3'*) ;;
    *) echo "FAIL: wget downloads do not receive bounded retries: $wget_line" >&2; exit 1 ;;
esac

echo "PASS: network downloads receive bounded timeout defaults"
