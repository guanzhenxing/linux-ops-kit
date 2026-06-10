#!/bin/bash
set -uo pipefail
# 网络诊断模块 - 端口检查/接口信息/连通性测试/防火墙管理

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# ==================== 端口检查 ====================

check_ports() {
    clear
    print_title "=== 端口检查 ==="

    cat << 'EOF'
1. 查看所有监听端口
2. 查看指定端口占用
3. 查看所有活跃连接
0. 返回

EOF

    read -r -p "请选择 [0-3]: " choice

    case $choice in
        1)
            echo ""
            print_info "所有监听端口:"
            echo ""
            echo -e "${BOLD}协议  本地地址            端口    进程${NC}"
            echo "----------------------------------------------"
            if command_exists ss; then
                ss -tlnp 2>/dev/null | grep LISTEN | awk '{
                    split($4, a, ":");
                    port=a[length(a)];
                    proc="";
                    for(i=6;i<=NF;i++) proc=proc" "$i;
                    printf " %-5s %-20s %-6s %s\n", $1, $4, port, proc
                }'
            elif command_exists netstat; then
                netstat -tlnp 2>/dev/null | grep LISTEN | awk '{
                    printf " %-5s %-20s %-6s %s\n", $1, $4, "", $7
                }'
            else
                print_error "ss 和 netstat 均不可用"
            fi
            echo ""
            pause
            ;;
        2)
            read -r -p "请输入端口号: " port
            if [ -z "$port" ] || ! [[ "$port" =~ ^[0-9]+$ ]]; then
                print_error "无效端口号"
                sleep 1
                return
            fi

            echo ""
            print_info "端口 $port 占用情况:"
            echo ""

            local port_info
            port_info=$(get_port_info "$port")
            if [ -n "$port_info" ]; then
                echo "$port_info"
            else
                print_info "端口 $port 未被占用"
            fi
            echo ""
            pause
            ;;
        3)
            echo ""
            print_info "所有活跃连接 (前 30 条):"
            echo ""
            if command_exists ss; then
                ss -tnp 2>/dev/null | head -31
            elif command_exists netstat; then
                netstat -tnp 2>/dev/null | head -31
            else
                print_error "ss 和 netstat 均不可用"
            fi
            echo ""
            pause
            ;;
        0) return ;;
        *)
            print_error "无效选择"
            sleep 1
            ;;
    esac
}

# ==================== 网络接口信息 ====================

show_interface() {
    clear
    print_title "=== 网络接口信息 ==="

    cat << 'EOF'
1. 查看网络接口和 IP 地址
2. 查看路由表
3. DNS 查询
4. 查看公网 IP
0. 返回

EOF

    read -r -p "请选择 [0-4]: " choice

    case $choice in
        1)
            echo ""
            print_info "网络接口信息:"
            echo ""
            if command_exists ip; then
                ip -brief addr show 2>/dev/null || ip addr show
            elif command_exists ifconfig; then
                ifconfig
            else
                print_error "ip 和 ifconfig 均不可用"
            fi
            echo ""
            pause
            ;;
        2)
            echo ""
            print_info "路由表:"
            echo ""
            if command_exists ip; then
                ip route show
            elif command_exists route; then
                route -n
            else
                print_error "ip 和 route 均不可用"
            fi
            echo ""
            pause
            ;;
        3)
            read -r -p "输入要查询的域名: " domain
            if [ -z "$domain" ]; then
                return
            fi
            echo ""
            if command_exists dig; then
                dig "$domain" +short
            elif command_exists nslookup; then
                nslookup "$domain"
            elif command_exists host; then
                host "$domain"
            else
                print_error "dig/nslookup/host 均不可用"
            fi
            echo ""
            pause
            ;;
        4)
            echo ""
            print_info "正在获取公网 IP..."
            local public_ip=""
            if command_exists curl; then
                public_ip=$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null)
            fi
            if [ -z "$public_ip" ] && command_exists wget; then
                public_ip=$(wget -qO- --timeout=3 ifconfig.me 2>/dev/null)
            fi
            if [ -n "$public_ip" ]; then
                echo -e "公网 IP: ${GREEN}${BOLD}$public_ip${NC}"
            else
                print_error "无法获取公网 IP（可能无网络连接）"
            fi
            echo ""
            pause
            ;;
        0) return ;;
        *)
            print_error "无效选择"
            sleep 1
            ;;
    esac
}

