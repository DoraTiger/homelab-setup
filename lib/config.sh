#!/bin/bash

# Generic file convergence and setup-local backup helpers.

homelab_validate_target_path() {
    local target="$1"
    [ -n "$target" ] && [ "$target" != / ] && [[ "$target" = /* ]]
}

homelab_validate_backup_component() {
    local component="$1"
    [ -n "$component" ] && [[ "$component" =~ ^[A-Za-z0-9._-]+$ ]] &&
        [ "$component" != . ] && [ "$component" != .. ]
}

homelab_files_equal() {
    local source_file="$1" target_file="$2"
    [ -f "$source_file" ] && [ -f "$target_file" ] && cmp -s "$source_file" "$target_file"
}

homelab_backup_path() {
    local module="$1" timestamp="$2" name="$3"
    homelab_validate_backup_component "$module" || return 1
    homelab_validate_backup_component "$timestamp" || return 1
    homelab_validate_backup_component "$name" || return 1
    printf '%s/%s/%s/%s\n' "$BACKUP_DIR" "$module" "$timestamp" "$name"
}

homelab_backup_user_file() {
    local module="$1" timestamp="$2" source_file="$3"
    local name="${4:-$(basename "$source_file")}" destination
    [ -e "$source_file" ] || return 0
    destination="$(homelab_backup_path "$module" "$timestamp" "$name")" || return 1
    [ ! -e "$destination" ] || { echo "backup already exists: $destination" >&2; return 1; }
    install -d -m 700 "$(dirname "$destination")"
    cp -a "$source_file" "$destination"
}

homelab_backup_system_file() {
    local module="$1" timestamp="$2" source_file="$3"
    local name="${4:-$(basename "$source_file")}" destination
    [ -e "$source_file" ] || return 0
    destination="$(homelab_backup_path "$module" "$timestamp" "$name")" || return 1
    [ ! -e "$destination" ] || { echo "backup already exists: $destination" >&2; return 1; }
    ensure_sudo || return 1
    install -d -m 700 "$(dirname "$destination")"
    run_as_root cp -a "$source_file" "$destination"
}

homelab_atomic_install_user() {
    local source_file="$1" target_file="$2" mode="${3:-}"
    local target_dir temp_file
    [ -f "$source_file" ] || return 1
    homelab_validate_target_path "$target_file" || return 1
    homelab_files_equal "$source_file" "$target_file" && return 0

    target_dir="$(dirname "$target_file")"
    mkdir -p "$target_dir"
    temp_file="$(mktemp "$target_dir/.homelab.XXXXXX")"
    if [ -n "$mode" ]; then
        install -m "$mode" "$source_file" "$temp_file"
    elif [ -e "$target_file" ]; then
        cp "$source_file" "$temp_file"
        chmod --reference="$target_file" "$temp_file"
    else
        cp --preserve=mode "$source_file" "$temp_file"
    fi
    mv "$temp_file" "$target_file"
}

homelab_install_system_file() {
    local source_file="$1" target_file="$2" mode="$3" owner="$4" group="$5"
    [ -f "$source_file" ] || return 1
    homelab_validate_target_path "$target_file" || return 1
    if homelab_files_equal "$source_file" "$target_file" &&
        [ "$(stat -c '%a:%U:%G' "$target_file")" = "$mode:$owner:$group" ]; then
        return 0
    fi
    run_as_root install -m "$mode" -o "$owner" -g "$group" "$source_file" "$target_file"
}
