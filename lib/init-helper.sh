#!/bin/bash
# linux-ops-kit — init 模块辅助函数
# 健康检查、SSH 验证、日志、状态管理、幂等检测

# 依赖
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "${SCRIPT_DIR}/lib/common.sh" 
source "${SCRIPT_DIR}/lib/os-detect.sh" 

# ==================== 路径常量 ====================

INIT_LOG_FILE="${INIT_LOG_FILE:-/var/log/ops-init.log}"
INIT_STATE_FILE="${INIT_STATE_FILE:-/etc/ops-init.state}"
INIT_BACKUP_DIR="${INIT_BACKUP_DIR:-/var/backups/ops-init}"

# ==================== 启动前健康检查 ====================

preflight_check() {
    local pass=true

    print_title "环境健康检查"

    # 磁盘检查
    local avail
    avail=$(df / --output=avail 2>/dev/null | tail -1 | tr -d ' ')
    if [ -n "$avail" ] && [ "$avail" -lt 2000000 ] 2>/dev/null; then
        print_error "磁盘可用空间不足: $(($avail/1024))MB (需要 >= 2GB)"
        print_info  "建议: 清理磁盘空间后重试，或使用 --skip-upgrade 跳过系统更新"
        pass=false
    else
        local disk_info=$(df -h / | tail -1 | awk '{print "总量 "$2", 可用 "$4}')
        print_success "磁盘空间: ${disk_info}"
    fi

    # 内存检查
    local mem
    mem=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}')
    if [ -n "$mem" ]; then
        if [ "$mem" -lt 512 ]; then
            print_warn "内存较低: ${mem}MB。运行 Docker 可能导致系统不稳定"
            print_info  "建议: 跳过 Docker 安装（不传 --docker）"
        else
            local mem_avail=$(free -m | awk '/Mem:/ {print $7}')
            print_success "内存: ${mem}MB 总量, ${mem_avail}MB 可用"
        fi
    fi
    # 网络检查
    # ICMP 可能被某些环境阻断（如 GitHub Actions），
    # 回退到 HTTP 连通性检查
    if ping -c 1 -W 3 8.8.8.8 &>/dev/null || \
       curl -s --connect-timeout 5 https://github.com >/dev/null 2>&1 || \
       wget -q --timeout=5 -O /dev/null https://github.com 2>/dev/null; then
        print_success "网络: 可访问外网"
    else
        print_error "无法访问外网 (ping 和 HTTP 均失败)"
        print_info  "建议: 检查网络配置和 DNS 设置"
        pass=false
    fi

    # 权限检查
    if is_root; then
        print_success "权限: root"
    else
        print_error "需要 root 权限，请使用 sudo 运行"
        pass=false
    fi

    # jq 依赖检查（状态文件读写依赖 jq；本工具的 help 模块也依赖它）
    if command_exists "jq"; then
        print_success "jq: $(jq --version 2>/dev/null)"
    else
        print_error "缺少 jq（init 状态文件读写依赖它）"
        print_info  "建议: apt-get install -y jq 或 dnf install -y jq 后重试"
        pass=false
    fi

    # 包管理器锁检查
    if fuser /var/lib/dpkg/lock-frontend &>/dev/null 2>&1; then
        print_warn "apt 正被其他进程占用（可能正在自动更新）"
        print_info  "等待中（最多 5 分钟）..."
        local waited=0
        while fuser /var/lib/dpkg/lock-frontend &>/dev/null 2>&1 && [ $waited -lt 300 ]; do
            sleep 5
            waited=$((waited + 5))
        done
    fi
    if fuser /var/run/yum.pid &>/dev/null 2>&1; then
        print_warn "yum 正被其他进程占用"
        print_info  "等待中（最多 5 分钟）..."
        local waited=0
        while fuser /var/run/yum.pid &>/dev/null 2>&1 && [ $waited -lt 300 ]; do
            sleep 5
            waited=$((waited + 5))
        done
    fi

    # SSH 会话数检查
    local session_count
    session_count=$(who | wc -l | tr -d ' ')
    if [ "$session_count" -gt 1 ]; then
        print_warn "当前有 ${session_count} 个活跃 SSH 会话:"
        who | while read -r line; do echo "  $line"; done
    fi

    # Docker kernel 检查（CentOS 7）
    if [ "$OS_FAMILY" = "rhel" ] && [ "${OS_VERSION%%.*}" -eq 7 ] 2>/dev/null; then
        local kernel_ver
        kernel_ver=$(uname -r | cut -d- -f1)
        local major minor
        major=$(echo "$kernel_ver" | cut -d. -f1)
        minor=$(echo "$kernel_ver" | cut -d. -f2)
        if [ "$major" -lt 3 ] || ([ "$major" -eq 3 ] && [ "${minor:-0}" -lt 10 ]); then
            print_warn "内核版本 ${kernel_ver} 可能不兼容 Docker CE（需要 >= 3.10）"
        fi
    fi

    [ "$pass" = true ] || return 1
    return 0
}

