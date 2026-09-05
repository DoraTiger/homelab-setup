#!/bin/bash
# DESCRIPTION: Apache Guacamole + PostgreSQL Compose 部署骨架

set -e

SERVICE_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SERVICE_DIR/../../common.sh"

# Guacamole 是有状态服务。脚本负责补齐部署文件、镜像和初始化 SQL，并通过
# Compose 收敛容器；已有凭据、配置、初始化 SQL 和数据库卷不会被重建。
command -v docker >/dev/null 2>&1 || {
    log_error "未找到 Docker，请先执行: bash init.sh --silent docker"
    exit 1
}
docker compose version >/dev/null 2>&1 || {
    log_error "未找到 Docker Compose 插件，请先执行: bash init.sh --silent docker"
    exit 1
}
docker info >/dev/null 2>&1 || {
    log_error "当前用户无法访问 Docker daemon，请确认服务已启动且用户具有 Docker 权限"
    exit 1
}

DEPLOY_DIR="${GUACAMOLE_DEPLOY_DIR:-$WORKSPACE_ROOT/services/docker/guacamole}"
DEPLOY_DIR="$(homelab_normalize_absolute_path "$DEPLOY_DIR" "$WORKSPACE_ROOT")"
[ "$DEPLOY_DIR" != / ] || { log_error "拒绝使用文件系统根目录作为部署目录"; exit 1; }
mkdir -p "$DEPLOY_DIR"

install_generated_file_if_missing() {
    local target_file="$1" mode="$2" label="$3"
    local temp_file
    if [ -e "$target_file" ]; then
        log_warn "保留已有文件: $target_file"
        return 0
    fi
    temp_file="$(mktemp "$DEPLOY_DIR/.guacamole.XXXXXX")"
    cat > "$temp_file"
    chmod "$mode" "$temp_file"
    mv "$temp_file" "$target_file"
    log_success "已生成 $label: $target_file"
}

install_generated_file_if_missing "$DEPLOY_DIR/compose.yaml" 640 compose.yaml <<'EOF'
name: guacamole

services:
  postgres:
    image: postgres:17
    container_name: guacamole-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: guacamole_db
      POSTGRES_USER: guacamole_user
      POSTGRES_PASSWORD: ${GUACAMOLE_DB_PASSWORD:?set GUACAMOLE_DB_PASSWORD in .env}
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./initdb.sql:/docker-entrypoint-initdb.d/001-guacamole.sql:ro
    networks:
      - guacamole

  guacd:
    image: guacamole/guacd:1.6.0
    container_name: guacd
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "nc -z 127.0.0.1 4822 || exit 1"]
      interval: 5m
      timeout: 5s
    networks:
      - guacamole

  guacamole:
    image: guacamole/guacamole:1.6.0
    container_name: guacamole
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_started
      guacd:
        condition: service_started
    environment:
      GUACD_HOSTNAME: guacd
      POSTGRESQL_HOSTNAME: postgres
      POSTGRESQL_ENABLED: "true"
      POSTGRESQL_DATABASE: guacamole_db
      POSTGRESQL_USERNAME: guacamole_user
      POSTGRESQL_PASSWORD: ${GUACAMOLE_DB_PASSWORD:?set GUACAMOLE_DB_PASSWORD in .env}
    ports:
      - "127.0.0.1:${GUACAMOLE_PORT:-30090}:8080"
    networks:
      - guacamole

volumes:
  postgres-data:
    name: guacamole_postgres-data

networks:
  guacamole:
    name: guacamole_guacamole
EOF

install_generated_file_if_missing "$DEPLOY_DIR/.env.example" 600 .env.example <<'EOF'
# Copy this file to .env and replace the placeholder with a strong random value.
GUACAMOLE_DB_PASSWORD=<GENERATE_A_STRONG_RANDOM_PASSWORD>
GUACAMOLE_PORT=30090
EOF

if [ -e "$DEPLOY_DIR/.env" ]; then
    log_warn "保留已有运行凭据: $DEPLOY_DIR/.env"
else
    command -v openssl >/dev/null 2>&1 || {
        log_error "未找到 openssl，无法安全生成数据库密码"
        exit 1
    }
    password="$(openssl rand -hex 32)"
    [ "${#password}" -eq 64 ] || { log_error "数据库密码生成失败"; exit 1; }
    temp_env="$(mktemp "$DEPLOY_DIR/.env.XXXXXX")"
    {
        printf 'GUACAMOLE_DB_PASSWORD=%s\n' "$password"
        printf 'GUACAMOLE_PORT=30090\n'
    } > "$temp_env"
    chmod 600 "$temp_env"
    mv "$temp_env" "$DEPLOY_DIR/.env"
    log_success "已生成运行凭据: $DEPLOY_DIR/.env"
fi

images=(
    postgres:17
    guacamole/guacd:1.6.0
    guacamole/guacamole:1.6.0
)

if upgrade_requested; then
    log_info "升级模式：检查并拉取 Compose 镜像"
    (cd "$DEPLOY_DIR" && docker compose pull)
else
    for image in "${images[@]}"; do
        if docker image inspect "$image" >/dev/null 2>&1; then
            log_info "复用本地镜像: $image"
        else
            log_info "拉取缺失镜像: $image"
            docker pull "$image"
        fi
    done
fi

if [ -e "$DEPLOY_DIR/initdb.sql" ]; then
    log_warn "保留已有文件: $DEPLOY_DIR/initdb.sql"
else
    temp_initdb="$(mktemp "$DEPLOY_DIR/.initdb.sql.XXXXXX")"
    if ! docker run --rm guacamole/guacamole:1.6.0 \
        /opt/guacamole/bin/initdb.sh --postgresql > "$temp_initdb"; then
        rm -f "$temp_initdb"
        log_error "Guacamole 数据库初始化 SQL 生成失败"
        exit 1
    fi
    if [ ! -s "$temp_initdb" ] || ! grep -q 'CREATE' "$temp_initdb"; then
        rm -f "$temp_initdb"
        log_error "Guacamole 数据库初始化 SQL 内容无效"
        exit 1
    fi
    chmod 600 "$temp_initdb"
    mv "$temp_initdb" "$DEPLOY_DIR/initdb.sql"
    log_success "已生成数据库初始化 SQL: $DEPLOY_DIR/initdb.sql"
fi

log_info "校验 Compose 配置"
(cd "$DEPLOY_DIR" && docker compose config >/dev/null)

log_info "收敛 Guacamole 容器"
(cd "$DEPLOY_DIR" && docker compose up -d --remove-orphans)

log_info "当前容器状态"
(cd "$DEPLOY_DIR" && docker compose ps)

cat <<EOF

Guacamole 已完成部署收敛，配置目录:
  $DEPLOY_DIR

常用管理命令：

  cd "$DEPLOY_DIR"
  docker compose ps
  docker compose logs -f
  docker compose restart

Caddy 反向代理参考（域名和 TLS/DNS 配置请自行补充）：

  <YOUR_DOMAIN> {
      reverse_proxy /guacamole/* 127.0.0.1:30090
  }

默认访问路径为 <YOUR_DOMAIN>/guacamole/。
配置 Guacamole 的 RDP 连接时，不要将 RDP 目标填写为 127.0.0.1；
容器中的 127.0.0.1 是容器自身，应填写 Docker 主机可达的局域网地址或网关地址。
首次登录后请立即创建新的管理员账户并删除默认 guacadmin 账户。
EOF
