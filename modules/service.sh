#!/bin/bash
set -uo pipefail
# 服务管理模块 - 服务状态概览/启停/自启管理

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# ==================== 常见服务列表 ====================

# 服务名列表（兼容 Ubuntu/CentOS 不同命名）
SERVICE_LIST=(
    "nginx"
    "apache2 httpd"
    "mysql mysqld mariadb"
    "postgresql"
    "docker"
    "redis-server redis"
    "mongod"
    "php-fpm php8.1-fpm php8.2-fpm php8.3-fpm"
    "ssh sshd"
    "cron crond"
    "firewalld ufw"
    "elasticsearch"
    "memcached"
    "rabbitmq-server rabbitmq"
    "etcd"
    "kubelet"
)

# ==================== 服务状态概览 ====================

show_service_overview() {
    clear
    print_title "=== 服务状态概览 ==="

    local total=0
    local running=0
    local stopped=0
    local not_installed=0

    for service_group in "${SERVICE_LIST[@]}"; do
        # 找到系统中实际存在的服务名
        local actual_service=""
        for name in $service_group; do
            if service_exists "$name"; then
                actual_service="$name"
                break
            fi
        done

        total=$((total + 1))
        echo -e -n "  "

        if [ -z "$actual_service" ]; then
            # 未安装
            echo -e "${CYAN}⬜${NC} $(echo "$service_group" | awk '{print $1}') ${CYAN}(未安装)${NC}"
            not_installed=$((not_installed + 1))
            continue
        fi

        # 检查运行状态
        local is_active=false
        if has_systemd; then
            systemctl is-active --quiet "$actual_service" 2>/dev/null && is_active=true
        else
            service "$actual_service" status &>/dev/null && is_active=true
        fi

        if $is_active; then
            local pid=$(pgrep -x "$actual_service" 2>/dev/null | head -1)
            pid=${pid:-N/A}
            echo -e "${GREEN}✓${NC}  $actual_service ${GREEN}(运行中)${NC} PID: $pid"
            running=$((running + 1))
        else
            echo -e "${RED}✗${NC}  $actual_service ${RED}(已停止)${NC}"
            stopped=$((stopped + 1))
        fi
    done

    # 统计
    echo ""
    echo "----------------------------------------"
    echo -e "共检测 ${BOLD}$total${NC} 项 | ${GREEN}运行中: $running${NC} | ${RED}已停止: $stopped${NC} | ${CYAN}未安装: $not_installed${NC}"

    echo ""
    pause
}

# ==================== 管理单个服务 ====================

manage_single_service() {
    clear
    print_title "=== 管理单个服务 ==="

    read -r -p "请输入服务名: " service_name

    if [ -z "$service_name" ]; then
        print_error "服务名不能为空"
        sleep 1
        return
    fi

    if ! service_exists "$service_name"; then
        print_error "服务 '$service_name' 未安装或不存在"
        echo ""
        pause
        return
    fi

    # 显示当前状态
    echo ""
    local is_active=false
    if has_systemd; then
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            is_active=true
            echo -e "当前状态: ${GREEN}运行中${NC}"
        else
            echo -e "当前状态: ${RED}已停止${NC}"
        fi

        local enabled_str=""
        if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
            enabled_str="${GREEN}已启用${NC}"
        else
            enabled_str="${YELLOW}已禁用${NC}"
        fi
        echo -e "开机自启: $enabled_str"
    else
        if service "$service_name" status &>/dev/null; then
            is_active=true
            echo -e "当前状态: ${GREEN}运行中${NC}"
        else
            echo -e "当前状态: ${RED}已停止${NC}"
        fi
    fi

    # 操作子菜单
    echo ""
    echo -e "${BOLD}操作:${NC}"
    cat << 'EOF'
1. 启动服务
2. 停止服务
3. 重启服务
4. 查看详细状态
5. 设置开机自启
6. 禁止开机自启
0. 返回

EOF

    read -r -p "请选择 [0-6]: " action

    case $action in
        1) do_service_action "$service_name" "start" ;;
        2) do_service_action "$service_name" "stop" ;;
        3) do_service_action "$service_name" "restart" ;;
        4) show_service_status "$service_name" ;;
        5) do_service_action "$service_name" "enable" ;;
        6) do_service_action "$service_name" "disable" ;;
        0) return ;;
        *) print_error "无效选择"; sleep 1 ;;
    esac
}

