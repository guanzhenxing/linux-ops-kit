#!/bin/bash
set -euo pipefail
# ============================================================
# linux-ops-kit — Day 2 操作：安全审计与状态检查
# ============================================================
# 两个子命令：
#   audit  — 完整安全审计（只读，六项检查：SSH/防火墙/fail2ban/自动更新/sudo用户/登录记录）
#   status — 快速安全状态摘要（五行输出，一目了然）
#
# 设计意图：init 是一次性的，但安全是需要持续关注的。
# Day 2 的 security status 让非专业用户也能随时确认"服务器还安全吗"。
# ============================================================

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/os-detect.sh"
source "${SCRIPT_DIR}/lib/init-helper.sh"


# ==================== 安全审计 ====================

do_security_audit_full() {
    print_title "安全审计报告"
    echo -e "审计时间: $(date '+%Y-%m-%d %H:%M:%S')\n"

    # 1. SSH 配置检查
    echo -e "${BOLD}1. SSH 配置${NC}"
    if [ -f /etc/ssh/sshd_config ]; then
        local checks=(
            "PermitRootLogin:no"
            "PasswordAuthentication:no"
        )
        for check in "${checks[@]}"; do
            local key="${check%%:*}"
            local expected="${check##*:}"
            local val
            val=$(sshd -T 2>/dev/null | grep "^${key} " | awk '{print $2}')
            if [ "$val" = "$expected" ]; then
                echo -e "  ${GREEN}✓${NC} $key = $val"
            else
                echo -e "  ${YELLOW}⚠${NC} $key = ${val:-未设置} (建议: $expected)"
            fi
        done
        echo -e "  ${GREEN}✓${NC} SSH 端口: $(get_ssh_port)"
    else
        echo -e "  ${RED}✗${NC} sshd_config 不存在"
    fi

    # 2. 防火墙状态
    echo -e "\n${BOLD}2. 防火墙${NC}"
    if command_exists "ufw"; then
        local ufw_status
        ufw_status=$(ufw status 2>/dev/null | head -1)
        echo -e "  ${GREEN}✓${NC} UFW: $ufw_status"
        ufw status 2>/dev/null | grep -E "^[0-9]" | while read -r rule; do
            echo "        $rule"
        done
    elif command_exists "firewall-cmd"; then
        if systemctl is-active firewalld &>/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} firewalld: 运行中"
            firewall-cmd --list-services 2>/dev/null | tr ' ' '\n' | while read -r svc; do
                [ -n "$svc" ] && echo "        服务: $svc"
            done
        else
            echo -e "  ${YELLOW}⚠${NC} firewalld: 未运行"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} 未检测到防火墙"
    fi

    # 3. fail2ban
    echo -e "\n${BOLD}3. 入侵防护 (fail2ban)${NC}"
    if command_exists "fail2ban-client"; then
        if fail2ban-client status 2>/dev/null | grep -q "Jail list"; then
            local jails
            jails=$(fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*Jail list://' | tr -d ' ,')
            if [ -n "$jails" ]; then
                echo -e "  ${GREEN}✓${NC} fail2ban 运行中"
                for jail in $jails; do
                    local banned
                    banned=$(fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
                    echo "        $jail: 封禁 $banned 个 IP"
                done
            else
                echo -e "  ${YELLOW}⚠${NC} fail2ban 运行中但无活跃 jail"
            fi
        else
            echo -e "  ${RED}✗${NC} fail2ban 未运行"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} fail2ban 未安装"
    fi

    # 4. 自动更新
    echo -e "\n${BOLD}4. 自动安全更新${NC}"
    case "$OS_FAMILY" in
        debian)
            if dpkg -l unattended-upgrades 2>/dev/null | grep -q "^ii"; then
                echo -e "  ${GREEN}✓${NC} unattended-upgrades 已安装"
            else
                echo -e "  ${YELLOW}⚠${NC} unattended-upgrades 未安装"
            fi
            ;;
        rhel)
            if systemctl is-active dnf-automatic.timer &>/dev/null 2>&1; then
                echo -e "  ${GREEN}✓${NC} dnf-automatic 已启用"
            elif systemctl is-active yum-cron &>/dev/null 2>&1; then
                echo -e "  ${GREEN}✓${NC} yum-cron 已启用"
            else
                echo -e "  ${YELLOW}⚠${NC} 自动更新未启用"
            fi
            ;;
    esac

    # 5. sudo 用户审计
    echo -e "\n${BOLD}5. Sudo 用户${NC}"
    local sudo_group
    sudo_group=$(get_sudo_group)
    local sudo_users
    sudo_users=$(getent group "$sudo_group" 2>/dev/null | cut -d: -f4 | tr ',' '\n' | grep -v "^$")
    if [ -n "$sudo_users" ]; then
        echo "$sudo_users" | while read -r u; do
            echo -e "  ${GREEN}✓${NC} $u"
        done
    else
        echo -e "  ${YELLOW}⚠${NC} 无 ${sudo_group} 组成员"
    fi

    # 6. 最近登录
    echo -e "\n${BOLD}6. 最近登录${NC}"
    last -n 5 2>/dev/null | head -5 | while read -r line; do
        echo "  $line"
    done

    echo ""
}