# ==================== SSH 连接验证 ====================

verify_ssh_access() {
    local user="$1"
    local host="${2:-127.0.0.1}"
    local port="${3:-22}"
    local key_file="${4:-}"
    local timeout=10

    print_info "验证 SSH 登录: ${user}@${host}:${port} ..."

    local key_opt=()
    if [ -n "$key_file" ] && [ -f "$key_file" ]; then
        key_opt=(-i "$key_file")
    fi

    if ssh \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=$timeout \
        -o BatchMode=yes \
        -o PasswordAuthentication=no \
        "${key_opt[@]}" \
        -p "$port" \
        "${user}@${host}" "echo 'SSH_VERIFY_OK'" 2>/dev/null | grep -q "SSH_VERIFY_OK"; then
        print_success "SSH 连接验证成功 — 后路确认通畅"
        return 0
    else
        print_error "SSH 连接验证失败！"
        print_error "原因可能是: SSH Key 未正确导入、权限不正确、或 sshd 配置问题"
        return 1
    fi
}

# SSH 配置回滚
rollback_ssh_config() {
    print_info "回滚 SSH 配置..."

    mkdir -p "$INIT_BACKUP_DIR"

    local backup_file
    backup_file=$(ls -t "${INIT_BACKUP_DIR}/sshd_config.bak."* 2>/dev/null | head -1)

    if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
        # 回滚主配置文件
        if cp "$backup_file" /etc/ssh/sshd_config 2>/dev/null; then
            print_info "已恢复: $backup_file → /etc/ssh/sshd_config"
        fi
        # 同时清理 sshd_config.d 下的加固文件
        rm -f /etc/ssh/sshd_config.d/99-hardening.conf 2>/dev/null
        systemctl restart sshd 2>/dev/null
        print_success "SSH 配置已回滚，服务器保持原状"
    else
        print_warn "未找到 SSH 备份文件，无法自动回滚"
    fi
}

# 防火墙紧急关闭
firewall_panic_off() {
    print_info "紧急关闭防火墙..."
    if command_exists "ufw"; then
        ufw disable 2>/dev/null
        print_info "UFW 已禁用"
    elif command_exists "firewall-cmd"; then
        firewall-cmd --panic-off 2>/dev/null
        print_info "firewalld panic 模式已关闭"
    fi
}

# ==================== 日志与备份 ====================

# 初始化日志
init_log() {
    mkdir -p "$(dirname "$INIT_LOG_FILE")"
    touch "$INIT_LOG_FILE"
}

# 记录操作步骤
log_init_step() {
    local status="$1"  # STEP | OK | FAIL | SKIP | BACKUP
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$status] $message" >> "$INIT_LOG_FILE"
}

# 备份文件
backup_file() {
    local src="$1"
    local timestamp
    timestamp=$(date '+%Y%m%d%H%M%S')
    local dst="${INIT_BACKUP_DIR}/$(basename "$src").bak.${timestamp}"

    if [ -f "$src" ]; then
        mkdir -p "$INIT_BACKUP_DIR"
        cp "$src" "$dst"
        log_init_step "BACKUP" "$src → $dst"
        echo "$dst"
    fi
}

# ==================== 状态管理 ====================

