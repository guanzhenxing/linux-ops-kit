#!/bin/bash
# 监控告警模块 - 实时面板/阈值告警/资源报告

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# ==================== 告警阈值 ====================

# 默认阈值
CPU_WARN=80
CPU_CRIT=90
MEM_WARN=80
MEM_CRIT=90
DISK_WARN=80
DISK_CRIT=90

# ==================== 实时监控面板 ====================

realtime_dashboard() {
    clear

    # 捕获 Ctrl+C 优雅退出
    trap 'echo -e "\n"; print_info "退出实时监控"; tput cnorm; return 0' INT

    # 隐藏光标
    tput civis

    while true; do
        # 定位到屏幕顶部
        tput cup 0 0

        echo -e "${BLUE}${BOLD}=== 系统实时监控 ===    $(date '+%Y-%m-%d %H:%M:%S')    按 Ctrl+C 退出${NC}"
        echo "=================================================="

        # CPU 信息
        echo ""
        echo -e "${BOLD}[CPU]${NC}"
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{printf "%.1f", $2}')
        local cpu_cores=$(nproc 2>/dev/null || echo "N/A")
        local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)

        # 颜色编码
        local cpu_color="$GREEN"
        if (( $(echo "$cpu_usage >= $CPU_CRIT" | bc -l 2>/dev/null || echo 0) )); then
            cpu_color="$RED"
        elif (( $(echo "$cpu_usage >= $CPU_WARN" | bc -l 2>/dev/null || echo 0) )); then
            cpu_color="$YELLOW"
        fi

        echo -e "  使用率: ${cpu_color}${cpu_usage}%${NC}  |  核心数: ${cpu_cores}  |  负载: ${load_avg}"

        # CPU 进度条
        local bar_width=40
        local filled=$(echo "$cpu_usage $bar_width" | awk '{printf "%d", ($1/100)*$2}')
        local empty=$((bar_width - filled))
        local bar=""
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty; i++)); do bar+="░"; done
        echo -e "  [${cpu_color}${bar}${NC}]"

        # 内存信息
        echo ""
        echo -e "${BOLD}[内存]${NC}"
        local mem_info=$(free | grep Mem)
        local mem_total=$(echo $mem_info | awk '{printf "%.0f", $2/1024}')
        local mem_used=$(echo $mem_info | awk '{printf "%.0f", $3/1024}')
        local mem_percent=$(echo $mem_info | awk '{printf "%.0f", ($3/$2)*100}')
        local mem_avail=$(echo $mem_info | awk '{printf "%.0f", $7/1024}')

        local mem_color="$GREEN"
        if (( $(echo "$mem_percent >= $MEM_CRIT" | bc -l 2>/dev/null || echo 0) )); then
            mem_color="$RED"
        elif (( $(echo "$mem_percent >= $MEM_WARN" | bc -l 2>/dev/null || echo 0) )); then
            mem_color="$YELLOW"
        fi

        echo -e "  已用/总量: ${mem_color}${mem_used}MB / ${mem_total}MB (${mem_percent}%)${NC}  |  可用: ${mem_avail}MB"

        # 内存进度条
        filled=$(echo "$mem_percent $bar_width" | awk '{printf "%d", ($1/100)*$2}')
        empty=$((bar_width - filled))
        bar=""
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty; i++)); do bar+="░"; done
        echo -e "  [${mem_color}${bar}${NC}]"

        # Swap
        local swap_info=$(free | grep Swap)
        local swap_total=$(echo $swap_info | awk '{print $2}')
        if [ "$swap_total" -gt 0 ]; then
            local swap_used=$(echo $swap_info | awk '{printf "%.0f", $3/1024}')
            local swap_total_mb=$(echo $swap_info | awk '{printf "%.0f", $2/1024}')
            local swap_percent=$(echo $swap_info | awk '{printf "%.0f", ($3/$2)*100}')
            echo -e "  Swap: ${swap_used}MB / ${swap_total_mb}MB (${swap_percent}%)"
        fi

        # 磁盘信息
        echo ""
        echo -e "${BOLD}[磁盘]${NC}"
        df -h | grep -vE '^Filesystem|tmpfs|cdrom|udev|overlay' | while read -r line; do
            local usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
            local disk_color="$GREEN"
            if [ "$usage" -ge $DISK_CRIT ]; then
                disk_color="$RED"
            elif [ "$usage" -ge $DISK_WARN ]; then
                disk_color="$YELLOW"
            fi
            local mount=$(echo "$line" | awk '{print $6}')
            local size=$(echo "$line" | awk '{print $2}')
            local used=$(echo "$line" | awk '{print $3}')
            local pct=$(echo "$line" | awk '{print $5}')
            echo -e "  ${mount}: ${disk_color}${used}/${size} (${pct})${NC}"
        done

        # TOP 进程
        echo ""
        echo -e "${BOLD}[TOP 5 进程 (CPU)]${NC}"
        ps aux --sort=-%cpu | head -6 | tail -5 | \
            awk '{printf "  %-8s %5s%%  %5s%%  %s\n", $1, $3, $4, $11}'

        # 网络连接数
        echo ""
        echo -e "${BOLD}[网络]${NC}"
        local established=$(ss -tn 2>/dev/null | grep -c ESTAB 2>/dev/null || echo "N/A")
        local time_wait=$(ss -tn 2>/dev/null | grep -c TIME-WAIT 2>/dev/null || echo "N/A")
        echo -e "  活跃连接: ${GREEN}$established${NC}  |  TIME_WAIT: ${YELLOW}$time_wait${NC}"

        echo ""
        echo "=================================================="

        sleep 2
    done
}

