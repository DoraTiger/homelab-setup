#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$TEST_DIR/../.." && pwd)"
HELPER="$SETUP_DIR/lib/xrdp-config.sh"

if [ ! -f "$HELPER" ]; then
    echo "FAIL: XRDP configuration helper is missing: $HELPER" >&2
    exit 1
fi

source "$HELPER"

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# Distribution comments and harmless formatting do not make a working
# startwm file stale.
existing_startwm="$fixture_root/existing-startwm.sh"
cat > "$existing_startwm" <<'EOF'
#!/bin/sh
# Keep the distribution documentation.
if test -r /etc/profile; then . /etc/profile; fi
if test -r ~/.profile; then . ~/.profile; fi
unset DBUS_SESSION_BUS_ADDRESS
unset SESSION_MANAGER
exec dbus-run-session -- /usr/local/bin/xrdp-xfce-session
# exec /bin/sh /etc/X11/Xsession
EOF
xrdp_startwm_is_usable "$existing_startwm" || fail "working startwm was treated as stale"

# A wrong Sessions value must be corrected without rewriting unrelated sections.
sesman_file="$fixture_root/sesman.ini"
cat > "$sesman_file" <<'EOF'
[Globals]
ListenAddress=127.0.0.1

[Sessions]
X11DisplayOffset=9
MaxSessions=2
KillDisconnected=true
DisconnectedTimeLimit=60
IdleTimeLimit=120
Policy=Separate
CustomSessionSetting=keep-me

[Security]
AllowRootLogin=false
EOF

converge_xrdp_sessions "$sesman_file"
first_sesman="$(cat "$sesman_file")"

expected_sessions='X11DisplayOffset=10
MaxSessions=50
KillDisconnected=false
DisconnectedTimeLimit=0
IdleTimeLimit=0
Policy=Default'
actual_sessions="$(awk '
    /^\[Sessions\]$/ { in_sessions=1; next }
    /^\[/ { in_sessions=0 }
    in_sessions && /^(X11DisplayOffset|MaxSessions|KillDisconnected|DisconnectedTimeLimit|IdleTimeLimit|Policy)=/ { print }
' "$sesman_file")"
[ "$actual_sessions" = "$expected_sessions" ] || fail "XRDP session policy was not converged"
grep -q '^CustomSessionSetting=keep-me$' "$sesman_file" || fail "custom Sessions setting was lost"
grep -q '^ListenAddress=127.0.0.1$' "$sesman_file" || fail "Globals section was changed"
grep -q '^AllowRootLogin=false$' "$sesman_file" || fail "Security section was changed"

converge_xrdp_sessions "$sesman_file"
[ "$(cat "$sesman_file")" = "$first_sesman" ] || fail "repeated sesman convergence was not idempotent"

# A working, unmarked Fcitx profile must remain byte-for-byte unchanged.
profile_file="$fixture_root/profile"
cat > "$profile_file" <<'EOF'
# user profile
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
EOF
profile_before="$(cat "$profile_file")"
ensure_fcitx_profile "$profile_file"
[ "$(cat "$profile_file")" = "$profile_before" ] || fail "working Fcitx profile was rewritten"

# A missing Fcitx environment is appended once and remains stable.
plain_profile="$fixture_root/plain-profile"
printf '%s\n' '# preserve me' > "$plain_profile"
ensure_fcitx_profile "$plain_profile"
first_profile="$(cat "$plain_profile")"
ensure_fcitx_profile "$plain_profile"
[ "$(cat "$plain_profile")" = "$first_profile" ] || fail "Fcitx profile block was duplicated"
grep -q '^# preserve me$' "$plain_profile" || fail "existing profile content was lost"

# The wrapper must create a unique keyring directory per launch and preserve older ones.
bin_dir="$fixture_root/bin"
runtime_dir="$fixture_root/runtime"
mkdir -p "$bin_dir" "$runtime_dir"
cat > "$bin_dir/gnome-keyring-daemon" <<'EOF'
#!/bin/sh
printf '%s\n' "$GNOME_KEYRING_CONTROL" > "$XRDP_TEST_KEYRING_CAPTURE"
EOF
cat > "$bin_dir/startxfce4" <<'EOF'
#!/bin/sh
printf '%s|%s\n' "${DBUS_SESSION_BUS_ADDRESS:-}" "$GNOME_KEYRING_CONTROL"
EOF
chmod +x "$bin_dir/gnome-keyring-daemon" "$bin_dir/startxfce4"

wrapper="$fixture_root/xrdp-xfce-session"
render_xrdp_xfce_session > "$wrapper"
chmod +x "$wrapper"

capture_one="$fixture_root/keyring-one"
capture_two="$fixture_root/keyring-two"
output_one="$(PATH="$bin_dir:$PATH" DISPLAY=:10.0 XDG_RUNTIME_DIR="$runtime_dir" XRDP_TEST_KEYRING_CAPTURE="$capture_one" "$wrapper")"
first_keyring="$(cat "$capture_one")"
touch "$first_keyring/preserve-active-session"
output_two="$(PATH="$bin_dir:$PATH" DISPLAY=:10.0 XDG_RUNTIME_DIR="$runtime_dir" XRDP_TEST_KEYRING_CAPTURE="$capture_two" "$wrapper")"
second_keyring="$(cat "$capture_two")"

[ -d "$first_keyring" ] || fail "first keyring directory was removed by a later launch"
[ -f "$first_keyring/preserve-active-session" ] || fail "existing keyring state was destroyed"
[ "$first_keyring" != "$second_keyring" ] || fail "keyring directory was reused across launches"
case "$output_one$output_two" in
    *"$runtime_dir/keyring-rdp-10.0-"*) ;;
    *) fail "keyring was not isolated below XDG_RUNTIME_DIR" ;;
