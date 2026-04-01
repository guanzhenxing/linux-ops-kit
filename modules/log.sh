#!/bin/bash
# 日志管理模块 - 系统日志/服务日志/实时跟踪/日志搜索

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# ==================== 服务日志路径映射 ====================

# 初始化日志路径（根据发行版调整）
init_service_logs() {
    declare -gA SERVICE_LOGS
    SERVICE_LOGS=(
        ["nginx"]="/var/log/nginx/error.log /var/log/nginx/access.log"
        ["apache2"]="/var/log/apache2/error.log /var/log/apache2/access.log"
        ["httpd"]="/var/log/httpd/error_log /var/log/httpd/access_log"
        ["mysql"]="/var/log/mysql/error.log"
        ["mysqld"]="/var/log/mysqld.log"
        ["postgresql"]="/var/log/postgresql/"
        ["docker"]="JOURNAL"
        ["redis-server"]="/var/log/redis/redis-server.log"
        ["redis"]="/var/log/redis/redis.log"
        ["mongod"]="/var/log/mongodb/mongod.log"
        ["php-fpm"]="/var/log/php-fpm/error.log"
        ["sshd"]="/var/log/auth.log"
        ["syslog"]="/var/log/syslog"
    )
}

# ==================== 系统日志 ====================

show_system_log() {
    clear
    print_title "=== 系统日志 ==="

    cat << 'EOF'
1. systemd 日志 (journalctl)  - 最近50条
2. systemd 日志 - 按时间范围
3. systemd 日志 - 按优先级 (错误/警告)
4. 内核日志 (dmesg)           - 最近50条
5. syslog                     - 最近50条
0. 返回

EOF

    read -p "请选择 [0-5]: " choice

    case $choice in
        1)
            if command_exists journalctl; then
                journalctl --no-pager -n 50 | less -R
            else
                print_error "journalctl 不可用"
                sleep 1
            fi
            ;;
        2)
            show_journal_by_time
            ;;
        3)
            if command_exists journalctl; then
                print_info "显示错误和警告级别的日志..."
                journalctl --no-pager -p err -n 30
                echo ""
                journalctl --no-pager -p warning -n 20
                echo ""
                pause
            else
                print_error "journalctl 不可用"
                sleep 1
            fi
            ;;
        4)
            dmesg | tail -50 | less -R
            ;;
        5)
            if [ -f /var/log/syslog ]; then
                tail -50 /var/log/syslog | less -R
            else
                print_error "/var/log/syslog 不存在"
                sleep 1
            fi
            ;;
        0) return ;;
        *)
            print_error "无效选择"
            sleep 1
            ;;
    esac
}

show_journal_by_time() {
    if ! command_exists journalctl; then
        print_error "journalctl 不可用"
        sleep 1
        return
    fi

    echo ""
    echo -e "${BOLD}时间范围:${NC}"
    cat << 'EOF'
1. 最近 1 小时
2. 最近 6 小时
3. 最近 24 小时
4. 最近 7 天
5. 自定义
EOF

    read -p "请选择 [1-5]: " time_choice
    local since=""

    case $time_choice in
        1) since="1 hour ago" ;;
        2) since="6 hours ago" ;;
        3) since="24 hours ago" ;;
        4) since="7 days ago" ;;
        5)
            read -p "输入时间 (如 '2024-01-01' 或 '2 hours ago'): " since
            [ -z "$since" ] && return
            ;;
        *) return ;;
    esac

    print_info "显示自 $since 以来的日志..."
    journalctl --no-pager --since "$since" | less -R
}

# ==================== 服务日志 ====================

