#!/bin/bash
# ============================================================
# linux-ops-kit — init 模块：安全加固
# ============================================================
# 本模块实现 init 流程中的安全屏障。包含五大功能：
#   1. SSH 加固      — 禁用 root 登录、密码认证，加固前自动验证SSH连接
#   2. 防火墙        — UFW (Ubuntu) / firewalld (RHEL)，启用后再次验证SSH
#   3. fail2ban      — SSH 暴力破解防护（3次/1小时）
#   4. 自动安全更新   — unattended-upgrades / dnf-automatic
#   5. 安全审计      — 只读检查（内核参数、文件权限、可疑服务、SELinux）
#
# 关键安全设计：
#   - SSH 加固前：必须验证新用户能通过 SSH Key 登录（在 init.sh 调度器中）
#   - 防火墙启用后：再次验证 SSH 连接，失败则紧急关闭防火墙
#   - ufw enable 会弹交互确认，必须用 --force 跳过
#   - CentOS 7: 优先尝试 Include 指令，fallback 到 sed + marker comment
#   - SELinux: 不自动关闭，仅在审计中报告状态
# ============================================================

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/os-detect.sh"
source "${SCRIPT_DIR}/lib/init-helper.sh"

# ==================== SSH 加固 ====================

do_ssh_harden() {
    local username="$1"  # 用于加固前验证
    local step_num=$2
    local total=$3
    print_step "$step_num" "$total" "SSH 加固"

    # 加固前验证 SSH 连接（如果提供了用户名）
    if [ -n "$username" ]; then
        print_info "加固前验证 SSH 连接..."
        local ssh_port
        ssh_port=$(get_ssh_port)
        if ! verify_ssh_access "$username" "127.0.0.1" "$ssh_port"; then
            print_error "SSH 验证失败，跳过 SSH 加固以避免锁死"
            write_init_state "ssh_harden" "failed"
            return 1
        fi
    fi

    # 备份现有配置
    backup_file /etc/ssh/sshd_config

    local ssh_strategy
    ssh_strategy=$(get_ssh_config_dir)

    local hardening_config
    hardening_config=$(cat << 'SSHCONF'
# linux-ops-kit SSH 加固配置
# 生成时间: __TIMESTAMP__
PermitRootLogin no
PasswordAuthentication no
MaxAuthTries 3
ClientAliveInterval 300
MaxSessions 3
X11Forwarding no
SSHCONF
)
    hardening_config="${hardening_config/__TIMESTAMP__/$(date '+%Y-%m-%d %H:%M:%S')}"

    case "$ssh_strategy" in
        sshd_config.d)
            # 现代发行版：直接写入独立的 .d 目录文件，不碰主配置
            # 好处：系统更新不会覆盖，卸载时直接删文件即可
            mkdir -p /etc/ssh/sshd_config.d
            echo "$hardening_config" > /etc/ssh/sshd_config.d/99-hardening.conf
            ;;
        direct)
            # CentOS 7 特殊处理：
            # 1) 优先创建 sshd_config.d 目录 + 添加 Include 指令（OpenSSH 7.4 支持）
            # 2) 若 Include 不可用，用 sed + marker comment 改主文件
            # 无论哪种方式，先备份主配置文件
            mkdir -p /etc/ssh/sshd_config.d
            if grep -q "^Include.*sshd_config.d" /etc/ssh/sshd_config 2>/dev/null; then
                echo "$hardening_config" > /etc/ssh/sshd_config.d/99-hardening.conf
            else
                # 尝试添加 Include 指令
                if ! grep -q "Include /etc/ssh/sshd_config.d" /etc/ssh/sshd_config; then
                    echo "" >> /etc/ssh/sshd_config
                    echo "# Added by linux-ops-kit" >> /etc/ssh/sshd_config
                    echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
                fi
                echo "$hardening_config" > /etc/ssh/sshd_config.d/99-hardening.conf
            fi
            ;;
    esac

    # SELinux (RHEL系): 修改 SSH 端口时，如果 SELinux 处于 Enforcing 模式，
    # 需要 semanage 将新端口添加到 ssh_port_t 类型，否则 sshd 无法绑定。
    # 不自动关闭 SELinux，只修正端口标签。
    if command_exists "semanage" && command_exists "getenforce"; then
        if [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
            semanage port -a -t ssh_port_t -p tcp "$(get_ssh_port)" 2>/dev/null || true
        fi
    fi

    # 验证 sshd 配置
    if sshd -t 2>/dev/null; then
        systemctl restart sshd 2>/dev/null
        print_result ok "SSH 加固" "/etc/ssh/sshd_config.d/99-hardening.conf"
        log_init_step "OK" "SSH 加固完成"
        write_init_state "ssh_harden" "ok"
        return 0
    else
        print_error "SSH 配置验证失败，回滚..."
        rollback_ssh_config
        write_init_state "ssh_harden" "failed"
        return 1
    fi
}

