#!/bin/bash
set -uo pipefail
# 系统检查模块 - CPU/内存/磁盘/服务健康检查

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# ==================== 主菜单 ====================

show_menu() {
    clear
    print_title "=== 系统检查 ==="

    cat << 'EOF'
1. 全部检查      - 依次显示所有信息
2. 系统信息      - 内核/系统/架构/运行时间
3. CPU 检查      - 使用率/核心数/负载/进程排行
4. 内存检查      - 使用率/可用内存/缓存/交换分区
5. 磁盘检查      - 各分区使用情况/Inode
6. 服务检查      - 运行中服务状态/指定服务检查
b. 返回主菜单

EOF
}

# ==================== 系统信息 ====================

show_system_info() {
    clear
    print_title "=== 系统信息 ==="

    # 获取系统信息
    local os_info=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os_info="$PRETTY_NAME"
    elif [ -f /etc/redhat-release ]; then
        os_info=$(cat /etc/redhat-release)
    elif [ -f /etc/debian_version ]; then
        os_info="Debian $(cat /etc/debian_version)"
    else
        os_info="Unknown"
    fi

    local kernel=$(uname -r)
    local arch=$(uname -m)
    local hostname=$(hostname)
    local uptime_info=$(uptime -p 2>/dev/null || uptime | awk '{print $3,$4}')
    local current_user=$(whoami)
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')

    # 显示信息
    echo -e "${CYAN}操作系统:${NC}      $os_info"
    echo -e "${CYAN}内核版本:${NC}      $kernel"
    echo -e "${CYAN}架构:${NC}          $arch"
    echo -e "${CYAN}主机名:${NC}        $hostname"
    echo -e "${CYAN}运行时间:${NC}      $uptime_info"
    echo -e "${CYAN}当前用户:${NC}      $current_user"
    echo -e "${CYAN}当前时间:${NC}      $current_time"

    echo ""
    pause
}

# ==================== CPU 检查 ====================

show_cpu_check() {
    clear
    print_title "=== CPU 检查 ==="

    # CPU 使用率
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo -e "${CYAN}CPU 使用率:${NC}    ${cpu_usage}%"

    # CPU 核心数
    local cpu_cores=$(nproc 2>/dev/null || echo "N/A")
    local cpu_threads=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "N/A")
    echo -e "${CYAN}CPU 核心数:${NC}    ${cpu_cores} 核 ${cpu_threads} 线程"

    # 平均负载
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    echo -e "${CYAN}平均负载:${NC}     ${load_avg}  (1分钟/5分钟/15分钟)"

    echo ""
    echo -e "${BOLD}TOP 5 进程:${NC}"

    # 获取 TOP 5 进程
    if command_exists ps; then
        echo -e "\n  ${BOLD}PID${NC}    ${BOLD}%CPU${NC}  ${BOLD}COMMAND${NC}"
        ps aux --sort=-%cpu | head -6 | tail -5 | awk '{printf "  %-6s %-5s %s\n", $2, $3, $11}'
    fi

    echo ""
    pause
}

# ==================== 内存检查 ====================

show_memory_check() {
    clear
    print_title "=== 内存检查 ==="

    # 获取内存信息
    local mem_info=$(free -h | grep Mem)
    local mem_total=$(echo $mem_info | awk '{print $2}')
    local mem_used=$(echo $mem_info | awk '{print $3}')
    local mem_avail=$(echo $mem_info | awk '{print $7}')

    # 计算使用率
    local mem_percent=$(free | grep Mem | awk '{printf "%.0f", ($3/$2)*100}')

    echo -e "${CYAN}总内存:${NC}        $mem_total"
    echo -e "${CYAN}已使用:${NC}        $mem_used ($mem_percent%)"
    echo -e "${CYAN}可用:${NC}          $mem_avail"

    # 缓存/缓冲
    local buffers=$(free -h | grep Mem | awk '{print $6}')
    local cached=$(free -h | grep Mem | awk '{print $7}')
    echo -e "${CYAN}缓存/缓冲:${NC}     $buffers / $cached"

    # 交换分区
    local swap_info=$(free -h | grep Swap)
    local swap_total=$(echo $swap_info | awk '{print $2}')
    local swap_used=$(echo $swap_info | awk '{print $3}')
    local swap_percent=$(free | grep Swap | awk '{if($2>0) printf "%.0f", ($3/$2)*100; else print "0"}')

    echo ""
    echo -e "${CYAN}交换分区:${NC}      $swap_used / $swap_total ($swap_percent%)"

    echo ""
    pause
}

# ==================== 磁盘检查 ====================

show_disk_check() {
    clear
    print_title "=== 磁盘检查 ==="

    # 磁盘使用情况
    echo -e "${BOLD}文件系统${NC}        ${BOLD}总容量${NC}    ${BOLD}已用${NC}     ${BOLD}可用${NC}    ${BOLD}使用%${NC}  ${BOLD}挂载点${NC}"
    df -h | grep -vE '^Filesystem|tmpfs|cdrom|udev' | while read -r line; do
        local usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
        local indicator=""
        if [ "$usage" -ge 90 ]; then
            indicator=" ${RED}⚠️${NC}"
        elif [ "$usage" -ge 80 ]; then
            indicator=" ${YELLOW}⚠${NC}"
        fi
        echo "$line$indicator"
    done

    # Inode 状态
    echo ""
    echo -e "${BOLD}Inode 状态:${NC}"
    df -i | grep -vE '^Filesystem|tmpfs|cdrom|udev' | while read -r line; do
        local usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
        local indicator=""
        if [ "$usage" -ge 90 ]; then
            indicator=" ${RED}⚠️${NC}"
        elif [ "$usage" -ge 80 ]; then
            indicator=" ${YELLOW}⚠${NC}"
        fi
        echo "$line$indicator"
    done

    echo ""
    pause
}

