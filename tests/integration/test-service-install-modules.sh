#!/bin/bash

set -euo pipefail

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

fake_bin="$fixture/bin"
test_home="$fixture/home"
workspace="$fixture/workspace"
network_marker="$fixture/network-used"
mkdir -p "$fake_bin" "$test_home" "$workspace"

cat > "$fake_bin/caddy" <<'EOF'
#!/bin/bash
case "${1:-}" in
    list-modules) printf '%s\n' http.handlers.reverse_proxy dns.providers.alidns ;;
    version) echo 'v2.test' ;;
esac
EOF
cat > "$fake_bin/code-server" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "--version" ]; then
    mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/code-server"
    touch "${XDG_CONFIG_HOME:-$HOME/.config}/code-server/config.yaml"
fi
echo '4.test with Code test'
EOF
cat > "$fake_bin/curl" <<'EOF'
#!/bin/bash
touch "$HOMELAB_TEST_NETWORK_MARKER"
exit 99
EOF
chmod +x "$fake_bin"/*

common_env=(
    HOME="$test_home"
    PATH="$fake_bin:/usr/bin:/bin"
    HOMELAB_WORKSPACE_ROOT="$workspace"
    HOMELAB_SILENT=1
    HOMELAB_UPGRADE=0
    HOMELAB_TEST_NETWORK_MARKER="$network_marker"
)

caddy_output="$(env "${common_env[@]}" bash "$SETUP_ROOT/modules/16-caddy.sh")" || fail "installed Caddy module failed"
code_server_output="$(env -u USER "${common_env[@]}" bash "$SETUP_ROOT/modules/17-code-server.sh")" || fail "installed code-server module failed without USER"
[ ! -e "$network_marker" ] || fail "default mode accessed the network for installed services"
[ ! -e "$test_home/.config/code-server/config.yaml" ] || fail "code-server version check wrote the user's config"
case "$caddy_output" in *'dns.providers.alidns'*) ;; *) fail "Caddy module did not verify AliDNS" ;; esac
case "$code_server_output" in *'4.test'*) ;; *) fail "code-server module did not verify the installed binary" ;; esac
case "$code_server_output" in *"code-server@$(id -un)"*) ;; *) fail "code-server guidance did not resolve the service user" ;; esac

cat > "$fake_bin/caddy" <<'EOF'
#!/bin/bash
case "${1:-}" in
    list-modules) printf '%s\n' http.handlers.reverse_proxy ;;
    version) echo 'v2.test' ;;
esac
EOF
chmod +x "$fake_bin/caddy"
if env "${common_env[@]}" bash "$SETUP_ROOT/modules/16-caddy.sh" >"$fixture/missing-go.log" 2>&1; then
    fail "Caddy build continued without Go"
fi
grep -q '05-golang.sh' "$fixture/missing-go.log" || fail "missing Go did not point to the Go module"

# When neither Caddy nor Go is available, prerequisite validation must happen
# before package installation or any other privileged system change.
minimal_bin="$fixture/minimal-bin"
privileged_marker="$fixture/privileged-command-used"
mkdir -p "$minimal_bin"
ln -s /usr/bin/dirname "$minimal_bin/dirname"
ln -s /usr/bin/realpath "$minimal_bin/realpath"
cat > "$minimal_bin/sudo" <<'EOF'
#!/bin/bash
touch "$HOMELAB_TEST_PRIVILEGED_MARKER"
exit 1
EOF
chmod +x "$minimal_bin/sudo"
if HOME="$test_home" \
    PATH="$minimal_bin" \
    HOMELAB_WORKSPACE_ROOT="$workspace" \
    HOMELAB_SILENT=1 \
    HOMELAB_UPGRADE=0 \
    HOMELAB_TEST_PRIVILEGED_MARKER="$privileged_marker" \
    /bin/bash "$SETUP_ROOT/modules/16-caddy.sh" >"$fixture/missing-tools.log" 2>&1; then
    fail "Caddy installation continued without Caddy or Go"
fi
[ ! -e "$privileged_marker" ] || fail "Caddy changed system state before validating Go"
grep -q '05-golang.sh' "$fixture/missing-tools.log" || fail "early Go prerequisite failure omitted recovery guidance"

echo "PASS: service modules skip installed components and enforce Caddy build prerequisites"
