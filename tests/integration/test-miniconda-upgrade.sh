#!/bin/bash

set -euo pipefail

SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

test_home="$fixture/home"
workspace="$fixture/workspace"
conda_bin="$test_home/.local/opt/miniconda3/bin/conda"
command_log="$fixture/conda.log"
mkdir -p "$(dirname "$conda_bin")" "$workspace"

cat > "$conda_bin" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$HOMELAB_TEST_COMMAND_LOG"
case " $* " in
    *' defaults '*|*'repo.anaconda.com'*)
        echo 'simulated non-interactive Anaconda ToS failure' >&2
        exit 64
        ;;
esac
case "${1:-}" in
    --version) echo 'conda 26.7.1' ;;
    info) echo "$HOME/.local/opt/miniconda3" ;;
esac
EOF
chmod +x "$conda_bin"

if ! HOME="$test_home" \
    HOMELAB_WORKSPACE_ROOT="$workspace" \
    HOMELAB_SILENT=1 \
    HOMELAB_UPGRADE=1 \
    HOMELAB_TEST_COMMAND_LOG="$command_log" \
    bash "$SETUP_ROOT/modules/04-miniconda.sh" >"$fixture/output.log" 2>&1; then
    cat "$fixture/output.log" >&2
    echo "FAIL: Miniconda upgrade used a channel that requires interactive ToS acceptance" >&2
    exit 1
fi

if grep -Eq '(^|[[:space:]])defaults([[:space:]]|$)|repo\.anaconda\.com' "$command_log" "$test_home/.condarc"; then
    echo "FAIL: Miniconda managed configuration still falls back to Anaconda defaults" >&2
    exit 1
fi

grep -q 'mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main' "$command_log" || {
    echo "FAIL: Miniconda upgrade did not select the managed Tsinghua channel" >&2
    exit 1
}

echo "PASS: Miniconda upgrade avoids interactive Anaconda ToS channels"
