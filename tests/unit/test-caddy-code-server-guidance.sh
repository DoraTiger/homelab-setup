#!/bin/bash

set -euo pipefail

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CADDY_HELPER="$SETUP_ROOT/lib/caddy-install.sh"
CODE_SERVER_HELPER="$SETUP_ROOT/lib/code-server-install.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[ -f "$CADDY_HELPER" ] || fail "Caddy install helper is missing"
[ -f "$CODE_SERVER_HELPER" ] || fail "code-server install helper is missing"
source "$CADDY_HELPER"
source "$CODE_SERVER_HELPER"

if ! declare -F prepare_code_server_curl_config >/dev/null; then
    fail "code-server installer curl policy is missing"
fi

caddy_go_version_supported 'go1.25.0' || fail "Go 1.25 was rejected"
caddy_go_version_supported 'go1.26.4' || fail "Go 1.26 was rejected"
if caddy_go_version_supported 'go1.24.9'; then fail "Go 1.24 was accepted"; fi
if caddy_go_version_supported 'invalid'; then fail "invalid Go version was accepted"; fi

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
curl_home="$fixture/curl-home"
prepare_code_server_curl_config "$curl_home"
curl_config="$(cat "$curl_home/.curlrc")"
case "$curl_config" in
    *'connect-timeout = 10'*'max-time = 300'*'retry = 3'*'retry-all-errors'*) ;;
    *) fail "code-server installer curl policy is not bounded and retryable" ;;
esac

cat > "$fixture/code-server-version" <<'EOF'
#!/bin/bash
mkdir -p "$XDG_CONFIG_HOME/code-server"
touch "$XDG_CONFIG_HOME/code-server/config.yaml"
printf '%s\n' 'info: wrote temporary config' '4.135.0 abc with Code 1.96.4'
EOF
chmod +x "$fixture/code-server-version"
version="$(HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/user-config" code_server_version "$fixture/code-server-version")"
[ "$version" = '4.135.0 abc with Code 1.96.4' ] || fail "code-server version parser did not select the version line"
[ ! -e "$fixture/user-config/code-server/config.yaml" ] || fail "code-server version helper touched the user config"

cat > "$fixture/caddy-with-alidns" <<'EOF'
#!/bin/bash
[ "${1:-}" = list-modules ] && printf '%s\n' http.handlers.reverse_proxy dns.providers.alidns
EOF
cat > "$fixture/caddy-without-alidns" <<'EOF'
#!/bin/bash
[ "${1:-}" = list-modules ] && printf '%s\n' http.handlers.reverse_proxy
EOF
chmod +x "$fixture"/caddy-*

caddy_binary_has_alidns "$fixture/caddy-with-alidns" || fail "AliDNS-enabled Caddy was rejected"
if caddy_binary_has_alidns "$fixture/caddy-without-alidns"; then fail "standard Caddy was treated as AliDNS-enabled"; fi

caddy_guide="$(render_caddy_next_steps)"
case "$caddy_guide" in
    *'/etc/caddy/alidns.env'*'ALIYUN_ACCESS_KEY_ID=<ACCESS_KEY_ID>'*'ALIYUN_ACCESS_KEY_SECRET=<ACCESS_KEY_SECRET>'*'EnvironmentFile=/etc/caddy/alidns.env'*'dns alidns'*'caddy validate'*) ;;
    *) fail "Caddy guidance omitted the AliDNS configuration workflow" ;;
esac
case "$caddy_guide" in
    *'--environ'*|*'superheaoz'*|*'192.168.'*) fail "Caddy guidance contains unsafe or private deployment values" ;;
esac

code_server_guide="$(render_code_server_next_steps 'sample-user')"
case "$code_server_guide" in
    *'127.0.0.1:<PORT>'*'code-server@sample-user'*'bash init.sh --silent caddy'*'reverse_proxy 127.0.0.1:<PORT>'*) ;;
    *) fail "code-server guidance omitted localhost or Caddy next steps" ;;
esac
case "$code_server_guide" in
    *'superheaoz'*|*'192.168.'*) fail "code-server guidance contains private deployment values" ;;
esac

echo "PASS: Caddy and code-server guidance is generic and credential-safe"