# ==================== 连通性测试 ====================

test_connectivity() {
    clear
    print_title "=== 连通性测试 ==="

    cat << 'EOF'
1. Ping 测试
2. Traceroute 路由追踪
3. 端口连通性测试
0. 返回

EOF

    read -r -p "请选择 [0-3]: " choice

    case $choice in
        1)
            read -r -p "输入目标地址: " target
            if [ -z "$target" ]; then
                return
            fi

            echo ""
            print_info "Ping $target (4 次)..."
            echo ""
            ping -c 4 "$target" 2>/dev/null
            if [ $? -ne 0 ]; then
                print_error "Ping 失败：无法连接到 $target"
            fi
            echo ""
            pause
            ;;
        2)
            read -r -p "输入目标地址: " target
            if [ -z "$target" ]; then
                return
            fi

            echo ""
            print_info "路由追踪到 $target..."
            echo ""

            if command_exists traceroute; then
                traceroute -m 20 "$target" 2>/dev/null
            elif command_exists tracepath; then
                tracepath "$target" 2>/dev/null
            else
                print_error "traceroute 和 tracepath 均不可用"
                print_info "安装: apt install traceroute 或 yum install traceroute"
                sleep 1
                return
            fi
            echo ""
            pause
            ;;
        3)
            read -r -p "输入目标地址 (host:port 或 host port): " input
            if [ -z "$input" ]; then
                return
            fi

            local host=""
            local port=""

            if [[ "$input" == *:* ]]; then
                host="${input%%:*}"
                port="${input##*:}"
            else
                host="$input"
                read -r -p "输入端口号: " port
            fi

            if [ -z "$host" ] || [ -z "$port" ]; then
                print_error "地址和端口不能为空"
                sleep 1
                return
            fi

            echo ""
            print_info "测试 $host:$port 连通性..."
            echo ""

            if command_exists nc; then
                nc -zv -w 3 "$host" "$port" 2>&1
            elif command_exists timeout; then
                timeout 3 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
                if [ $? -eq 0 ]; then
                    print_success "$host:$port 连通"
                else
                    print_error "$host:$port 不可达"
                fi
            else
                print_error "nc 不可用，且无法使用 /dev/tcp"
            fi
            echo ""
            pause
            ;;
        0) return ;;
        *)
            print_error "无效选择"
            sleep 1
            ;;
    esac
}

# ==================== 防火墙管理 ====================

# 检测防火墙类型
detect_firewall() {
    if command_exists ufw; then
        echo "ufw"
    elif command_exists firewall-cmd; then
        echo "firewalld"
    elif command_exists iptables; then
        echo "iptables"
    else
        echo "none"
    fi
}

manage_firewall() {
    clear
    print_title "=== 防火墙管理 ==="

    local fw_type=$(detect_firewall)

    if [ "$fw_type" = "none" ]; then
        print_error "未检测到防火墙工具 (ufw/firewalld/iptables)"
        echo ""
        pause
        return
    fi

    echo -e "检测到防火墙类型: ${GREEN}${BOLD}$fw_type${NC}"
    echo ""

    # 显示当前状态（只读，不需要 root）
    show_firewall_status "$fw_type"

    cat << 'EOF'

1. 查看详细规则
2. 开放端口
3. 关闭端口
0. 返回

EOF

    read -r -p "请选择 [0-3]: " choice

    case $choice in
        1) show_firewall_rules "$fw_type" ;;
        2) firewall_open_port "$fw_type" ;;
        3) firewall_close_port "$fw_type" ;;
        0) return ;;
        *)
            print_error "无效选择"
            sleep 1
            ;;
    esac
}

