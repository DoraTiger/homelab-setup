#!/bin/bash

prepare_code_server_curl_config() {
    local curl_home="$1"

    mkdir -p "$curl_home"
    cat > "$curl_home/.curlrc" <<'EOF'
connect-timeout = 10
max-time = 300
retry = 3
retry-delay = 2
retry-all-errors
EOF
    chmod 600 "$curl_home/.curlrc"
}

# code-server may create its default configuration even for --version. Isolate
# that probe in a disposable XDG directory so installation checks never touch
# the user's real configuration.
code_server_version() {
    local binary="$1" probe_home output status

    probe_home="$(mktemp -d)"
    if output="$(XDG_CONFIG_HOME="$probe_home" "$binary" --version 2>/dev/null)"; then
        status=0
    else
        status=$?
    fi
    rm -rf "$probe_home"
    [ "$status" -eq 0 ] || return "$status"
    printf '%s\n' "${output##*$'\n'}"
}

render_code_server_next_steps() {
    local service_user="$1"

    cat <<EOF

code-server 已安装。本模块不会修改配置或启动服务，可按需配置：

  \$EDITOR ~/.config/code-server/config.yaml

配置参考：

  bind-addr: 127.0.0.1:<PORT>
  auth: password
  cert: false
  locale: zh-cn

启动并设置开机启动：

  sudo systemctl enable --now code-server@$service_user

如需公网可信 HTTPS，可先安装含 AliDNS Provider 的 Caddy：

  cd <SETUP_REPOSITORY>
  bash init.sh --silent caddy

Caddyfile 反向代理参考：

  <YOUR_DOMAIN> {
      reverse_proxy 127.0.0.1:<PORT>
  }
EOF
}
