#!/bin/bash

# Path resolution and restricted setup-local configuration.
# Sourcing this file defines functions only and creates no filesystem state.

homelab_normalize_absolute_path() {
    local value="$1"
    local base="${2:-$PWD}"

    [ -n "$value" ] || {
        echo "path must not be empty" >&2
        return 1
    }
    case "$value" in
        *$'\n'*|*$'\r'*)
            echo "path must not contain a newline" >&2
            return 1
            ;;
    esac

    if [[ "$value" = /* ]]; then
        realpath -m -- "$value"
    else
        realpath -m -- "$base/$value"
    fi
}

homelab_read_local_workspace() {
    local config_file="$1"
    local line value=""

    [ -f "$config_file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            HOMELAB_WORKSPACE_ROOT=*) value="${line#*=}" ;;
        esac
    done < "$config_file"

    [ -z "$value" ] || homelab_normalize_absolute_path "$value" "$HOME"
}

homelab_write_local_workspace() {
    local config_file="$1"
    local workspace_value="$2"
    local workspace_path temp_file

    workspace_path="$(homelab_normalize_absolute_path "$workspace_value" "$HOME")" || return 1
    mkdir -p "$(dirname "$config_file")"
    temp_file="$(mktemp "${config_file}.tmp.XXXXXX")"
    printf 'HOMELAB_WORKSPACE_ROOT=%s\n' "$workspace_path" > "$temp_file"
    chmod 600 "$temp_file"

    if [ -f "$config_file" ] && cmp -s "$temp_file" "$config_file"; then
        rm -f "$temp_file"
        return 0
    fi
    mv "$temp_file" "$config_file"
}

homelab_initialize_paths() {
    local setup_value="$1"
    local local_workspace workspace_value

    SETUP_ROOT="$(homelab_normalize_absolute_path "$setup_value" "$PWD")" || return 1
    local_workspace="$(homelab_read_local_workspace "$SETUP_ROOT/.homelab.local")" || return 1
    workspace_value="${HOMELAB_WORKSPACE_ROOT:-${local_workspace:-$HOME/workspace}}"
    WORKSPACE_ROOT="$(homelab_normalize_absolute_path "$workspace_value" "$HOME")" || return 1

    CACHE_DIR="$(homelab_normalize_absolute_path "${HOMELAB_CACHE_DIR:-$WORKSPACE_ROOT/cache}" "$HOME")" || return 1
    PACKAGES_DIR="$(homelab_normalize_absolute_path "${HOMELAB_PACKAGES_DIR:-$WORKSPACE_ROOT/packages}" "$HOME")" || return 1
    BACKUP_DIR="$SETUP_ROOT/backup"
    KEYS_DIR="$SETUP_ROOT/keys"

    # Compatibility alias for modules that have not yet migrated.
    PROJECT_ROOT="$WORKSPACE_ROOT"

    export SETUP_ROOT WORKSPACE_ROOT CACHE_DIR PACKAGES_DIR BACKUP_DIR KEYS_DIR PROJECT_ROOT
}
