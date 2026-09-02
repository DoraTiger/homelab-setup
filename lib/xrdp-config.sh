#!/bin/bash

# Pure configuration helpers for modules/12-xrdp.sh.
# These functions intentionally do not invoke sudo or systemctl so they can be
# exercised against temporary file trees.

render_xrdp_startwm() {
    local session_wrapper="${1:-/usr/local/bin/xrdp-xfce-session}"
    local dbus_runner="${2:-dbus-run-session}"

    cat <<EOF
#!/bin/sh

if test -r /etc/profile; then
    . /etc/profile
fi

if test -r ~/.profile; then
    . ~/.profile
fi

unset DBUS_SESSION_BUS_ADDRESS
unset SESSION_MANAGER

exec $dbus_runner -- $session_wrapper
EOF
}

xrdp_startwm_is_usable() {
    local startwm_file="$1"
    [ -f "$startwm_file" ] || return 1

    grep -Eq '^[[:space:]]*unset[[:space:]]+DBUS_SESSION_BUS_ADDRESS[[:space:]]*$' "$startwm_file" &&
        grep -Eq '^[[:space:]]*unset[[:space:]]+SESSION_MANAGER[[:space:]]*$' "$startwm_file" &&
        grep -Eq '^[[:space:]]*exec[[:space:]]+dbus-run-session[[:space:]]+--[[:space:]]+/usr/local/bin/xrdp-xfce-session[[:space:]]*$' "$startwm_file"
}

render_xrdp_xfce_session() {
    cat <<'EOF'
#!/bin/bash

set -euo pipefail

runtime_dir="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is required for an XRDP session}"
display_id="${DISPLAY#:}"
display_id="${display_id//[^A-Za-z0-9_.-]/_}"

if [ ! -d "$runtime_dir" ] || [ ! -w "$runtime_dir" ]; then
    echo "XRDP runtime directory is not writable: $runtime_dir" >&2
    exit 1
fi

umask 077
keyring_dir="$(mktemp -d "$runtime_dir/keyring-rdp-${display_id:-unknown}-XXXXXX")"
export GNOME_KEYRING_CONTROL="$keyring_dir"

gnome-keyring-daemon \
    --start \
    --components=secrets \
    --control-directory="$keyring_dir" \
    >/dev/null

exec startxfce4
EOF
}

render_fcitx5_autostart() {
    cat <<'EOF'
[Desktop Entry]
Type=Application
Name=Fcitx 5
Comment=Start Fcitx 5 Input Method
Exec=fcitx5 -d
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
EOF
}

fcitx5_autostart_is_usable() {
    local desktop_file="$1"
    [ -f "$desktop_file" ] || return 1

    grep -Eq '^[[:space:]]*Type=Application[[:space:]]*$' "$desktop_file" &&
        grep -Eq '^[[:space:]]*Exec=fcitx5[[:space:]]+-d[[:space:]]*$' "$desktop_file" &&
        grep -Eq '^[[:space:]]*Hidden=false[[:space:]]*$' "$desktop_file"
}

file_has_fcitx5_environment() {
    local profile_file="$1"
    [ -f "$profile_file" ] || return 1

    grep -Eq '^[[:space:]]*(export[[:space:]]+)?GTK_IM_MODULE=fcitx[[:space:]]*$' "$profile_file" &&
        grep -Eq '^[[:space:]]*(export[[:space:]]+)?QT_IM_MODULE=fcitx[[:space:]]*$' "$profile_file" &&
        grep -Eq '^[[:space:]]*(export[[:space:]]+)?XMODIFIERS=@im=fcitx[[:space:]]*$' "$profile_file"
}

ensure_fcitx_profile() {
    local profile_file="$1"
    local begin_marker="# BEGIN homelab Fcitx5 environment"
    local end_marker="# END homelab Fcitx5 environment"
    local temp_file

    if file_has_fcitx5_environment "$profile_file"; then
        return 0
    fi

    mkdir -p "$(dirname "$profile_file")"
    touch "$profile_file"
    temp_file="$(mktemp "${profile_file}.tmp.XXXXXX")"

    awk -v begin="$begin_marker" -v end="$end_marker" '
        $0 == begin { managed=1; next }
        managed && $0 == end { managed=0; next }
        !managed { print }
    ' "$profile_file" > "$temp_file"

    if [ -s "$temp_file" ] && [ "$(tail -c 1 "$temp_file" | wc -l)" -eq 0 ]; then
        printf '\n' >> "$temp_file"
    fi

    cat >> "$temp_file" <<EOF

$begin_marker
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
$end_marker
EOF

    chmod --reference="$profile_file" "$temp_file"
    mv "$temp_file" "$profile_file"
}

converge_xrdp_sessions() {
    local sesman_file="$1"
    local temp_file

    [ -f "$sesman_file" ] || {
        echo "sesman configuration not found: $sesman_file" >&2
        return 1
    }

    temp_file="$(mktemp "${sesman_file}.tmp.XXXXXX")"
    awk '
        BEGIN {
            order[1]="X11DisplayOffset"
            order[2]="MaxSessions"
            order[3]="KillDisconnected"
            order[4]="DisconnectedTimeLimit"
            order[5]="IdleTimeLimit"
            order[6]="Policy"
            desired["X11DisplayOffset"]="10"
            desired["MaxSessions"]="50"
            desired["KillDisconnected"]="false"
            desired["DisconnectedTimeLimit"]="0"
            desired["IdleTimeLimit"]="0"
            desired["Policy"]="Default"
        }
        function emit_missing(    i, key) {
            for (i=1; i<=6; i++) {
                key=order[i]
                if (!seen[key]) print key "=" desired[key]
            }
        }
        /^\[Sessions\][[:space:]]*$/ {
            if (in_sessions) emit_missing()
            in_sessions=1
            found_sessions=1
            print
            next
        }
        /^\[/ {
            if (in_sessions) {
                emit_missing()
                in_sessions=0
            }
            print
            next
        }
        in_sessions {
            candidate=$0
            sub(/^[[:space:]]*[;#]?[[:space:]]*/, "", candidate)
            split(candidate, parts, /[[:space:]]*=/)
            key=parts[1]
            if (key in desired) {
                if (!seen[key]) {
                    print key "=" desired[key]
                    seen[key]=1
                }
                next
            }
        }
        { print }
        END {
            if (in_sessions) emit_missing()
            if (!found_sessions) {
                print ""
                print "[Sessions]"
                emit_missing()
            }
        }
    ' "$sesman_file" > "$temp_file"

    chmod --reference="$sesman_file" "$temp_file"
    mv "$temp_file" "$sesman_file"
}

migrate_known_legacy_file() {
    local source_file="$1"
    local known_content="$2"
    local backup_dir="$3"
    local backup_file

    [ -f "$source_file" ] || return 1
    [ "$(cat "$source_file")" = "$known_content" ] || return 1

    mkdir -p "$backup_dir"
    backup_file="$backup_dir/$(basename "$source_file")"
    if [ -e "$backup_file" ]; then
        echo "backup target already exists: $backup_file" >&2
        return 2
    fi
    mv "$source_file" "$backup_file"
}