# 写入初始化状态
write_init_state() {
    local step_name="$1"
    local step_status="$2"  # ok | skipped | failed

    mkdir -p "$(dirname "$INIT_STATE_FILE")"

    if [ "$step_name" = "__init__" ]; then
        # 第一次写入，创建完整结构
        cat > "$INIT_STATE_FILE" << STATEFILE
{
  "version": "1",
  "initialized_at": "$(date '+%Y-%m-%dT%H:%M:%S%:z')",
  "ops_version": "${VERSION:-2.0.0}",
  "params": ${INIT_PARAMS:-[]},
  "steps": {}
}
STATEFILE
    else
        # 更新 steps 字段中的某个步骤
        # 用 jq 原子写入，避免 sed 正则在值含特殊字符（/ " & 等）时破坏 JSON 结构
        local tmp
        tmp=$(mktemp)
        if jq --arg k "$step_name" --arg v "$step_status" \
              '.steps[$k] = $v' "$INIT_STATE_FILE" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$INIT_STATE_FILE"
        else
            rm -f "$tmp"
            log_init_step "FAIL" "状态文件更新失败（jq 解析失败）：$step_name"
            return 1
        fi
    fi

    log_init_step "STATE" "$step_name = $step_status"
}

# 读取初始化状态
read_init_state() {
    if [ -f "$INIT_STATE_FILE" ]; then
        cat "$INIT_STATE_FILE"
        return 0
    else
        return 1
    fi
}

# 检查是否已初始化
is_initialized() {
    [ -f "$INIT_STATE_FILE" ]
}

# 显示上次初始化信息
show_init_status() {
    if is_initialized; then
        local init_time
        init_time=$(jq -r '.initialized_at // empty' "$INIT_STATE_FILE" 2>/dev/null)
        if [ -n "$init_time" ]; then
            print_info "服务器已于 ${init_time} 完成初始化"
        else
            print_warn "状态文件存在但格式异常: $INIT_STATE_FILE"
        fi
    else
        print_info "初始化状态: 首次运行"
    fi
}

# ==================== 幂等检测 ====================

# 通用幂等检测
# 用法: if check_idempotent "user_create" "用户 jesen"; then
#           return 0  # 已存在，跳过
#       fi
check_idempotent() {
    local key="$1"
    local desc="$2"

    if is_initialized; then
        if jq -e --arg k "$key" '.steps[$k] == "ok"' "$INIT_STATE_FILE" &>/dev/null; then
            print_result skip "$desc" "已存在，跳过"
            return 0
        fi
    fi
    return 1
}

# 检测用户是否已存在
user_exists() {
    id "$1" &>/dev/null
}

# 检测包是否已安装
pkg_installed() {
    local pkg="$1"
    case "$OS_FAMILY" in
        debian) dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" ;;
        rhel)   rpm -q "$pkg" &>/dev/null ;;
        *)      (dpkg -l "$pkg" 2>/dev/null | grep -q "^ii") || (rpm -q "$pkg" &>/dev/null) || return 1 ;;
    esac
}

# 检测 Docker 是否已安装
docker_installed() {
    command -v docker &>/dev/null && docker --version &>/dev/null
}

# ==================== 系统信息展示 ====================

print_system_info() {
    detect_os_full
    echo -e "检测到系统: ${GREEN}${OS_ID} ${OS_VERSION}${NC} ($(uname -m))"
    echo -e "内核: $(uname -r)"
    echo -e "CPU: $(nproc) 核"

    local mem_total mem_avail
    mem_total=$(free -h 2>/dev/null | awk '/Mem:/ {print $2}')
    mem_avail=$(free -h 2>/dev/null | awk '/Mem:/ {print $7}')
    echo -e "内存: ${mem_total} (可用 ${mem_avail})"

    local disk_info
    disk_info=$(df -h / 2>/dev/null | tail -1 | awk '{print $2" (可用 "$4")"}')
    echo -e "磁盘: $disk_info"

    local ssh_user host
    ssh_user=$(whoami)
    host=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo -e "当前 SSH: ${ssh_user}@${host:-unknown}"

    local session_count
    session_count=$(who | wc -l | tr -d ' ')
    echo -e "活跃会话: ${session_count}"
}

# 初始化日志文件（仅在 Linux 上执行）
if [ "$(uname -s)" = "Linux" ]; then
    init_log
fi