esac

# startwm must clear inherited desktop state, create a private bus, and load Fcitx variables.
home_dir="$fixture_root/home"
mkdir -p "$home_dir"
cat > "$home_dir/.profile" <<'EOF'
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
EOF
cat > "$bin_dir/dbus-run-session" <<'EOF'
#!/bin/sh
[ "$1" = "--" ] && shift
export DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/test-private-bus
exec "$@"
EOF
cat > "$fixture_root/session-target" <<'EOF'
#!/bin/sh
printf '%s|%s|%s|%s|%s\n' \
    "$DBUS_SESSION_BUS_ADDRESS" "${SESSION_MANAGER:-}" \
    "$GTK_IM_MODULE" "$QT_IM_MODULE" "$XMODIFIERS"
EOF
chmod +x "$bin_dir/dbus-run-session" "$fixture_root/session-target"

startwm="$fixture_root/startwm.sh"
render_xrdp_startwm "$fixture_root/session-target" "$bin_dir/dbus-run-session" > "$startwm"
chmod +x "$startwm"
startwm_output="$(PATH="$bin_dir:$PATH" HOME="$home_dir" DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus SESSION_MANAGER=local "$startwm")"
[ "$startwm_output" = 'unix:path=/tmp/test-private-bus||fcitx|fcitx|@im=fcitx' ] || fail "startwm did not isolate D-Bus and preserve the input environment"

# Only the exact legacy files owned by this setup are migrated; custom files stay put.
legacy_file="$fixture_root/.xsession"
backup_dir="$fixture_root/backups"
printf '%s\n' 'startxfce4' > "$legacy_file"
migrate_known_legacy_file "$legacy_file" 'startxfce4' "$backup_dir"
[ ! -e "$legacy_file" ] || fail "known legacy .xsession was not migrated"
[ -f "$backup_dir/.xsession" ] || fail "known legacy .xsession was not backed up"

custom_file="$fixture_root/custom.xsession"
printf '%s\n' 'exec my-custom-desktop' > "$custom_file"
if migrate_known_legacy_file "$custom_file" 'startxfce4' "$backup_dir/custom"; then
    fail "custom .xsession was treated as managed legacy content"
fi
[ -f "$custom_file" ] || fail "custom .xsession was removed"

echo "PASS: XRDP configuration converges safely and idempotently"