show_firewall_status() {
    local fw_type="$1"

    echo -e "${BOLD}防火墙状态:${NC}"
    echo ""

    case "$fw_type" in
        ufw)
            sudo ufw status 2>/dev/null || ufw status 2>/dev/null
            ;;
        firewalld)
            firewall-cmd --state 2>/dev/null
            echo ""
            firewall-cmd --list-all 2>/dev/null
            ;;
        iptables)
            sudo iptables -L -n --line-numbers 2>/dev/null | head -30
            ;;
    esac
}

show_firewall_rules() {
    local fw_type="$1"

    echo ""
    print_info "详细规则:"
    echo ""

    case "$fw_type" in
        ufw)
            sudo ufw status verbose 2>/dev/null
            ;;
        firewalld)
            firewall-cmd --list-all-zones 2>/dev/null | head -50
            ;;
        iptables)
            sudo iptables -L -n -v 2>/dev/null | head -50
            ;;
    esac

    echo ""
    pause
}

firewall_open_port() {
    local fw_type="$1"

    if ! is_root; then
        print_error "此操作需要 root 权限"
        echo ""
        pause
        return
    fi

    read -r -p "输入要开放的端口号: " port
    if [ -z "$port" ] || ! [[ "$port" =~ ^[0-9]+$ ]]; then
        print_error "无效端口号"
        sleep 1
        return
    fi

    read -r -p "协议类型 (tcp/udp，默认 tcp): " proto
    proto=${proto:-tcp}

    if ! confirm "确定开放端口 $port/$proto ?"; then
        return
    fi

    case "$fw_type" in
        ufw)
            ufw allow "$port/$proto"
            ;;
        firewalld)
            firewall-cmd --permanent --add-port="$port/$proto"
            firewall-cmd --reload
            ;;
        iptables)
            iptables -A INPUT -p "$proto" --dport "$port" -j ACCEPT
            print_info "提示: iptables 规则重启后失效，建议保存规则"
            ;;
    esac

    print_success "端口 $port/$proto 已开放"
    log_action "开放了防火墙端口 $port/$proto"
    echo ""
    pause
}

firewall_close_port() {
    local fw_type="$1"

    if ! is_root; then
        print_error "此操作需要 root 权限"
        echo ""
        pause
        return
    fi

    read -r -p "输入要关闭的端口号: " port
    if [ -z "$port" ] || ! [[ "$port" =~ ^[0-9]+$ ]]; then
        print_error "无效端口号"
        sleep 1
        return
    fi

    read -r -p "协议类型 (tcp/udp，默认 tcp): " proto
    proto=${proto:-tcp}

    if ! confirm "确定关闭端口 $port/$proto ?"; then
        return
    fi

    case "$fw_type" in
        ufw)
            ufw deny "$port/$proto"
            ;;
        firewalld)
            firewall-cmd --permanent --remove-port="$port/$proto"
            firewall-cmd --reload
            ;;
        iptables)
            iptables -A INPUT -p "$proto" --dport "$port" -j DROP
            print_info "提示: iptables 规则重启后失效"
            ;;
    esac

    print_success "端口 $port/$proto 已关闭"
    log_action "关闭了防火墙端口 $port/$proto"
    echo ""
    pause
}

# ==================== 主菜单 ====================

show_menu() {
    clear
    print_title "=== 网络诊断 ==="

    cat << 'EOF'
1. 端口检查        - 查看端口占用/监听/连接
2. 网络接口信息    - IP地址/路由/DNS/公网IP
3. 连通性测试      - Ping/Traceroute/端口连通
4. 防火墙管理      - ufw/firewalld/iptables
b. 返回主菜单

EOF
}

# ==================== 主入口 ====================

main_network() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        port|ports)         check_ports ;;
        iface|interface)    show_interface ;;
        dns|nslookup)       show_interface ;;
        ping)               test_connectivity ;;
        traceroute|trace)   test_connectivity ;;
        firewall|fw)        manage_firewall ;;
        help|--help)        show_network_help ;;
        "")
            main
            ;;
        *)
            print_error "未知子命令: $subcmd"
            show_network_help
            exit 1
            ;;
    esac
}
main_network "$@"
