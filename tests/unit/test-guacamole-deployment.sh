#!/bin/bash

set -euo pipefail

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICE="$SETUP_ROOT/services/docker/00-guacamole.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[ -f "$SERVICE" ] || fail "Guacamole service script is missing"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/workspace" "$fixture/images"

cat > "$fixture/bin/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$HOMELAB_TEST_DOCKER_LOG"
if [ "${1:-}" = compose ] && [ "${2:-}" = version ]; then
    echo 'Docker Compose version v2.test'
    exit 0
fi
if [ "${1:-}" = info ]; then exit 0; fi
if [ "${1:-}" = image ] && [ "${2:-}" = inspect ]; then
    image_key="$(printf '%s' "$3" | tr '/:' '__')"
    [ -e "$HOMELAB_TEST_IMAGE_DIR/$image_key" ]
    exit
fi
if [ "${1:-}" = pull ]; then
    image_key="$(printf '%s' "$2" | tr '/:' '__')"
    touch "$HOMELAB_TEST_IMAGE_DIR/$image_key"
    exit 0
fi
if [ "${1:-}" = run ]; then
    printf '%s\n' '-- Guacamole PostgreSQL schema' 'CREATE TABLE guacamole_test (id integer);'
    exit 0
fi
if [ "${1:-}" = compose ]; then
    case "${2:-}" in
        config|up|pull) exit 0 ;;
        ps) printf '%s\n' 'guacamole  running'; exit 0 ;;
    esac
fi
echo "unexpected docker command: $*" >&2
exit 97
EOF
chmod +x "$fixture/bin/docker"

run_service() {
    HOME="$fixture/home" \
    PATH="$fixture/bin:/usr/bin:/bin" \
    HOMELAB_WORKSPACE_ROOT="$fixture/workspace" \
    HOMELAB_SILENT=1 \
    HOMELAB_UPGRADE="${HOMELAB_TEST_UPGRADE:-0}" \
    HOMELAB_TEST_DOCKER_LOG="$fixture/docker.log" \
    HOMELAB_TEST_IMAGE_DIR="$fixture/images" \
    bash "$SERVICE"
}

: > "$fixture/docker.log"
first_output="$(run_service)" || fail "first Guacamole generation failed"
deployment="$fixture/workspace/services/docker/guacamole"
compose_file="$deployment/compose.yaml"
env_example="$deployment/.env.example"
env_file="$deployment/.env"
initdb_file="$deployment/initdb.sql"

[ -f "$compose_file" ] || fail "compose.yaml was not generated"
[ -f "$env_example" ] || fail ".env.example was not generated"
[ -f "$env_file" ] || fail "runtime .env was not generated"
[ "$(stat -c '%a' "$env_file")" = 600 ] || fail "runtime .env permissions are not 600"
grep -Eq '^GUACAMOLE_DB_PASSWORD=[0-9a-f]{64}$' "$env_file" || fail "database password was not randomly generated"
[ -s "$initdb_file" ] || fail "initdb.sql was not generated"
[ "$(stat -c '%a' "$initdb_file")" = 600 ] || fail "initdb.sql permissions are not 600"

grep -Fq 'image: postgres:17' "$compose_file" || fail "PostgreSQL image is not pinned"
grep -Fq 'image: guacamole/guacd:1.6.0' "$compose_file" || fail "guacd image is not pinned"
grep -Fq 'image: guacamole/guacamole:1.6.0' "$compose_file" || fail "Guacamole image is not pinned"
grep -Fq '127.0.0.1:${GUACAMOLE_PORT:-30090}:8080' "$compose_file" || fail "web port is not loopback-only"
grep -Fq 'GUACAMOLE_DB_PASSWORD' "$compose_file" || fail "database password variable is missing"
grep -Fq 'WEBAPP_CONTEXT: ROOT' "$compose_file" || fail "Guacamole root web context is not explicit"
grep -Fq 'name: guacamole' "$compose_file" || fail "Compose project name is not explicit"
grep -Fq 'name: guacamole_postgres-data' "$compose_file" || fail "PostgreSQL volume name is not explicit"
grep -Fq 'name: guacamole_guacamole' "$compose_file" || fail "Docker network name is not explicit"
grep -Fq 'container_name: guacamole-postgres' "$compose_file" || fail "PostgreSQL container name is not stable"

