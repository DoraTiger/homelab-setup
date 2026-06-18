#!/bin/bash
# DESCRIPTION: SSH 密钥生成与 authorized_keys 配置 — 生成本机密钥并合并 keys/ 目录下的公钥

set -e
source "$(dirname "$0")/../common.sh"

SETUP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEYS_DIR="$SETUP_DIR/keys"
SSH_DIR="$HOME/.ssh"

# ========== 辅助函数 ==========

show_key_info() {
    local pub_file="$1"
    local name=$(basename "$pub_file")
    local key_type=$(awk '{print $1}' "$pub_file")
    local comment=$(awk '{print $NF}' "$pub_file")
    local fingerprint=$(ssh-keygen -lf "$pub_file" 2>/dev/null | awk '{print $2}')
    printf "    %-24s %-10s %s\n" "$name" "$key_type" "$comment"
    [ -n "$fingerprint" ] && echo "                       fingerprint: $fingerprint"
}

# ========== 1. 生成本机密钥 ==========

echo ""
log_info "🔑 步骤 1/3: 生成本机 SSH 密钥"

if ls "$SSH_DIR"/id_* &>/dev/null; then
    log_warn "SSH 密钥已存在，跳过生成"
    if [ "$SILENT" != "1" ]; then
        echo ""
        log_info "当前已有密钥:"
        for f in "$SSH_DIR"/id_*; do
            [ -f "$f" ] && [[ ! "$f" == *.pub ]] && show_key_info "${f}.pub" 2>/dev/null
        done
    fi
else
    KEY_TYPE=$(prompt_choice "选择密钥类型:" "ed25519" "ed25519" "rsa-4096" "ecdsa")
    case "$KEY_TYPE" in
        rsa-4096) KEY_TYPE="rsa"; KEY_BITS="-b 4096" ;;
        ecdsa)    KEY_BITS="-b 521" ;;
        *)        KEY_BITS="" ;;
    esac

    COMMENT=$(prompt_input "密钥注释 (comment):" "$(whoami)@$(hostname)")

    PASSPHRASE=""
    if prompt_yesno "是否为密钥设置密码 (passphrase)?" "n"; then
        PASSPHRASE=$(prompt_secret "请输入密码")
        [ $? -ne 0 ] && exit 1
    fi

    mkdir -p "$SSH_DIR"
    ssh-keygen -t "$KEY_TYPE" ${KEY_BITS:-} -C "$COMMENT" -f "$SSH_DIR/id_${KEY_TYPE}" -N "$PASSPHRASE"
    log_success "密钥已生成: $SSH_DIR/id_${KEY_TYPE}"

    echo ""
    log_info "新生成的公钥:"
    show_key_info "$SSH_DIR/id_${KEY_TYPE}.pub"
fi

# ========== 2. 构建 authorized_keys ==========

echo ""
log_info "🔑 步骤 2/3: 配置 authorized_keys"

mkdir -p "$SSH_DIR"
touch "$SSH_DIR/authorized_keys"

# 收集所有公钥
declare -a PUB_KEYS=()

for f in "$SSH_DIR"/id_*; do
    [ -f "$f" ] && [[ ! "$f" == *.pub ]] && [ -f "${f}.pub" ] && PUB_KEYS+=("${f}.pub")
done

if [ -d "$KEYS_DIR" ]; then
    shopt -s nullglob
    for pub in "$KEYS_DIR"/*.pub; do
        PUB_KEYS+=("$pub")
    done
    shopt -u nullglob
fi

if [ ${#PUB_KEYS[@]} -eq 0 ]; then
    log_error "未找到任何公钥"
    exit 1
fi

# 展示公钥列表
if [ "$SILENT" != "1" ]; then
    echo ""
    log_info "待注册公钥列表:"
    rows=()
    for pub in "${PUB_KEYS[@]}"; do
        local name=$(basename "$pub")
        local key_type=$(awk '{print $1}' "$pub")
        local comment=$(awk '{print $NF}' "$pub")
        rows+=("$name|$key_type|$comment")
    done
    prompt_table "文件名|类型|注释" "${rows[@]}"
    echo ""
fi

# 逐个写入
added=0
for pub in "${PUB_KEYS[@]}"; do
    key_line=$(cat "$pub")
    key_name=$(basename "$pub")
    if grep -qF "$key_line" "$SSH_DIR/authorized_keys"; then
        log_warn "$key_name 已存在，跳过"
    else
        echo "$key_line" >> "$SSH_DIR/authorized_keys"
        log_success "$key_name 已追加"
        added=$((added + 1))
    fi
done

[ "$added" -eq 0 ] && log_info "所有公钥已存在，无新增" || log_info "新增 $added 个公钥"

# ========== 3. 设置权限 ==========

echo ""
log_info "🔑 步骤 3/3: 设置权限"

chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR/authorized_keys"

log_success "SSH 环境配置完成"