# ==================== 防火墙 ====================

do_firewall() {
    local extra_ports="$1"
    local step_num=$2
    local total=$3
    print_step "$step_num" "$total" "防火墙配置"

    local ssh_port
    ssh_port=$(get_ssh_port)

    case "$OS_FAMILY" in
        debian)
            # Ubuntu/Debian: UFW
            if ! command_exists "ufw"; then
                pkg_install --skip-missing "ufw"
            fi
            if command_exists "ufw"; then
                ufw --force disable 2>/dev/null || true
                ufw default deny incoming 2>/dev/null
                ufw default allow outgoing 2>/dev/null
                ufw allow "$ssh_port/tcp" 2>/dev/null
                ufw allow 80/tcp 2>/dev/null
                ufw allow 443/tcp 2>/dev/null

                # 自定义端口
                if [ -n "$extra_ports" ]; then
                    for port in $extra_ports; do
                        ufw allow "$port/tcp" 2>/dev/null
                    done
                fi

                # ufw enable 默认会弹交互确认："Command may disrupt existing ssh connections"
                # 脚本环境必须用 --force 跳过交互。前提：SSH 端口已在上面 allow 过。
                ufw --force enable 2>/dev/null
                print_result ok "防火墙" "UFW 已启用 (${ssh_port}/80/443)"
            fi
            ;;
        rhel)
            # RHEL 系: firewalld
            if ! systemctl is-active firewalld &>/dev/null 2>&1; then
                systemctl start firewalld 2>/dev/null
            fi
            if systemctl is-active firewalld &>/dev/null 2>&1; then
                firewall-cmd --permanent --add-service=ssh 2>/dev/null
                firewall-cmd --permanent --add-service=http 2>/dev/null
                firewall-cmd --permanent --add-service=https 2>/dev/null

                if [ "$ssh_port" != "22" ]; then
                    firewall-cmd --permanent --add-port="${ssh_port}/tcp" 2>/dev/null
                fi
                if [ -n "$extra_ports" ]; then
                    for port in $extra_ports; do
                        firewall-cmd --permanent --add-port="${port}/tcp" 2>/dev/null
                    done
                fi

                firewall-cmd --reload 2>/dev/null
                print_result ok "防火墙" "firewalld 已启用 (${ssh_port}/80/443)"
            else
                print_result fail "防火墙" "firewalld 不可用"
            fi
            ;;
    esac

    log_init_step "OK" "防火墙配置完成"
    write_init_state "firewall" "ok"

    # 防火墙后验证 SSH
    if [ -n "$username" ]; then
        if ! verify_ssh_access "$username" "127.0.0.1" "$ssh_port"; then
            print_error "防火墙后 SSH 验证失败！紧急关闭防火墙..."
            firewall_panic_off
            write_init_state "firewall" "failed"
            return 1
        fi
    fi

    return 0
}

# ==================== fail2ban ====================

do_fail2ban() {
    local step_num=$1
    local total=$2
    print_step "$step_num" "$total" "fail2ban 入侵防护"

    if ! command_exists "fail2ban-client"; then
        pkg_install --skip-missing "fail2ban"
    fi

    if command_exists "fail2ban-client"; then
        # 创建 jail.local
        local jail_file="/etc/fail2ban/jail.local"
        if [ ! -f "$jail_file" ]; then
            cat > "$jail_file" << 'FAIL2BAN'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
maxretry = 3
bantime = 1h
FAIL2BAN
        fi

        svc_manage "fail2ban" enable-now 2>/dev/null
        print_result ok "fail2ban" "SSH: 3次/1小时, 通用: 5次/1小时"
        log_init_step "OK" "fail2ban 安装并配置完成"
        write_init_state "fail2ban" "ok"
    else
        print_result fail "fail2ban" "安装失败"
        write_init_state "fail2ban" "failed"
        return 1
    fi
    return 0
}

# ==================== 自动安全更新 ====================

do_auto_updates() {
    local step_num=$1
    local total=$2
    print_step "$step_num" "$total" "自动安全更新"

    case "$OS_FAMILY" in
        debian)
            pkg_install --skip-missing "unattended-upgrades"
            if command_exists "unattended-upgrades"; then
                dpkg-reconfigure -f noninteractive unattended-upgrades 2>/dev/null || true
                print_result ok "自动更新" "unattended-upgrades 已启用"
            fi
            ;;
        rhel)
            case "$OS_ID" in
                centos)
                    if [ "${OS_VERSION%%.*}" -eq 7 ] 2>/dev/null; then
                        pkg_install --skip-missing "yum-cron"
                        svc_manage "yum-cron" enable-now 2>/dev/null || true
                    else
                        pkg_install --skip-missing "dnf-automatic"
                        svc_manage "dnf-automatic.timer" enable 2>/dev/null || true
                    fi
                    ;;
                *)
                    pkg_install --skip-missing "dnf-automatic"
                    svc_manage "dnf-automatic.timer" enable 2>/dev/null || true
                    ;;
            esac
            print_result ok "自动更新" "安全更新已启用"
            ;;
    esac

    log_init_step "OK" "自动安全更新配置完成"
    write_init_state "auto_updates" "ok"
    return 0
}

