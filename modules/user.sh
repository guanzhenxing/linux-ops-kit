#!/bin/bash
set -euo pipefail
# ============================================================
# linux-ops-kit — Day 2 操作：用户管理
# ============================================================
# 提供服务器初始化之后的日常用户管理能力：
#   - add:  创建新用户 + 导入 SSH Key（不再需要重跑 init）
#   - list: 审计所有可登录用户
#   - del:  安全删除用户（默认保留 home 目录防误删）
#
# 依赖：lib/common.sh（UX 输出）、lib/os-detect.sh（发行版差异）
#       lib/init-helper.sh（user_exists、get_sudo_group 等）
# ============================================================

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/os-detect.sh"
source "${SCRIPT_DIR}/lib/init-helper.sh"

show_user_help() {
    cat << 'HELP'
用法: ./ops.sh user <子命令> [参数]

子命令:
  add  <name>    添加用户（--ssh-key github:USER / gitlab:USER / 路径）
  list           列出所有可登录用户
  del  <name>    删除用户（--purge 同时删除 home 目录）

示例:
  ./ops.sh user add alice --ssh-key github:alice
  ./ops.sh user add bob --ssh-key "ssh-rsa AAA..."
  ./ops.sh user list
  ./ops.sh user del bob --purge
HELP
}

do_user_add() {
    local username="$1"
    local ssh_key=""

    # 解析 --ssh-key
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --ssh-key)
                ssh_key="$2"; shift 2 ;;
            *)
                shift ;;
        esac
    done

    if [ -z "$username" ]; then
        print_error "用法: ./ops.sh user add <username> [--ssh-key SOURCE]"
        return 1
    fi

    if user_exists "$username"; then
        print_result skip "用户" "$username 已存在"
        return 0
    fi

    # 创建用户
    local sudo_group
    sudo_group=$(get_sudo_group)

    # Debian/Ubuntu 优先用 adduser（Perl 脚本，自动创建 home、复制 skel、设 shell）
    # RHEL 系只有 useradd（底层 C 程序，必须手动指定 -m -s）
    local create_cmd
    case "$OS_FAMILY" in
        debian)
            if command_exists "adduser"; then
                create_cmd="adduser --disabled-password --gecos '' '$username'"
            else
                create_cmd="useradd -m -s /bin/bash '$username'"
            fi
            ;;
        *)
            create_cmd="useradd -m -s /bin/bash '$username'"
            ;;
    esac

    # 删除密码：强制该用户只能通过 SSH Key 登录，禁止密码认证
    run_cmd "创建用户: $username (sudo 权限, 仅 SSH Key 登录)" \
        "$create_cmd && passwd -d '$username' && usermod -aG '$sudo_group' '$username'" || return 1

    print_result ok "用户" "$username 已创建 (sudo 权限)"

    # 导入 SSH Key
    if [ -n "$ssh_key" ]; then
        local ssh_dir="/home/${username}/.ssh"
        local auth_file="${ssh_dir}/authorized_keys"
        mkdir -p "$ssh_dir"

        local key_content=""
        case "$ssh_key" in
            github:*)
                local gh_user="${ssh_key#github:}"
                key_content=$(curl -s --connect-timeout 10 "https://github.com/${gh_user}.keys" 2>/dev/null)
                ;;
            gitlab:*)
                local gl_user="${ssh_key#gitlab:}"
                key_content=$(curl -s --connect-timeout 10 "https://gitlab.com/${gl_user}.keys" 2>/dev/null)
                ;;
            *)
                if [ -f "$ssh_key" ]; then
                    key_content=$(cat "$ssh_key")
                else
                    key_content="$ssh_key"
                fi
                ;;
        esac

        if [ -n "$key_content" ]; then
            echo "$key_content" > "$auth_file"
            chmod 700 "$ssh_dir"
            chmod 600 "$auth_file"
            chown -R "${username}:${username}" "$ssh_dir"
            print_result ok "SSH Key" "已导入 → ~${username}/.ssh/authorized_keys"
        else
            print_warn "未能获取 SSH Key"
        fi
    fi
}

do_user_list() {
    print_title "可登录用户列表"

    echo -e "${BOLD}用户名\t\tUID\tShell\t\t家目录${NC}"
    echo "─────────────────────────────────────────────"

    # 过滤条件：UID >= 1000（普通用户）且 < 65534（排除 nobody/nfsnobody）
    # 排除 nologin/false shell（系统服务账户）
    while IFS=: read -r user _ uid _ _ _ shell home; do
        if [ "$uid" -ge 1000 ] && [ "$uid" -lt 65534 ] && [ "$shell" != "/usr/sbin/nologin" ] && [ "$shell" != "/bin/false" ]; then
            local sudo_status=""
            if groups "$user" 2>/dev/null | grep -qE "(sudo|wheel)"; then
                sudo_status=" (sudo)"
            fi
            printf "%-16s %-8s %-16s %s%s\n" "$user" "$uid" "$shell" "$home" "$sudo_status"
        fi
    done < /etc/passwd
}

do_user_del() {
    local username="$1"
    local purge="no"

    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --purge) purge="yes"; shift ;;
            *) shift ;;
        esac
    done

    if [ -z "$username" ]; then
        print_error "用法: ./ops.sh user del <username> [--purge]"
        return 1
    fi

    if ! user_exists "$username"; then
        print_error "用户 $username 不存在"
        return 1
    fi

    # 安全策略：默认保留 home 目录。用户数据可能还有价值，
    # 只有显式传 --purge 时才彻底删除。这是运维安全的基本操作习惯。
    if [ "$purge" = "yes" ]; then
        if run_cmd "删除用户: $username (含 home 目录)" "userdel -r '$username'"; then
            print_result ok "删除用户" "$username (含 home 目录)"
        fi
    else
        if run_cmd "删除用户: $username (保留 home 目录)" "userdel '$username'"; then
            print_result ok "删除用户" "$username (home 目录已保留)"
        fi
    fi
}

# ==================== 主入口 ====================

main_user() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        add)
            do_user_add "$@"
            ;;
        list)
            do_user_list
            ;;
        del|delete|remove)
            do_user_del "$@"
            ;;
        *)
            show_user_help
            ;;
    esac
}

main_user "$@"