# ==================== 阈值告警检查 ====================

check_thresholds() {
    clear
    print_title "=== 阈值告警检查 ==="

    cat << 'EOF'
1. 查看当前阈值
2. 修改阈值
3. 执行一次检查
0. 返回

EOF

    read -p "请选择 [0-3]: " choice

    case $choice in
        1)
            echo ""
            echo -e "${BOLD}当前告警阈值:${NC}"
            echo ""
            echo -e "  CPU:   ${YELLOW}警告 ${CPU_WARN}%${NC}  ${RED}严重 ${CPU_CRIT}%${NC}"
            echo -e "  内存:  ${YELLOW}警告 ${MEM_WARN}%${NC}  ${RED}严重 ${MEM_CRIT}%${NC}"
            echo -e "  磁盘:  ${YELLOW}警告 ${DISK_WARN}%${NC}  ${RED}严重 ${DISK_CRIT}%${NC}"
            echo ""
            pause
            ;;
        2)
            echo ""
            read -p "CPU 警告阈值 (当前 $CPU_WARN%): " input
            [ -n "$input" ] && CPU_WARN=$input
            read -p "CPU 严重阈值 (当前 $CPU_CRIT%): " input
            [ -n "$input" ] && CPU_CRIT=$input
            read -p "内存 警告阈值 (当前 $MEM_WARN%): " input
            [ -n "$input" ] && MEM_WARN=$input
            read -p "内存 严重阈值 (当前 $MEM_CRIT%): " input
            [ -n "$input" ] && MEM_CRIT=$input
            read -p "磁盘 警告阈值 (当前 $DISK_WARN%): " input
            [ -n "$input" ] && DISK_WARN=$input
            read -p "磁盘 严重阈值 (当前 $DISK_CRIT%): " input
            [ -n "$input" ] && DISK_CRIT=$input
            print_success "阈值已更新"
            echo ""
            pause
            ;;
        3) run_threshold_check ;;
        0) return ;;
        *)
            print_error "无效选择"
            sleep 1
            ;;
    esac
}