# ==================== 服务检查 ====================

show_service_check() {
    clear
    print_title "=== 服务检查 ==="

    # 自动检测运行中的服务
    echo -e "${BOLD}运行中的服务:${NC}\n"

    local services_found=0

    if has_systemd; then
        # 使用 systemd
        systemctl list-units --type=service --state=running --no-pager --plain 2>/dev/null | grep -v '^UNIT' | head -10 | while read -r line; do
            local service=$(echo "$line" | awk '{print $1}')
            local pid=$(systemctl show -p MainPID --value "$service" 2>/dev/null)
            pid=${pid:-0}

            if [ "$pid" -gt 0 ]; then
                echo -e "  ${GREEN}✓${NC} $service (pid: $pid)"
                services_found=1
            fi
        done
    else
        # 使用 service 命令
        for service in nginx apache2 mysql postgresql redis-server docker; do
            if service_exists "$service"; then
                local pid=$(pgrep -x "$service" | head -1)
                pid=${pid:-N/A}
                echo -e "  ${GREEN}✓${NC} $service (pid: $pid)"
                services_found=1
            fi
        done
    fi

    if [ "$services_found" -eq 0 ]; then
        print_warn "未检测到运行中的服务"
    fi

    echo ""
    echo -e "${BOLD}检查特定服务:${NC}"
    read -r -p "请输入服务名 (留空跳过): " specific_service

    if [ -n "$specific_service" ]; then
        echo ""
        if has_systemd; then
            systemctl status "$specific_service" --no-pager 2>&1 | head -15
        else
            service "$specific_service" status 2>&1 | head -15
        fi
    fi

    echo ""
    pause
}

# ==================== 全部检查 ====================

show_all_check() {
    clear
    print_title "=== 全部系统检查 ==="

    # 系统信息
    echo -e "\n${BOLD}[1/6] 系统信息${NC}"
    echo "----------------------------------------"
    local os_info=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os_info="$PRETTY_NAME"
    fi
    echo -e "系统:      $os_info"
    echo -e "内核:      $(uname -r)"
    echo -e "架构:      $(uname -m)"
    echo -e "运行时间:  $(uptime -p 2>/dev/null || uptime | awk '{print $3,$4}')"

    # CPU
    echo -e "\n${BOLD}[2/6] CPU${NC}"
    echo "----------------------------------------"
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local load_avg=$(uptime | awk -F'load average:' '{print $2}')
    echo -e "CPU 使用率: ${cpu_usage}%"
    echo -e "核心数:    $(nproc 2>/dev/null || echo N/A) 核"
    echo -e "负载:      $load_avg"

    # 内存
    echo -e "\n${BOLD}[3/6] 内存${NC}"
    echo "----------------------------------------"
    local mem_percent=$(free | grep Mem | awk '{printf "%.0f", ($3/$2)*100}')
    local swap_percent=$(free | grep Swap | awk '{if($2>0) printf "%.0f", ($3/$2)*100; else print "0"}')
    echo -e "内存:      $(get_memory_usage)"
    echo -e "交换分区:  $swap_percent%"

    # 磁盘
    echo -e "\n${BOLD}[4/6] 磁盘${NC}"
    echo "----------------------------------------"
    df -h | grep -vE '^Filesystem|tmpfs|cdrom|udev' | head -10

    # 服务
    echo -e "\n${BOLD}[5/6] 主要服务${NC}"
    echo "----------------------------------------"
    for service in nginx apache2 mysql redis-server docker; do
        if service_exists "$service"; then
            local pid=$(pgrep -x "$service" | head -1)
            if [ -n "$pid" ]; then
                echo -e "  ${GREEN}✓${NC} $service"
            else
                echo -e "  ${RED}✗${NC} $service"
            fi
        fi
    done

    # 总结
    echo -e "\n${BOLD}[6/6] 健康状态总结${NC}"
    echo "----------------------------------------"
    local issues=0

    # 检查磁盘
    while read -r line; do
        local usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
        if [ "$usage" -ge 90 ]; then
            echo -e "  ${RED}⚠️${NC} 磁盘 $(echo $line | awk '{print $1}') 使用率 ${usage}%"
            issues=$((issues + 1))
        fi
    done < <(df -h | grep -vE '^Filesystem|tmpfs|cdrom|udev')

    # 检查内存
    if [ "$mem_percent" -ge 90 ]; then
        echo -e "  ${RED}⚠️${NC} 内存使用率 ${mem_percent}%"
        issues=$((issues + 1))
    fi

    if [ "$issues" -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} 系统状态正常"
    else
        echo -e "  ${YELLOW}⚠${NC} 发现 $issues 个需要注意的问题"
    fi

    echo ""
    pause
}

# ==================== 主循环 ====================

main() {
    while true; do
        show_menu
        read -r -p "请选择 [1-6/b]: " choice

        case $choice in
            1) show_all_check ;;
            2) show_system_info ;;
            3) show_cpu_check ;;
            4) show_memory_check ;;
            5) show_disk_check ;;
            6) show_service_check ;;
            b|B) return 0 ;;
            *)
                print_error "无效选择"
                sleep 1
                ;;
        esac
    done
}

main "$@"
