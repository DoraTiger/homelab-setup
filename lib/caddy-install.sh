#!/bin/bash

caddy_go_version_supported() {
    local version="${1#go}" major minor
    [[ "$version" =~ ^([0-9]+)\.([0-9]+)(\.|$) ]] || return 1
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge 25 ]; }
}

caddy_binary_has_alidns() {
    local binary="$1"
    [ -x "$binary" ] || return 1
    "$binary" list-modules 2>/dev/null | grep -qx 'dns.providers.alidns'
}

archive_caddy_binary() {
    local source_binary="$1" destination="$2"

    caddy_binary_has_alidns "$source_binary" || return 1
    mkdir -p "$(dirname "$destination")"
    install -m 755 "$source_binary" "$destination.part"
    mv -f "$destination.part" "$destination"
}

render_caddy_next_steps() {
    cat <<'EOF'

Caddy 已包含 dns.providers.alidns。需要 DNS-01 HTTPS 时，可按需执行：

  sudo install -m 640 -o root -g caddy /dev/null /etc/caddy/alidns.env
  sudoedit /etc/caddy/alidns.env

凭据文件参考内容（请替换占位符，不要提交到 Git）：

  ALIYUN_ACCESS_KEY_ID=<ACCESS_KEY_ID>
  ALIYUN_ACCESS_KEY_SECRET=<ACCESS_KEY_SECRET>

使用 `sudo systemctl edit caddy` 注入凭据，并覆盖发行版启动命令：

  [Service]
  EnvironmentFile=/etc/caddy/alidns.env
  ExecStart=
  ExecStart=/usr/bin/caddy run --config /etc/caddy/Caddyfile

Caddyfile 站点参考模板：

  <YOUR_DOMAIN> {
      tls {
          dns alidns {
              access_key_id {env.ALIYUN_ACCESS_KEY_ID}
              access_key_secret {env.ALIYUN_ACCESS_KEY_SECRET}
          }
      }
      reverse_proxy 127.0.0.1:<PORT>
  }

应用前请执行：

  sudo caddy fmt --overwrite /etc/caddy/Caddyfile
  sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
  sudo systemctl daemon-reload
  sudo systemctl restart caddy
EOF
}