# ==================== 快速状态 ====================

do_security_status() {
    print_title "安全状态摘要"

    # SSH 加固
    local ssh_ok=true
    if sshd -T 2>/dev/null | grep -q "permitrootlogin no"; then
        echo -e "SSH 加固:   ${GREEN}✓ 正常${NC}"
    else
        echo -e "SSH 加固:   ${YELLOW}⚠ 未加固${NC}"
        ssh_ok=false
    fi

    # 防火墙
    if command_exists "ufw"; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            local rules
            rules=$(ufw status 2>/dev/null | grep -c "^[0-9]")
            echo -e "防火墙:     ${GREEN}✓ UFW 已启用, ${rules} 条规则${NC}"
        else
            echo -e "防火墙:     ${YELLOW}⚠ UFW 未启用${NC}"
        fi
    elif command_exists "firewall-cmd"; then
        if systemctl is-active firewalld &>/dev/null 2>&1; then
            echo -e "防火墙:     ${GREEN}✓ firewalld 已启用${NC}"
        else
            echo -e "防火墙:     ${YELLOW}⚠ firewalld 未启用${NC}"
        fi
    else
        echo -e "防火墙:     ${YELLOW}⚠ 未检测到${NC}"
    fi

    # fail2ban
    if command_exists "fail2ban-client"; then
        if fail2ban-client status 2>/dev/null | grep -q "Jail list"; then
            local total_banned
            total_banned=$(fail2ban-client status 2>/dev/null | grep "Currently banned" | awk '{sum += $NF} END {print sum+0}')
            echo -e "fail2ban:   ${GREEN}✓ 运行中, 封禁 ${total_banned} 个 IP${NC}"
        else
            echo -e "fail2ban:   ${RED}✗ 未运行${NC}"
        fi
    else
        echo -e "fail2ban:   ${YELLOW}⚠ 未安装${NC}"
    fi

    # 自动更新
    case "$OS_FAMILY" in
        debian)
            if dpkg -l unattended-upgrades 2>/dev/null | grep -q "^ii"; then
                echo -e "自动更新:   ${GREEN}✓ unattended-upgrades 已启用${NC}"
            else
                echo -e "自动更新:   ${YELLOW}⚠ 未启用${NC}"
            fi
            ;;
        rhel)
            if systemctl is-active dnf-automatic.timer &>/dev/null 2>&1 || \
               systemctl is-active yum-cron &>/dev/null 2>&1; then
                echo -e "自动更新:   ${GREEN}✓ 已启用${NC}"
            else
                echo -e "自动更新:   ${YELLOW}⚠ 未启用${NC}"
            fi
            ;;
    esac
}

# ==================== 子命令帮助 ====================

show_security_help() {
    cat << 'HELP'
用法: ./ops.sh security <子命令>

子命令:
  audit      完整安全审计（只读，不修改）
  status     快速安全状态摘要
  help       显示此帮助

无子命令运行进入交互式菜单。

示例:
  ./ops.sh security audit
  ./ops.sh security status
HELP
}

# ==================== 交互式菜单 ====================

security_interactive_menu() {
    while true; do
        clear
        print_title "=== 安全审计与状态检查 ==="
        echo ""
        echo "1. 完整安全审计"
        echo "2. 快速安全状态"
        echo "b. 返回"
        echo ""
        read -r -p "请选择 [1-2/b]: " choice

        case $choice in
            1) do_security_audit_full ;;
            2) do_security_status ;;
            b|B) return 0 ;;
            *) print_error "无效选择"; sleep 1 ;;
        esac
    done
}

# ==================== 主入口 ====================

main_security() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        audit)
            do_security_audit_full
            ;;
        status)
            do_security_status
            ;;
        "")
            security_interactive_menu
            ;;
        *)
            show_security_help
            exit 1
            ;;
    esac
}

main_security "$@"