case "$(cat "$env_example")" in
    *'GUACAMOLE_DB_PASSWORD='*) ;;
    *) fail ".env.example omitted the database password variable" ;;
esac
case "$(cat "$env_example")" in
    *'guacadmin'*|*'ALIYUN_ACCESS_KEY'*|*'192.168.'*|*'superheaoz'*)
        fail "generated files contain credentials or private deployment values"
        ;;
esac

case "$first_output" in *'reverse_proxy 127.0.0.1:30090'*'<YOUR_DOMAIN>'*) ;; *) fail "Caddy guidance is incomplete" ;; esac
case "$first_output" in *'不要将 RDP 目标填写为 127.0.0.1'*) ;; *) fail "RDP target guidance is incomplete" ;; esac
case "$first_output" in *'guacamole  running'*) ;; *) fail "container status was not displayed" ;; esac

for image in postgres_17 guacamole_guacd_1.6.0 guacamole_guacamole_1.6.0; do
    [ -e "$fixture/images/$image" ] || fail "missing image was not pulled: $image"
done
grep -qx 'compose config' "$fixture/docker.log" || fail "Compose configuration was not validated"
grep -qx 'compose up -d --remove-orphans' "$fixture/docker.log" || fail "Compose stack was not converged"

printf '%s\n' '# user-managed compose' > "$compose_file"
printf '%s\n' 'GUACAMOLE_DB_PASSWORD=user-kept' > "$env_example"
runtime_env_before="$(cat "$env_file")"
initdb_before="$(cat "$initdb_file")"
compose_mtime="$(stat -c '%Y' "$compose_file")"
env_mtime="$(stat -c '%Y' "$env_example")"
sleep 1
: > "$fixture/docker.log"
second_output="$(run_service)" || fail "repeated Guacamole generation failed"

[ "$(cat "$compose_file")" = '# user-managed compose' ] || fail "existing compose.yaml was overwritten"
[ "$(cat "$env_example")" = 'GUACAMOLE_DB_PASSWORD=user-kept' ] || fail "existing .env.example was overwritten"
[ "$(stat -c '%Y' "$compose_file")" = "$compose_mtime" ] || fail "existing compose.yaml was rewritten"
[ "$(stat -c '%Y' "$env_example")" = "$env_mtime" ] || fail "existing .env.example was rewritten"
[ "$(cat "$env_file")" = "$runtime_env_before" ] || fail "runtime password changed on repeated execution"
[ "$(cat "$initdb_file")" = "$initdb_before" ] || fail "database schema changed on repeated execution"
if grep -q '^pull ' "$fixture/docker.log"; then fail "default repeated execution pulled an existing image"; fi
if grep -q '^compose pull$' "$fixture/docker.log"; then fail "default repeated execution refreshed images"; fi
case "$second_output" in
    *'保留已有文件'*) ;;
    *) fail "repeated execution did not report preserved files" ;;
esac

: > "$fixture/docker.log"
HOMELAB_TEST_UPGRADE=1 run_service >/dev/null || fail "upgrade deployment failed"
grep -qx 'compose pull' "$fixture/docker.log" || fail "upgrade mode did not refresh Compose images"
grep -qx 'compose up -d --remove-orphans' "$fixture/docker.log" || fail "upgrade mode did not converge containers"
[ "$(cat "$env_file")" = "$runtime_env_before" ] || fail "upgrade mode changed the database password"
[ "$(cat "$initdb_file")" = "$initdb_before" ] || fail "upgrade mode changed the database schema"

echo "PASS: Guacamole deployment generation is safe and idempotent"
