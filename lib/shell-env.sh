#!/bin/bash

# Shell environment convergence. Functions create files only when called.

ensure_bashrc_d_loader() {
    mkdir -p "$HOME/.bashrc.d"
    if ! grep -qF 'Load environment snippets' "$HOME/.bashrc" 2>/dev/null; then
        cat <<'SNIPPET' >> "$HOME/.bashrc"

# Load environment snippets
if [ -d "$HOME/.bashrc.d" ]; then
    for f in "$HOME"/.bashrc.d/*.sh; do
        [ -f "$f" ] && . "$f"
    done
fi
SNIPPET
        log_success ".bashrc.d 加载逻辑已写入 .bashrc"
    fi
}

ensure_shell_env_loader() {
    local config_dir="$HOME/.config/homelab"
    local loader_file="$config_dir/bash-env.sh"
    local base_tmp loader_tmp
    local profile_marker="# Load homelab non-interactive environment"
    local profile_begin="# BEGIN homelab non-interactive environment"
    local bashrc_marker="# Load homelab environment before interactive guard"

    mkdir -p "$config_dir" "$HOME/.profile.d"
    base_tmp="$(mktemp)"
    cat > "$base_tmp" <<'BASE'
# Base user environment (managed by homelab setup)
homelab_path_prepend "$HOME/.local/bin"
BASE
    homelab_atomic_install_user "$base_tmp" "$HOME/.profile.d/00-base.sh" 644
    rm -f "$base_tmp"

    loader_tmp="$(mktemp)"
    cat > "$loader_tmp" <<'LOADER'
# Homelab shell environment loader (managed by homelab setup)
homelab_path_prepend() {
    homelab_var_prepend PATH "$1"
}

homelab_var_prepend() {
    local variable_name="$1"
    local entry="$2"
    local current_value="${!variable_name:-}"
    case ":$current_value:" in
        *":$entry:"*) ;;
        *) printf -v "$variable_name" '%s' "$entry${current_value:+:$current_value}" ;;
    esac
    export "$variable_name"
}

if [ -d "$HOME/.profile.d" ]; then
    for homelab_env_file in "$HOME"/.profile.d/*.sh; do
        [ -f "$homelab_env_file" ] && . "$homelab_env_file"
    done
    unset homelab_env_file
fi

unset -f homelab_path_prepend
unset -f homelab_var_prepend
LOADER
    homelab_atomic_install_user "$loader_tmp" "$loader_file" 644
    rm -f "$loader_tmp"

    [ -e "$HOME/.profile" ] || : > "$HOME/.profile"
    [ -e "$HOME/.bashrc" ] || : > "$HOME/.bashrc"

    if grep -qFx "$profile_marker" "$HOME/.profile" && ! grep -qFx "$profile_begin" "$HOME/.profile"; then
        local profile_tmp
        profile_tmp="$(mktemp)"
        awk -v marker="$profile_marker" '
            $0 == marker { skip = 2; next }
            skip > 0 { skip--; next }
            { print }
        ' "$HOME/.profile" > "$profile_tmp"
        chmod --reference="$HOME/.profile" "$profile_tmp"
        mv "$profile_tmp" "$HOME/.profile"
    fi

    if ! grep -qFx "$profile_begin" "$HOME/.profile"; then
        cat <<'PROFILE' >> "$HOME/.profile"

# BEGIN homelab non-interactive environment
if [ -n "${BASH_VERSION:-}" ]; then
    export BASH_ENV="$HOME/.config/homelab/bash-env.sh"
    [ -f "$BASH_ENV" ] && . "$BASH_ENV"
fi
# END homelab non-interactive environment
PROFILE
    fi

    if ! grep -qF "$bashrc_marker" "$HOME/.bashrc"; then
        local bashrc_tmp
        bashrc_tmp="$(mktemp)"
        cat > "$bashrc_tmp" <<'BASHRC'
# Load homelab environment before interactive guard
export BASH_ENV="$HOME/.config/homelab/bash-env.sh"
[ -f "$BASH_ENV" ] && . "$BASH_ENV"

BASHRC
        cat "$HOME/.bashrc" >> "$bashrc_tmp"
        chmod --reference="$HOME/.bashrc" "$bashrc_tmp"
        mv "$bashrc_tmp" "$HOME/.bashrc"
    fi
}

write_profile_env_file() {
    local name="$1" content="$2"
    local target="$HOME/.profile.d/$name.sh"
    ensure_shell_env_loader
    if [ ! -f "$target" ] || [ "$(cat "$target")" != "$content" ]; then
        printf '%s\n' "$content" > "$target"
        log_success "非交互环境配置已写入 $target"
    else
        log_success "非交互环境配置已是最新: $target"
    fi
}