show_service_log() {
    clear
    print_title "=== 服务日志 ==="

    init_service_logs

    # 列出可用的服务日志
    echo -e "${BOLD}可查看日志的服务:${NC}"
    echo ""

    local idx=1
    local services=()

    for service in "${!SERVICE_LOGS[@]}"; do
        local log_paths="${SERVICE_LOGS[$service]}"

        if [ "$log_paths" = "JOURNAL" ]; then
            if command_exists journalctl; then
                echo -e "  ${GREEN}$idx${NC}. $service ${CYAN}(journalctl)${NC}"
                services+=("$service")
                idx=$((idx + 1))
            fi
            continue
        fi

        local found=false
        for path in $log_paths; do
            if [ -f "$path" ] || [ -d "$path" ]; then
                found=true
                break
            fi
        done

        if $found; then
            echo -e "  ${GREEN}$idx${NC}. $service"
            services+=("$service")
            idx=$((idx + 1))
        fi
    done

    if [ ${#services[@]} -eq 0 ]; then
        print_warn "未找到可用的服务日志文件"
        echo ""
        pause
        return
    fi

    echo ""
    read -p "选择服务编号 (0 返回): " num

    [ "$num" = "0" ] && return

    if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "${#services[@]}" ]; then
        print_error "无效选择"
        sleep 1
        return
    fi

    local selected_service="${services[$((num - 1))]}"
    local log_paths="${SERVICE_LOGS[$selected_service]}"

    if [ "$log_paths" = "JOURNAL" ]; then
        journalctl -u "$selected_service" --no-pager -n 100 | less -R
        return
    fi

    if [ -d "$log_paths" ]; then
        echo ""
        echo -e "${BOLD}可用日志文件:${NC}"
        local files=()
        local fidx=1
        for f in "$log_paths"/*; do
            [ -f "$f" ] || continue
            echo -e "  ${GREEN}$fidx${NC}. $(basename "$f")"
            files+=("$f")
            fidx=$((fidx + 1))
        done

        if [ ${#files[@]} -eq 0 ]; then
            print_warn "目录下无日志文件"
            sleep 1
            return
        fi

        echo ""
        read -p "选择文件编号: " fnum
        if [[ "$fnum" =~ ^[0-9]+$ ]] && [ "$fnum" -ge 1 ] && [ "$fnum" -le "${#files[@]}" ]; then
            tail -100 "${files[$((fnum - 1))]}" | less -R
        fi
        return
    fi

    local files=()
    for path in $log_paths; do
        [ -f "$path" ] && files+=("$path")
    done

    if [ ${#files[@]} -eq 1 ]; then
        tail -100 "${files[0]}" | less -R
    else
        echo ""
        echo -e "${BOLD}选择日志文件:${NC}"
        for i in "${!files[@]}"; do
            echo -e "  ${GREEN}$((i + 1))${NC}. ${files[$i]}"
        done

        echo ""
        read -p "选择编号: " fnum
        if [[ "$fnum" =~ ^[0-9]+$ ]] && [ "$fnum" -ge 1 ] && [ "$fnum" -le "${#files[@]}" ]; then
            tail -100 "${files[$((fnum - 1))]}" | less -R
        fi
    fi
}

# ==================== 实时跟踪 ====================

follow_log() {
    clear
    print_title "=== 实时日志跟踪 ==="

    init_service_logs

    echo -e "${BOLD}选择日志源:${NC}"
    echo ""
    echo "1. 从服务日志列表选择"
    echo "2. 手动输入日志文件路径"
    echo "0. 返回"
    echo ""

    read -p "请选择 [0-2]: " choice

    case $choice in
        0) return ;;
        1)
            local log_files=()
            for service in "${!SERVICE_LOGS[@]}"; do
                local log_paths="${SERVICE_LOGS[$service]}"
                [ "$log_paths" = "JOURNAL" ] && continue
                for path in $log_paths; do
                    if [ -f "$path" ]; then
                        log_files+=("$path")
                    fi
                done
            done

            [ -f /var/log/syslog ] && log_files+=("/var/log/syslog")
            [ -f /var/log/auth.log ] && log_files+=("/var/log/auth.log")
            [ -f /var/log/kern.log ] && log_files+=("/var/log/kern.log")

            if [ ${#log_files[@]} -eq 0 ]; then
                print_warn "未找到可跟踪的日志文件"
                sleep 1
                return
            fi

            echo ""
            for i in "${!log_files[@]}"; do
                echo -e "  ${GREEN}$((i + 1))${NC}. ${log_files[$i]}"
            done

            echo ""
            read -p "选择编号: " fnum
            if [[ "$fnum" =~ ^[0-9]+$ ]] && [ "$fnum" -ge 1 ] && [ "$fnum" -le "${#log_files[@]}" ]; then
                start_follow "${log_files[$((fnum - 1))]}"
            fi
            ;;
        2)
            read -p "输入日志文件路径: " log_path
            if [ -z "$log_path" ]; then
                return
            fi
            if [ ! -f "$log_path" ]; then
                print_error "文件不存在: $log_path"
                sleep 1
                return
            fi
            start_follow "$log_path"
            ;;
        *)
            print_error "无效选择"
            sleep 1
            ;;
    esac
}

start_follow() {
    local log_file="$1"
    echo ""
    print_info "实时跟踪: $log_file"
    print_info "按 Ctrl+C 退出"
    echo ""
    sleep 1
    tail -f "$log_file" 2>/dev/null || print_error "无法读取日志文件"
}

# ==================== 日志搜索 ====================

search_log() {
    clear
    print_title "=== 日志搜索 ==="

    read -p "输入搜索关键词: " keyword
    [ -z "$keyword" ] && return

    echo ""
    echo -e "${BOLD}搜索范围:${NC}"
    cat << 'EOF'
1. 系统日志 (journalctl)
2. 指定日志文件
3. /var/log 下所有 .log 文件
0. 返回

EOF

    read -p "请选择 [0-3]: " choice

    case $choice in
        1)
            if ! command_exists journalctl; then
                print_error "journalctl 不可用"
                sleep 1
                return
            fi

            local time_range
            time_range=$(select_time_range)
            [ $? -ne 0 ] && return

            print_info "在 journalctl 中搜索 '$keyword'..."
            echo ""
            if [ -n "$time_range" ]; then
                journalctl --no-pager --since "$time_range" --grep "$keyword" | less -R
            else
                journalctl --no-pager --grep "$keyword" | less -R
            fi
            ;;
        2)
            read -p "输入日志文件路径: " file_path
            if [ -z "$file_path" ] || [ ! -f "$file_path" ]; then
                print_error "文件不存在"
                sleep 1
                return
            fi

            print_info "在 $file_path 中搜索 '$keyword'..."
            echo ""
            grep -i "$keyword" "$file_path" | less -R
            ;;
        3)
            print_info "在 /var/log 下搜索 '$keyword' (可能需要较长时间)..."
            echo ""
            grep -r -i "$keyword" /var/log/*.log 2>/dev/null | head -200 | less -R
            ;;
        0) return ;;
        *)
            print_error "无效选择"
            sleep 1
            ;;
    esac
}

select_time_range() {
    echo ""
    echo -e "${BOLD}时间范围 (可选):${NC}"
    cat << 'EOF'
1. 最近 1 小时
2. 最近 6 小时
3. 最近 24 小时
4. 最近 7 天
5. 不限时间
EOF

    read -p "请选择 [1-5] (默认5): " time_choice

    case $time_choice in
        1) echo "1 hour ago" ;;
        2) echo "6 hours ago" ;;
        3) echo "24 hours ago" ;;
        4) echo "7 days ago" ;;
        5|"") echo "" ;;
        *) return 1 ;;
    esac
}

# ==================== 主菜单 ====================

show_menu() {
    clear
    print_title "=== 日志管理 ==="

    cat << 'EOF'
1. 系统日志        - journalctl/dmesg/syslog
2. 服务日志        - Nginx/MySQL/Docker 等常见服务
3. 实时跟踪        - tail -f 实时查看日志
4. 日志搜索        - 按关键词和时间范围搜索
b. 返回主菜单

EOF
}

# ==================== 主循环 ====================

main() {
    while true; do
        show_menu
        read -p "请选择 [1-4/b]: " choice

        case $choice in
            1) show_system_log ;;
            2) show_service_log ;;
            3) follow_log ;;
            4) search_log ;;
            b|B) return 0 ;;
            *)
                print_error "无效选择"
                sleep 1
                ;;
        esac
    done
}

main "$@"
