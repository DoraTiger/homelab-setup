#!/bin/bash

set -euo pipefail

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICE_ENTRYPOINT="$SETUP_ROOT/service.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[ -f "$SERVICE_ENTRYPOINT" ] || fail "service.sh is missing"

help_output="$(bash "$SERVICE_ENTRYPOINT" --help)"
case "$help_output" in
    *'Usage: bash service.sh'*'docker'*'00-guacamole.sh'*) ;;
    *) fail "service help does not describe the Docker service selector" ;;
esac

if bash "$SERVICE_ENTRYPOINT" --silent > /dev/null 2>&1; then
    fail "silent mode ran without an explicit service selection"
fi

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/workspace"

cat > "$fixture/bin/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$HOMELAB_TEST_DOCKER_LOG"
if [ "${1:-}" = compose ] && [ "${2:-}" = version ]; then
    echo 'Docker Compose version v2.test'
    exit 0
fi
if [ "${1:-}" = info ]; then exit 0; fi
if [ "${1:-}" = image ] && [ "${2:-}" = inspect ]; then exit 0; fi
if [ "${1:-}" = run ]; then printf '%s\n' 'CREATE TABLE guacamole_test (id integer);'; exit 0; fi
if [ "${1:-}" = compose ]; then exit 0; fi
exit 98
EOF
chmod +x "$fixture/bin/docker"

output="$(
    HOME="$fixture/home" \
    PATH="$fixture/bin:/usr/bin:/bin" \
    HOMELAB_WORKSPACE_ROOT="$fixture/workspace" \
    HOMELAB_TEST_DOCKER_LOG="$fixture/docker.log" \
    bash "$SERVICE_ENTRYPOINT" --silent docker 00
)" || fail "docker service selector failed"

[ -f "$fixture/workspace/services/docker/guacamole/compose.yaml" ] ||
    fail "selected Guacamole service did not generate compose.yaml"
grep -qx 'info' "$fixture/docker.log" || fail "Docker daemon access was not checked"
case "$output" in
    *'00-guacamole.sh'*) ;;
    *) fail "service execution did not identify the selected service" ;;
esac

: > "$fixture/docker.log"
HOME="$fixture/home" \
PATH="$fixture/bin:/usr/bin:/bin" \
HOMELAB_WORKSPACE_ROOT="$fixture/workspace" \
HOMELAB_TEST_DOCKER_LOG="$fixture/docker.log" \
bash "$SERVICE_ENTRYPOINT" --silent --upgrade docker 00 >/dev/null ||
    fail "service entrypoint rejected upgrade mode"
grep -qx 'compose pull' "$fixture/docker.log" || fail "--upgrade was not propagated to the service"

echo "PASS: service entrypoint requires explicit, stable service selection"
