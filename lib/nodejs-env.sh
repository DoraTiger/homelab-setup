#!/bin/bash

render_nodejs_profile_env() {
    local user_home="$1"
    local fnm_install_dir="$user_home/.local/opt/fnm"
    local fnm_data_dir="$user_home/.local/share/fnm"
    local npm_prefix_dir="$user_home/.local/npm-global"

    cat <<EOF
# Node.js environment (managed by homelab setup)
export FNM_INSTALL_DIR="$fnm_install_dir"
export FNM_DIR="$fnm_data_dir"
homelab_path_prepend "\$FNM_INSTALL_DIR"
homelab_path_prepend "\$FNM_DIR/aliases/default/bin"
homelab_path_prepend "$npm_prefix_dir/bin"
EOF
}

render_nodejs_interactive_env() {
    cat <<'EOF'
# Node.js interactive environment (managed by homelab setup)
eval "$(fnm env --use-on-cd)" >/dev/null 2>&1
EOF
}

migrate_legacy_fnm_data() {
    local install_dir="$1"
    local data_dir="$2"
    local backup_dir="$3"
    local legacy_entry
    local has_legacy=false

    for legacy_entry in node-versions aliases; do
        if [ -e "$install_dir/$legacy_entry" ] || [ -L "$install_dir/$legacy_entry" ]; then
            has_legacy=true
        fi
    done

    if [ "$has_legacy" = false ]; then
        return 0
    fi

    if [ -e "$backup_dir" ]; then
        echo "Backup path already exists: $backup_dir" >&2
        return 1
    fi

    mkdir -p "$data_dir" "$backup_dir"
    for legacy_entry in node-versions aliases; do
        if [ -e "$install_dir/$legacy_entry" ] || [ -L "$install_dir/$legacy_entry" ]; then
            mv "$install_dir/$legacy_entry" "$backup_dir/$legacy_entry"
        fi
    done
}
