#!/bin/bash

set -euo pipefail

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

test_home="$fixture/home"
workspace="$fixture/workspace"
fnm_dir="$test_home/.local/opt/fnm"
node_dir="$test_home/.local/share/fnm/node-versions/v20.0.0/installation"
default_link="$test_home/.local/share/fnm/aliases/default"
fake_bin="$fixture/bin"
mkdir -p "$fnm_dir" "$node_dir/bin" "$(dirname "$default_link")" "$fake_bin" "$workspace"
ln -s "$node_dir" "$default_link"

cat > "$fnm_dir/fnm" <<'EOF'
#!/bin/bash
case "${1:-}" in
    --version) echo 'fnm 1.39.0' ;;
    list) echo '* v20.0.0 default' ;;
    env) exit 0 ;;
    install|upgrade|default) exit 0 ;;
esac
EOF
chmod +x "$fnm_dir/fnm"

cat > "$node_dir/bin/node" <<'EOF'
#!/bin/bash
echo 'v20.0.0'
EOF

cat > "$node_dir/bin/npm" <<'EOF'
#!/bin/bash
if [ "${1:-}" = config ] && [ "${2:-}" = get ]; then
    case "${3:-}" in
        prefix) echo "$HOME/.local/npm-global" ;;
        cache) echo "$HOMELAB_WORKSPACE_ROOT/cache/npm" ;;
        registry) echo 'https://registry.npmmirror.com' ;;
    esac
elif [ "${1:-}" = -v ]; then
    echo '10.0.0'
fi
EOF
chmod +x "$node_dir/bin/node" "$node_dir/bin/npm"

cat > "$fake_bin/curl" <<'EOF'
#!/bin/bash
output=''
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then output="$2"; shift 2; else shift; fi
done
[ -n "$output" ] || exit 2
printf '%s\n' '#!/bin/bash' 'exit 42' > "$output"
EOF
chmod +x "$fake_bin/curl"

if ! HOME="$test_home" \
    PATH="$fake_bin:$PATH" \
    HOMELAB_WORKSPACE_ROOT="$workspace" \
    HOMELAB_SILENT=1 \
    HOMELAB_UPGRADE=1 \
    bash "$SETUP_ROOT/modules/07-nodejs.sh" >"$fixture/output.log" 2>&1; then
    cat "$fixture/output.log" >&2
    echo "FAIL: an optional fnm upgrade failure aborted the Node.js module" >&2
    exit 1
fi

grep -q 'fnm 升级失败，保留当前版本' "$fixture/output.log" || {
    cat "$fixture/output.log" >&2
    echo "FAIL: fnm installer failure was not reported as a recoverable warning" >&2
    exit 1
}

echo "PASS: Node.js configuration continues after an optional fnm upgrade failure"
