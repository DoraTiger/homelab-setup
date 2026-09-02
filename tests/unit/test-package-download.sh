#!/bin/bash

set -euo pipefail

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

mkdir -p "$fixture/bin" "$fixture/packages/tool"
cat > "$fixture/bin/curl" <<'EOF'
#!/bin/bash
output=""
url=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) output="$2"; shift 2 ;;
        http*) url="$1"; shift ;;
        *) shift ;;
    esac
done
printf '%s|%s|%s|%s\n' "$url" "${http_proxy:-}" "${HTTPS_PROXY:-}" "${ALL_PROXY:-}" >> "$DOWNLOAD_TEST_LOG"
attempts=0
[ ! -f "$DOWNLOAD_TEST_ATTEMPTS" ] || attempts="$(cat "$DOWNLOAD_TEST_ATTEMPTS")"
attempts=$((attempts + 1))
printf '%s\n' "$attempts" > "$DOWNLOAD_TEST_ATTEMPTS"
[ "$attempts" -ge "${DOWNLOAD_TEST_SUCCEED_ON:-1}" ] || exit 22
printf '%s\n' "${DOWNLOAD_TEST_CONTENT:-valid archive}" > "$output"
EOF
chmod +x "$fixture/bin/curl"

export PATH="$fixture/bin:/usr/bin:/bin"
export DOWNLOAD_TEST_LOG="$fixture/download.log"
export DOWNLOAD_TEST_ATTEMPTS="$fixture/attempts"
export PROXY_ADDR="socks5://127.0.0.1:7890"
log_info() { :; }
log_success() { :; }
log_warn() { :; }
log_error() { :; }
source "$SETUP_ROOT/lib/network.sh"

unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
export_proxy_environment
proxy_snapshot="$(bash -c 'printf "%s|%s|%s|%s" "$http_proxy" "$https_proxy" "$HTTPS_PROXY" "$ALL_PROXY"')"
[ "$proxy_snapshot" = 'socks5://127.0.0.1:7890|socks5://127.0.0.1:7890|socks5://127.0.0.1:7890|socks5://127.0.0.1:7890' ] || \
    fail "proxy environment was not inherited by nested downloaders"

printf '%s\n' '#!/bin/sh' 'exit 0' > "$fixture/installer.sh"
validate_shell_script "$fixture/installer.sh" || fail "valid shell installer was rejected"
printf '%s\n' '<html>upstream error</html>' > "$fixture/not-installer.sh"
if validate_shell_script "$fixture/not-installer.sh"; then fail "HTML response was accepted as a shell installer"; fi
printf '\177ELFpayload' > "$fixture/program"
validate_elf_binary "$fixture/program" || fail "ELF executable was rejected"
if validate_elf_binary "$fixture/not-installer.sh"; then fail "HTML response was accepted as an ELF executable"; fi

mkdir -p "$fixture/archive-input"
printf '%s\n' payload > "$fixture/archive-input/file"
tar -czf "$fixture/archive.tar.gz" -C "$fixture/archive-input" file
validate_tar_archive "$fixture/archive.tar.gz" || fail "valid tar archive was rejected"
printf '%s\n' truncated > "$fixture/broken.tar.gz"
if validate_tar_archive "$fixture/broken.tar.gz"; then fail "broken tar archive was accepted"; fi

legacy="$fixture/cache/tool/legacy.tar.gz"
migrated="$fixture/packages/tool/migrated.tar.gz"
mkdir -p "$(dirname "$legacy")"
cp "$fixture/archive.tar.gz" "$legacy"
migrate_legacy_package "$legacy" "$migrated" validate_tar_archive || fail "valid legacy package was not migrated"
[ -f "$migrated" ] || fail "migrated package is missing"
[ ! -e "$legacy" ] || fail "legacy package was left behind after migration"

mkdir -p "$fixture/versioned"
cp "$fixture/archive.tar.gz" "$fixture/versioned/tool-1.9.tar.gz"
cp "$fixture/archive.tar.gz" "$fixture/versioned/tool-1.10.tar.gz"
printf '%s\n' broken > "$fixture/versioned/tool-2.0.tar.gz"
latest_valid="$(find_latest_valid_package "$fixture/versioned" 'tool-*.tar.gz' validate_tar_archive)"
[ "$latest_valid" = "$fixture/versioned/tool-1.10.tar.gz" ] || fail "latest valid cached package was not selected"

validate_archive() {
    grep -q '^valid archive$' "$1"
}

destination="$fixture/packages/tool/tool.tar.gz"
printf '%s\n' 'valid archive' > "$destination"
download_package 'https://example.invalid/tool.tar.gz' "$destination" validate_archive || fail "valid cache was rejected"
[ ! -e "$DOWNLOAD_TEST_LOG" ] || fail "valid cache unexpectedly accessed the network"

printf '%s\n' 'broken archive' > "$destination"
export DOWNLOAD_TEST_SUCCEED_ON=2
download_package 'https://example.invalid/tool.tar.gz' "$destination" validate_archive || fail "retryable download failed"
[ "$(cat "$DOWNLOAD_TEST_ATTEMPTS")" = 2 ] || fail "download did not retry exactly once before success"
[ "$(cat "$destination")" = 'valid archive' ] || fail "validated download was not installed atomically"
[ ! -e "$destination.part" ] || fail "partial download was left behind"

proxy_line="$(tail -n1 "$DOWNLOAD_TEST_LOG")"
case "$proxy_line" in
    *'socks5://127.0.0.1:7890|socks5://127.0.0.1:7890|socks5://127.0.0.1:7890'*) ;;
    *) fail "proxy was not exported in lower- and upper-case forms: $proxy_line" ;;
esac

printf '%s\n' 'known good cache' > "$destination"
export DOWNLOAD_TEST_CONTENT='invalid response'
export DOWNLOAD_TEST_SUCCEED_ON=1
printf '%s\n' 0 > "$DOWNLOAD_TEST_ATTEMPTS"
if download_package 'https://example.invalid/tool.tar.gz' "$destination" validate_archive; then
    fail "invalid downloaded content was accepted"
fi
[ "$(cat "$destination")" = 'known good cache' ] || fail "failed download replaced the previous cache"
[ ! -e "$destination.part" ] || fail "failed validation left a partial file"

echo "PASS: package downloads reuse valid cache and update it atomically with proxy and retries"