run_threshold_check() {
    echo ""
    print_info "执行阈值检查..."
    echo ""

    local has_warning=false
    local has_critical=false

    # CPU 检查
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{printf "%.1f", $2}')
    if (( $(echo "$cpu_usage >= $CPU_CRIT" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "  ${RED}${BOLD}[CRIT]${NC}  CPU 使用率: ${RED}${cpu_usage}%${NC} (阈值: ${CPU_CRIT}%)"
        has_critical=true
    elif (( $(echo "$cpu_usage >= $CPU_WARN" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "  ${YELLOW}${BOLD}[WARN]${NC}  CPU 使用率: ${YELLOW}${cpu_usage}%${NC} (阈值: ${CPU_WARN}%)"
        has_warning=true
    else
        echo -e "  ${GREEN}[OK]${NC}    CPU 使用率: ${cpu_usage}% (阈值: ${CPU_WARN}%)"
    fi

    # 内存检查
    local mem_percent=$(free | grep Mem | awk '{printf "%.0f", ($3/$2)*100}')
    if (( $(echo "$mem_percent >= $MEM_CRIT" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "  ${RED}${BOLD}[CRIT]${NC}  内存使用率: ${RED}${mem_percent}%${NC} (阈值: ${MEM_CRIT}%)"
        has_critical=true
    elif (( $(echo "$mem_percent >= $MEM_WARN" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "  ${YELLOW}${BOLD}[WARN]${NC}  内存使用率: ${YELLOW}${mem_percent}%${NC} (阈值: ${MEM_WARN}%)"
        has_warning=true
    else
        echo -e "  ${GREEN}[OK]${NC}    内存使用率: ${mem_percent}% (阈值: ${MEM_WARN}%)"
    fi

    # 磁盘检查
    df -h | grep -vE '^Filesystem|tmpfs|cdrom|udev|overlay' | while read -r line; do
        local usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
        local mount=$(echo "$line" | awk '{print $6}')

        if [ "$usage" -ge $DISK_CRIT ]; then
            echo -e "  ${RED}${BOLD}[CRIT]${NC}  磁盘 $mount: ${RED}${usage}%${NC} (阈值: ${DISK_CRIT}%)"
        elif [ "$usage" -ge $DISK_WARN ]; then
            echo -e "  ${YELLOW}${BOLD}[WARN]${NC}  磁盘 $mount: ${YELLOW}${usage}%${NC} (阈值: ${DISK_WARN}%)"
        else
            echo -e "  ${GREEN}[OK]${NC}    磁盘 $mount: ${usage}% (阈值: ${DISK_WARN}%)"
        fi
    done

    # 总结
    echo ""
    if $has_critical; then
        echo -e "  ${RED}${BOLD}⚠️  发现严重问题，请立即处理！${NC}"
    elif $has_warning; then
        echo -e "  ${YELLOW}⚠  存在警告项目，建议关注${NC}"
    else
        echo -e "  ${GREEN}✓  所有指标正常${NC}"
    fi

    echo ""
    pause
}

# ==================== 资源报告 ====================

generate_report() {
    clear
    print_title "=== 资源报告 ==="

    local report_file="/tmp/system-report-$(date +%Y%m%d-%H%M%S).txt"

    print_info "正在生成系统资源报告..."

    {
        echo "========================================"
        echo "  系统资源报告"
        echo "  生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "========================================"
        echo ""

        # 系统信息
        echo "[系统信息]"
        echo "----------------------------------------"
        local os_info=""
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            os_info="$PRETTY_NAME"
        fi
        echo "操作系统:    $os_info"
        echo "内核版本:    $(uname -r)"
        echo "架构:        $(uname -m)"
        echo "主机名:      $(hostname)"
        echo "运行时间:    $(uptime -p 2>/dev/null || uptime | awk '{print $3,$4}')"
        echo ""

        # CPU 信息
        echo "[CPU]"
        echo "----------------------------------------"
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{printf "%.1f", $2}')
        local cpu_cores=$(nproc 2>/dev/null || echo "N/A")
        local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
        local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
        echo "型号:        ${cpu_model:-N/A}"
        echo "核心数:      $cpu_cores"
        echo "使用率:      ${cpu_usage}%"
        echo "平均负载:    $load_avg"
        echo ""

        echo "TOP 10 进程 (CPU):"
        ps aux --sort=-%cpu | head -11 | awk '{printf "  %-8s %6s %5s%%  %5s%%  %s\n", $1, $2, $3, $4, $11}'
        echo ""

        # 内存信息
        echo "[内存]"
        echo "----------------------------------------"
        free -h
        echo ""

        # 磁盘信息
        echo "[磁盘]"
        echo "----------------------------------------"
        df -hT | grep -vE 'tmpfs|cdrom|udev|overlay'
        echo ""

        # 网络信息
        echo "[网络]"
        echo "----------------------------------------"
        if command_exists ip; then
            ip -brief addr show 2>/dev/null
        fi
        echo ""

        # 活跃服务
        echo "[活跃服务]"
        echo "----------------------------------------"
        if has_systemd; then
            systemctl list-units --type=service --state=running --no-pager --plain 2>/dev/null | \
                grep -v '^UNIT' | awk '{print "  " $1}' | head -15
        fi
        echo ""

        # 最近登录
        echo "[最近登录]"
        echo "----------------------------------------"
        last -n 5 2>/dev/null
        echo ""

        echo "========================================"
        echo "报告结束"
    } > "$report_file"

    print_success "报告已生成: $report_file"

    echo ""
    read -p "查看报告? [y/N]: " view
    if [ "$view" = "y" ] || [ "$view" = "Y" ]; then
        less "$report_file"
    fi
}

# ==================== 主菜单 ====================

show_menu() {
    clear
    print_title "=== 监控告警 ==="

    cat << 'EOF'
1. 实时监控面板    - 实时刷新 CPU/内存/磁盘/网络
2. 阈值告警检查    - 查看/修改阈值，执行检查
3. 资源报告        - 生成系统资源报告文件
b. 返回主菜单

EOF
}

# ==================== 主循环 ====================

main() {
    while true; do
        show_menu
        read -p "请选择 [1-3/b]: " choice

        case $choice in
            1) realtime_dashboard ;;
            2) check_thresholds ;;
            3) generate_report ;;
            b|B) return 0 ;;
            *)
                print_error "无效选择"
                sleep 1
                ;;
        esac
    done
}

main "$@"
