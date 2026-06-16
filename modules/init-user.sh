#!/bin/bash
# linux-ops-kit — init 模块：用户管理
# 创建 sudo 用户、SSH Key 导入、root 锁定

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/os-detect.sh"
source "${SCRIPT_DIR}/lib/init-helper.sh"

# ==================== 创建用户 ====================

do_create_user() {
    local username="$1"
    local step_num=$2
    local total=$3
    print_step "$step_num" "$total" "创建用户"

    if [ -z "$username" ]; then
        print_result fail "创建用户" "未指定用户名"
        write_init_state "user_create" "failed"
        return 1
    fi

    # 幂等检测
    if user_exists "$username"; then
        print_result skip "创建用户" "$username 已存在"
        write_init_state "user_create" "skipped"
        return 0
    fi

    # 创建用户
    local sudo_group
    sudo_group=$(get_sudo_group)

    local create_cmd
    case "$OS_FAMILY" in
        debian)
            # Debian/Ubuntu: 优先 adduser
            if command_exists "adduser"; then
                create_cmd="adduser --disabled-password --gecos '' '$username'"
            else
                create_cmd="useradd -m -s /bin/bash '$username'"
            fi
            ;;
        rhel)
            create_cmd="useradd -m -s /bin/bash '$username'"
            ;;
        *)
            create_cmd="useradd -m -s /bin/bash '$username'"
            ;;
    esac

    # 创建用户 + 清除密码 + 加入 sudo 组
    run_cmd "创建用户: $username (sudo 权限, 仅 SSH Key 登录)" \
        "$create_cmd && passwd -d '$username' && usermod -aG '$sudo_group' '$username'" || return 1

    # 验证 sudo 组是否在 sudoers 中启用
    local sudoers_fragment="/etc/sudoers.d/99-ops-init"
    local rule=""
    if [ "$sudo_group" = "sudo" ]; then
        if ! grep -qE "^%sudo\s+ALL" /etc/sudoers 2>/dev/null; then
            rule="%sudo ALL=(ALL:ALL) NOPASSWD:ALL"
        fi
    elif [ "$sudo_group" = "wheel" ]; then
        if grep -qE "^#\s*%wheel" /etc/sudoers 2>/dev/null; then
            rule="%wheel ALL=(ALL:ALL) NOPASSWD:ALL"
        fi
    fi

    # 幂等写入：仅当片段文件尚未包含该规则时才追加（避免重复 init 累积重复行）
    if [ -n "$rule" ]; then
        if [ ! -f "$sudoers_fragment" ] || ! grep -qxF "$rule" "$sudoers_fragment" 2>/dev/null; then
            echo "$rule" >> "$sudoers_fragment"
        fi
    fi
    chmod 440 "$sudoers_fragment" 2>/dev/null || true

    print_result ok "创建用户" "$username (sudo 权限)"
    log_init_step "OK" "用户 $username 创建完成"
    write_init_state "user_create" "ok"

    # 返回用户名供后续步骤使用
    echo "$username"
    return 0
}

# ==================== SSH Key 导入 ====================

do_import_ssh_key() {
    local key_source="$1"
    local username="$2"
    local step_num=$3
    local total=$4
    print_step "$step_num" "$total" "SSH Key 导入"

    if [ -z "$key_source" ]; then
        print_result skip "SSH Key" "未指定来源"
        write_init_state "ssh_key_import" "skipped"
        return 0
    fi

    if [ -z "$username" ]; then
        print_result fail "SSH Key" "未指定用户"
        write_init_state "ssh_key_import" "failed"
        return 1
    fi

    local ssh_dir="/home/${username}/.ssh"
    local auth_file="${ssh_dir}/authorized_keys"
    mkdir -p "$ssh_dir"

    local key_content=""

    # 判断 Key 来源
    case "$key_source" in
        github:*)
            local gh_user="${key_source#github:}"
            print_info "从 GitHub 拉取 SSH Key: $gh_user"
            key_content=$(curl -s --connect-timeout 10 "https://github.com/${gh_user}.keys" 2>/dev/null)

            if [ $? -ne 0 ] || [ -z "$key_content" ]; then
                if curl -s --connect-timeout 5 "https://github.com" &>/dev/null; then
                    print_error "未找到 ${gh_user} 的 SSH Key，请确认用户名是否正确"
                else
                    print_error "无法访问 GitHub，请检查网络或使用 --mirror 切换镜像源"
                fi
                write_init_state "ssh_key_import" "failed"
                return 1
            fi
            ;;
        gitlab:*)
            local gl_user="${key_source#gitlab:}"
            print_info "从 GitLab 拉取 SSH Key: $gl_user"
            key_content=$(curl -s --connect-timeout 10 "https://gitlab.com/${gl_user}.keys" 2>/dev/null)

            if [ $? -ne 0 ] || [ -z "$key_content" ]; then
                print_error "无法访问 GitLab 或未找到 ${gl_user} 的 SSH Key"
                write_init_state "ssh_key_import" "failed"
                return 1
            fi
            ;;
        /*)
            # 文件路径
            if [ -f "$key_source" ]; then
                key_content=$(cat "$key_source")
            else
                print_error "SSH Key 文件不存在: $key_source"
                write_init_state "ssh_key_import" "failed"
                return 1
            fi
            ;;
        ssh-*|ecdsa-*|sk-ssh-*)
            # 直接是公钥内容
            key_content="$key_source"
            ;;
        *)
            # 尝试作为文件路径
            if [ -f "$key_source" ]; then
                key_content=$(cat "$key_source")
            else
                print_error "无法识别的 SSH Key 来源: $key_source"
                write_init_state "ssh_key_import" "failed"
                return 1
            fi
            ;;
    esac

    # 写入 authorized_keys
    echo "$key_content" > "$auth_file"
    chmod 700 "$ssh_dir"
    chmod 600 "$auth_file"
    chown -R "${username}:${username}" "$ssh_dir"

    local key_count
    key_count=$(echo "$key_content" | grep -c "^ssh-\|^ecdsa-\|^sk-ssh-")
    print_result ok "SSH Key" "${key_source} (${key_count} keys) → ~${username}/.ssh/authorized_keys"
    log_init_step "OK" "SSH Key 已导入: $key_source → $username"
    write_init_state "ssh_key_import" "ok"
    return 0
}

# ==================== Root 账户锁定 ====================

do_lock_root() {
    local step_num=$1
    local total=$2
    print_step "$step_num" "$total" "锁定 Root 账户"

    # 检查当前是否有 root SSH 会话（通过检查当前用户）
    if [ "$(whoami)" != "root" ]; then
        print_result skip "锁定 Root" "当前非 root 用户，跳过"
        write_init_state "lock_root" "skipped"
        return 0
    fi

    # 不自动锁定 root，只提示
    print_warn "Root 账户未锁定。如果你想禁用 root SSH 登录，请在 SSH 加固后手动执行:"
    print_info "  passwd -l root"
    print_result ok "锁定 Root" "保留 root 密码（SSH 加固将禁用 root 登录）"
    write_init_state "lock_root" "skipped"
    return 0
}

# ==================== 模块入口 ====================

run_init_user() {
    local step_num=${1:-1}
    local total=${2:-10}
    local username="${3:-}"
    local ssh_key="${4:-}"

    if [ -z "$username" ]; then
        print_warn "未指定用户名，跳过用户管理"
        return 0
    fi

    do_create_user "$username" "$step_num" "$total"
    step_num=$((step_num + 1))
    do_import_ssh_key "$ssh_key" "$username" "$step_num" "$total"
    step_num=$((step_num + 1))
    do_lock_root "$step_num" "$total"
}