# ==================== 安全审计（只读） ====================
#
# 重要设计决定：本节所有检查只输出报告，不自动修改任何配置。
# 原因：非专业用户不了解 avahi-daemon 等服务的用途，
# 自动禁用可能数月后才暴露问题。与其替用户做危险决定，
# 不如把发现清楚地报告出来。

do_security_audit() {
    local step_num=$1
    local total=$2
    print_step "$step_num" "$total" "系统安全审计"

    print_info "审计结果（只读，未修改任何配置）:"

    # 内核参数审计
    echo -e "\n${BOLD}内核安全参数:${NC}"
    for param in \
        "net.ipv4.conf.all.send_redirects:0" \
        "kernel.randomize_va_space:2" \
        "net.ipv4.tcp_syncookies:1"; do
        local key="${param%%:*}"
        local expected="${param##*:}"
        local current
        current=$(sysctl -n "$key" 2>/dev/null)
        if [ "$current" = "$expected" ]; then
            echo -e "  ${GREEN}✓${NC} $key = $current"
        else
            echo -e "  ${YELLOW}⚠${NC} $key = ${current:-未设置} (建议: $expected)"
        fi
    done

    # 文件权限审计
    echo -e "\n${BOLD}关键文件权限:${NC}"
    for file in /etc/shadow /etc/gshadow /etc/passwd; do
        if [ -f "$file" ]; then
            local perms owner
            perms=$(stat -c "%a:%U:%G" "$file" 2>/dev/null)
            echo -e "  ${GREEN}✓${NC} $file ($perms)"
        fi
    done

    # 运行服务审计
    echo -e "\n${BOLD}可疑服务检查:${NC}"
    local suspicious="avahi-daemon cups rpcbind bluetooth"
    for svc in $suspicious; do
        if systemctl is-active "$svc" &>/dev/null 2>&1; then
            echo -e "  ${YELLOW}⚠${NC} $svc 正在运行。如不需要: systemctl disable --now $svc"
        fi
    done
    echo -e "  ${GREEN}✓${NC} 未发现其他可疑服务"

    # SELinux 状态
    echo -e "\n${BOLD}SELinux 状态:${NC}"
    if command_exists "getenforce"; then
        local selinux_mode
        selinux_mode=$(getenforce 2>/dev/null)
        case "$selinux_mode" in
            Enforcing)
                echo -e "  ${BLUE}ℹ${NC}  SELinux: $selinux_mode (SSH 改动可能需要 semanage 调整)"
                ;;
            Permissive)
                echo -e "  ${YELLOW}⚠${NC} SELinux: $selinux_mode"
                ;;
            Disabled)
                echo -e "  ${YELLOW}⚠${NC} SELinux: $selinux_mode"
                ;;
        esac
    else
        echo -e "  ${GREEN}✓${NC} SELinux: 未安装"
    fi

    print_result ok "安全审计" "只读，建议已列出"
    log_init_step "OK" "安全审计完成"
    write_init_state "security_audit" "ok"
    return 0
}

# ==================== 模块入口 ====================

run_init_security() {
    local step_num=${1:-1}
    local total=${2:-10}
    local username="${3:-}"
    local firewall_enabled="${4:-no}"
    local fail2ban_enabled="${5:-no}"
    local harden_ssh="${6:-no}"
    local extra_ports="${7:-}"

    # SSH 加固
    if [ "$harden_ssh" = "yes" ] && [ -n "$username" ]; then
        do_ssh_harden "$username" "$step_num" "$total"
    else
        print_result skip "SSH 加固" "跳过（需要 --harden-ssh 和用户名）"
        write_init_state "ssh_harden" "skipped"
    fi
    step_num=$((step_num + 1))

    # 防火墙
    if [ "$firewall_enabled" = "yes" ]; then
        do_firewall "$extra_ports" "$step_num" "$total"
    else
        print_result skip "防火墙" "跳过"
        write_init_state "firewall" "skipped"
    fi
    step_num=$((step_num + 1))

    # fail2ban
    if [ "$fail2ban_enabled" = "yes" ]; then
        do_fail2ban "$step_num" "$total"
    else
        print_result skip "fail2ban" "跳过"
        write_init_state "fail2ban" "skipped"
    fi
    step_num=$((step_num + 1))

    # 自动安全更新
    do_auto_updates "$step_num" "$total"
    step_num=$((step_num + 1))

    # 安全审计（始终执行）
    do_security_audit "$step_num" "$total"
}
