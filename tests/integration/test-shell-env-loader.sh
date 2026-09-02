#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$TEST_DIR/../.." && pwd)"

source "$SETUP_DIR/common.sh"

if ! declare -F ensure_shell_env_loader >/dev/null; then
    echo "FAIL: non-interactive shell environment loader is missing" >&2
    exit 1
fi

if ! declare -F write_profile_env_file >/dev/null; then
    echo "FAIL: managed profile environment writer is missing" >&2
    exit 1
fi

fixture_home="$(mktemp -d)"
trap 'rm -rf "$fixture_home"' EXIT

mkdir -p "$fixture_home/.profile.d" "$fixture_home/.bashrc.d" "$fixture_home/tools/bin" "$fixture_home/.local/bin"
printf '#!/bin/sh\nexit 0\n' > "$fixture_home/tools/bin/fixture-tool"
chmod +x "$fixture_home/tools/bin/fixture-tool"
printf '#!/bin/sh\nexit 0\n' > "$fixture_home/.local/bin/local-tool"
chmod +x "$fixture_home/.local/bin/local-tool"

cat > "$fixture_home/.profile.d/fixture.sh" <<'EOF'
homelab_path_prepend "$HOME/tools/bin"
homelab_var_prepend FIXTURE_LIST "$HOME/tools/lib"
export FIXTURE_ENV=loaded
EOF

cat > "$fixture_home/.bashrc.d/interactive.sh" <<'EOF'
export INTERACTIVE_HOOK_LOADED=yes
EOF

cat > "$fixture_home/.bashrc" <<'EOF'
case $- in
    *i*) ;;
      *) return;;
esac

if [ -d "$HOME/.bashrc.d" ]; then
    for f in "$HOME"/.bashrc.d/*.sh; do
        [ -f "$f" ] && . "$f"
    done
fi
EOF
chmod 640 "$fixture_home/.bashrc"

cat > "$fixture_home/.profile" <<'EOF'
# fixture profile

# Load homelab non-interactive environment
export BASH_ENV="$HOME/.config/homelab/bash-env.sh"
[ -f "$BASH_ENV" ] && . "$BASH_ENV"
EOF

HOME="$fixture_home" ensure_shell_env_loader

if [ "$(stat -c '%a' "$fixture_home/.bashrc")" != "640" ]; then
    echo "FAIL: installing the loader changed existing .bashrc permissions" >&2
    exit 1
fi

posix_output="$(env -u BASH_ENV HOME="$fixture_home" sh -c '. "$HOME/.profile"; printf posix-ok' 2>/dev/null || true)"
if [ "$posix_output" != "posix-ok" ]; then
    echo "FAIL: the Bash-specific loader broke a POSIX shell reading .profile" >&2
    exit 1
fi
HOME="$fixture_home" write_profile_env_file fixture '# fixture managed file
homelab_path_prepend "$HOME/tools/bin"
homelab_var_prepend FIXTURE_LIST "$HOME/tools/lib"
export FIXTURE_ENV=loaded'

managed_files=(
    "$fixture_home/.profile"
    "$fixture_home/.bashrc"
    "$fixture_home/.profile.d/00-base.sh"
    "$fixture_home/.config/homelab/bash-env.sh"
    "$fixture_home/.profile.d/fixture.sh"
)
before_mtimes="$(stat -c '%n:%Y' "${managed_files[@]}")"
sleep 1
HOME="$fixture_home" ensure_shell_env_loader
HOME="$fixture_home" write_profile_env_file fixture '# fixture managed file
homelab_path_prepend "$HOME/tools/bin"
homelab_var_prepend FIXTURE_LIST "$HOME/tools/lib"
export FIXTURE_ENV=loaded'
after_mtimes="$(stat -c '%n:%Y' "${managed_files[@]}")"
if [ "$before_mtimes" != "$after_mtimes" ]; then
    echo "FAIL: repeated loader convergence rewrote unchanged files" >&2
    diff -u <(printf '%s\n' "$before_mtimes") <(printf '%s\n' "$after_mtimes") >&2 || true
    exit 1
fi

noninteractive="$(env -u BASH_ENV HOME="$fixture_home" bash --noprofile --norc -c '
    . "$HOME/.profile"
    printf "%s|%s|%s" "$(command -v fixture-tool)" "$FIXTURE_ENV" "${INTERACTIVE_HOOK_LOADED:-}"
')"
expected="$fixture_home/tools/bin/fixture-tool|loaded|"
if [ "$noninteractive" != "$expected" ]; then
    echo "FAIL: login environment did not load only non-interactive-safe settings" >&2
    printf 'expected: %s\nactual:   %s\n' "$expected" "$noninteractive" >&2
    exit 1
fi

child="$(env -u BASH_ENV HOME="$fixture_home" bash --noprofile --norc -c '
    . "$HOME/.profile"
    bash --noprofile --norc -c '\''printf "%s|%s" "$(command -v fixture-tool)" "$FIXTURE_ENV"'\''
')"
expected_child="$fixture_home/tools/bin/fixture-tool|loaded"
if [ "$child" != "$expected_child" ]; then
    echo "FAIL: BASH_ENV did not propagate settings to a child bash -c" >&2
    exit 1
fi

path_count="$(env -u BASH_ENV HOME="$fixture_home" bash --noprofile --norc -c '
    . "$HOME/.profile"
    . "$BASH_ENV"
    awk -F: -v target="$HOME/tools/bin" '\''{ count=0; for (i=1; i<=NF; i++) if ($i==target) count++; print count }'\'' <<< "$PATH"
')"
if [ "$path_count" != "1" ]; then
    echo "FAIL: repeated environment loading duplicated PATH entries" >&2
    exit 1
fi

list_count="$(env -u BASH_ENV HOME="$fixture_home" bash --noprofile --norc -c '
    . "$HOME/.profile"
    . "$BASH_ENV"
    awk -F: -v target="$HOME/tools/lib" '\''{ count=0; for (i=1; i<=NF; i++) if ($i==target) count++; print count }'\'' <<< "$FIXTURE_LIST"
')"
if [ "$list_count" != "1" ]; then
    echo "FAIL: repeated environment loading duplicated a colon-separated variable" >&2
    exit 1
fi

manual_bashrc="$(env -u BASH_ENV HOME="$fixture_home" PATH=/usr/local/bin:/usr/bin:/bin bash --noprofile --norc -c '
    . "$HOME/.bashrc"
    printf "%s|%s|%s" "$(command -v fixture-tool)" "$(command -v local-tool)" "${INTERACTIVE_HOOK_LOADED:-}"
')"
if [ "$manual_bashrc" != "$fixture_home/tools/bin/fixture-tool|$fixture_home/.local/bin/local-tool|" ]; then
    echo "FAIL: .bashrc did not load safe settings before its non-interactive return" >&2
    exit 1
fi

echo "PASS: non-interactive and interactive shell settings are separated"