# ==================== 服务操作 ====================

do_service_action() {
    local service="$1"
    local action="$2"

    # 启停操作需要 root
    case "$action" in
        start|stop|restart|enable|disable)
            if ! is_root; then
                print_error "此操作需要 root 权限"
                print_info "请使用: sudo ops.sh 或以 root 用户运行"
                echo ""
                pause
                return
            fi
            ;;
    esac

    local action_cn=""
    case "$action" in
        start)   action_cn="启动" ;;
        stop)    action_cn="停止" ;;
        restart) action_cn="重启" ;;
        enable)  action_cn="设置开机自启" ;;
        disable) action_cn="禁止开机自启" ;;
    esac

    echo ""
    print_info "正在${action_cn}服务 $service ..."

    if has_systemd; then
        case "$action" in
            start|stop|restart)
                show_cmd "${action_cn}服务: $service" "systemctl $action '$service'"
                ;;
            enable)
                show_cmd "设置开机自启: $service" "systemctl enable '$service'"
                ;;
            disable)
                show_cmd "禁止开机自启: $service" "systemctl disable '$service'"
                ;;
        esac
    else
        case "$action" in
            start|stop|restart)
                show_cmd "${action_cn}服务: $service" "service '$service' $action"
                ;;
            enable)
                show_cmd "设置开机自启: $service" "chkconfig '$service' on || update-rc.d '$service' enable"
                ;;
            disable)
                show_cmd "禁止开机自启: $service" "chkconfig '$service' off || update-rc.d '$service' disable"
                ;;
        esac
    fi

    if [ $? -eq 0 ]; then
        print_success "服务 $service ${action_cn}成功"
        log_action "${action_cn}了服务 $service"
    else
        print_error "服务 $service ${action_cn}失败"
    fi

    echo ""
    pause
}

# ==================== 查看服务详细状态 ====================

show_service_status() {
    local service="$1"

    echo ""
    print_info "服务 $service 详细状态:"
    echo ""

    if has_systemd; then
        systemctl status "$service" --no-pager 2>&1 | head -20
    else
        service "$service" status 2>&1 | head -20
    fi

    echo ""
    pause
}

# ==================== 主菜单 ====================

show_menu() {
    clear
    print_title "=== 服务管理 ==="

    cat << 'EOF'
1. 服务状态概览    - 扫描常见服务运行状态
2. 管理单个服务    - 启动/停止/重启/查看状态/开机自启
b. 返回主菜单

EOF
}

# ==================== 子命令帮助 ====================
show_service_help() {
    cat << 'HELP'
用法: ./ops.sh service <子命令> [参数]

子命令:
  overview             服务状态概览
  status <服务名>      查看服务详细状态
  start  <服务名>      启动服务
  stop   <服务名>      停止服务
  restart <服务名>     重启服务
  enable <服务名>      设置开机自启
  disable <服务名>     禁止开机自启
  help                 显示此帮助

无子命令运行进入交互式菜单。

示例:
  ./ops.sh service overview
  ./ops.sh service status nginx
  ./ops.sh service restart nginx
HELP
}

# ==================== 主入口 ====================

main_service() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        overview|list)  show_service_overview ;;
        status)         show_service_status "$1" ;;
        start)          do_service_action "$1" "start" ;;
        stop)           do_service_action "$1" "stop" ;;
        restart)        do_service_action "$1" "restart" ;;
        enable)         do_service_action "$1" "enable" ;;
        disable)        do_service_action "$1" "disable" ;;
        help|--help)    show_service_help ;;
        "")
            main
            ;;
        *)
            print_error "未知子命令: $subcmd"
            show_service_help
            exit 1
            ;;
    esac
}

# ==================== 主循环 ====================

main() {
    while true; do
        show_menu
        read -r -p "请选择 [1-2/b]: " choice

        case $choice in
            1) show_service_overview ;;
            2) manage_single_service ;;
            b|B) return 0 ;;
            *)
                print_error "无效选择"
                sleep 1
                ;;
        esac
    done
}

main_service "$@"

