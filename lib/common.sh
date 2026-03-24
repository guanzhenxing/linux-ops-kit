#!/bin/bash
# Linux 运维工具箱 - 核心函数库
# 提供颜色输出、通用函数、系统检测等功能

# ==================== 颜色定义 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ==================== 输出函数 ====================

# 信息输出（绿色）
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# 警告输出（黄色）
print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 错误输出（红色）
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 成功输出（绿色加粗）
print_success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"
}

# 标题输出（蓝色加粗）
print_title() {
    echo -e "\n${BLUE}${BOLD}$1${NC}"
    echo -e "${BLUE}${BOLD}$(printf '=%.0s' {1..50})${NC}\n"
}

# ==================== 交互函数 ====================

# 确认提示（返回 true/false）
# 用法: if confirm "确定要删除吗？"; then ... fi
confirm() {
    local prompt="$1 [y/N]: "
    local answer
    read -p "$prompt" answer
    [ "$answer" = "y" ] || [ "$answer" = "Y" ]
}

# 任意键继续
pause() {
    echo -e "\n${CYAN}按任意键继续...${NC}"
    read -n 1 -s
}

# 菜单选择（范围限制）
# 用法: choice=$(menu_choice "请选择" 1 5)
menu_choice() {
    local prompt="$1"
    local min=$2
    local max=$3
    local choice

    while true; do
        read -p "$prompt [$min-$max]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge "$min" ] && [ "$choice" -le "$max" ]; then
            echo "$choice"
            return
        fi
        print_error "无效选择，请输入 $min-$max 之间的数字"
    done
}

# ==================== 系统检测函数 ====================

# 检测操作系统类型
# 返回: ubuntu|centos|debian|unknown
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID" | tr '[:upper:]' '[:lower:]'
    elif [ -f /etc/redhat-release ]; then
        echo "centos"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# 检测是否有 systemd
has_systemd() {
    command -v systemctl &>/dev/null && [ -d /run/systemd/system ]
}

# 检测服务状态
# 用法: if service_exists "nginx"; then ... fi
service_exists() {
    local service=$1
    if has_systemd; then
        systemctl list-unit-files | grep -q "^${service}.service"
    else
        service "$service" status &>/dev/null
    fi
}

# 检测命令是否存在
# 用法: if command_exists "docker"; then ... fi
command_exists() {
    command -v "$1" &>/dev/null
}

# ==================== 系统信息获取 ====================

# 获取 CPU 使用率
get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1
}

# 获取内存使用情况
# 格式: "used/total (percent%)"
get_memory_usage() {
    local mem_info=$(free -h | grep Mem)
    local total=$(echo $mem_info | awk '{print $2}')
    local used=$(echo $mem_info | awk '{print $3}')
    local percent=$(free | grep Mem | awk '{printf "%.0f", ($3/$2)*100}')
    echo "${used}/${total} (${percent}%)"
}

# 获取磁盘使用情况
# 用法: get_disk_usage /path
get_disk_usage() {
    local path=${1:-/}
    df -h "$path" | tail -1 | awk '{print $5 " 已使用 (" $3 "/" $2 ")"}'
}

# 获取指定端口占用情况
# 返回: "PORT|PID|COMMAND" 或空
get_port_info() {
    local port=$1
    if command_exists "ss"; then
        ss -tlnp | grep ":$port " | head -1
    elif command_exists "netstat"; then
        netstat -tlnp | grep ":$port " | head -1
    fi
}

# ==================== 日志函数 ====================

# 记录操作日志
# 用法: log_action "启动了 nginx 服务"
log_action() {
    local log_file="${LOG_FILE:-/var/log/ops-scripts.log}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$log_file"
}

# ==================== 错误处理 ====================

# 错误时退出（如果设置了严格模式）
error_exit() {
    print_error "$1"
    exit 1
}

# 设置严格模式
set_strict_mode() {
    set -e  # 遇到错误退出
    set -u  # 使用未定义变量时报错
    set -o pipefail  # 管道中任何错误都会导致整个管道失败
}

# ==================== 其他工具函数 ====================

# 检查是否为 root 用户
is_root() {
    [ "$EUID" -eq 0 ]
}

# 要求 root 权限
require_root() {
    if ! is_root; then
        print_error "此操作需要 root 权限"
        print_info "请使用: sudo $0 $@"
        exit 1
    fi
}

# 数字转单位（字节 -> 可读格式）
# 用法: human_readable 1024 -> "1.00 KB"
human_readable() {
    local bytes=$1
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0

    while [ $bytes -gt 1024 ] && [ $unit -lt 4 ]; do
        bytes=$((bytes / 1024))
        unit=$((unit + 1))
    done

    echo "${bytes} ${units[$unit]}"
}
