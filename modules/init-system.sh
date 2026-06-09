#!/bin/bash
# linux-ops-kit — init 模块：系统基础配置
# 时区、hostname、swap、sysctl 调优、NTP、EPEL

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/os-detect.sh"
source "${SCRIPT_DIR}/lib/init-helper.sh"

# ==================== 系统更新 ====================

do_system_update() {
    local step_num=$1
    local total=$2
    print_step "$step_num" "$total" "系统更新"
    if pkg_update; then
        log_init_step "OK" "系统更新完成"
        write_init_state "system_update" "ok"
        return 0
    else
        log_init_step "FAIL" "系统更新失败"
        write_init_state "system_update" "failed"
        return 1
    fi
}

# ==================== 时区设置 ====================

do_timezone() {
    local tz="${1:-Asia/Shanghai}"
    local step_num=$2
    local total=$3
    print_step "$step_num" "$total" "时区设置"

    if command_exists "timedatectl"; then
        if run_cmd "设置时区: $tz" "timedatectl set-timezone '$tz'"; then
            print_result ok "时区设置" "→ $tz"
            log_init_step "OK" "时区设置为 $tz"
            write_init_state "timezone" "ok"
            return 0
        fi
    fi

    # fallback: 手动链接
    if [ -f "/usr/share/zoneinfo/$tz" ]; then
        run_cmd "设置时区 (fallback): $tz" "ln -sf '/usr/share/zoneinfo/$tz' /etc/localtime"
        print_result ok "时区设置" "→ $tz"
        log_init_step "OK" "时区设置为 $tz (手动)"
        write_init_state "timezone" "ok"
        return 0
    fi

    print_result fail "时区设置" "无效时区: $tz"
    write_init_state "timezone" "failed"
    return 1
}

# ==================== Hostname 设置 ====================

do_hostname() {
    local hostname="$1"
    local step_num=$2
    local total=$3
    print_step "$step_num" "$total" "Hostname 设置"

    local current
    current=$(hostname)

    if [ -z "$hostname" ]; then
        print_result skip "Hostname" "未指定，保持 $current"
        write_init_state "hostname" "skipped"
        return 0
    fi

    if [ "$hostname" = "$current" ]; then
        print_result skip "Hostname" "已是 $hostname"
        write_init_state "hostname" "skipped"
        return 0
    fi

    if command_exists "hostnamectl"; then
        run_cmd "设置 hostname: $hostname" "hostnamectl set-hostname '$hostname'"
    else
        run_cmd "设置 hostname (fallback): $hostname" "echo '$hostname' > /etc/hostname && hostname '$hostname'"
    fi

    print_result ok "Hostname" "→ $hostname"
    log_init_step "OK" "hostname 设置为 $hostname"
    write_init_state "hostname" "ok"
    return 0
}

# ==================== Swap 创建 ====================

do_swap() {
    local size="$1"
    local step_num=$2
    local total=$3
    print_step "$step_num" "$total" "Swap 创建"

    if [ -z "$size" ]; then
        print_result skip "Swap" "未指定大小"
        write_init_state "swap" "skipped"
        return 0
    fi

    # 检测已有 swap
    local current_swap
    current_swap=$(swapon --show --noheadings 2>/dev/null | wc -l | tr -d ' ')
    if [ "$current_swap" -gt 0 ]; then
        local swap_info
        swap_info=$(swapon --show --noheadings 2>/dev/null | awk '{print $3}' | head -1)
        print_result skip "Swap" "已存在 ${swap_info} swap，跳过"
        write_init_state "swap" "skipped"
        return 0
    fi

    # 解析大小
    local size_bytes
    size_bytes=$(echo "$size" | sed 's/G/*1024*1024*1024/;s/M/*1024*1024/;s/K/*1024/' | bc 2>/dev/null)
    if [ -z "$size_bytes" ]; then
        size_bytes=$((2*1024*1024*1024))  # 默认 2G
    fi

    # 检查磁盘空间
    local avail
    avail=$(df / --output=avail 2>/dev/null | tail -1 | tr -d ' ')
    local required=$((size_bytes / 1024 * 3 / 2))  # × 1.5 安全系数
    if [ "$avail" -lt "$required" ] 2>/dev/null; then
        print_result fail "Swap" "磁盘空间不足"
        write_init_state "swap" "failed"
        return 1
    fi

    # 选择 swapfile 路径
    local swapfile="/swapfile"
    if stat -f / 2>/dev/null | grep -q "Type: btrfs"; then
        mkdir -p /swap
        swapfile="/swap/swapfile"
        chattr +C /swap 2>/dev/null || true
    fi

    # 创建 swapfile
    local count=$((size_bytes / 1024))
    if run_cmd "创建 ${size} swapfile: $swapfile" "dd if=/dev/zero of='$swapfile' bs=1024 count=$count && chmod 600 '$swapfile' && mkswap '$swapfile' && swapon '$swapfile'"; then

        # 写入 fstab
        if ! grep -q "$swapfile" /etc/fstab; then
            echo "$swapfile none swap sw 0 0" >> /etc/fstab
        fi

        print_result ok "Swap" "已创建 ${size} swapfile → $swapfile"
        log_init_step "OK" "swap 创建: $swapfile ($size)"
        write_init_state "swap" "ok"
        return 0
    else
        print_result fail "Swap" "创建 swapfile 失败"
        write_init_state "swap" "failed"
        return 1
    fi
}

# ==================== 系统参数调优 ====================

do_sysctl_tuning() {
    local step_num=$1
    local total=$2
    print_step "$step_num" "$total" "系统参数调优"

    # ulimit 配置
    local limits_file="/etc/security/limits.conf"
    if [ -f "$limits_file" ]; then
        backup_file "$limits_file"
        for limit in "nofile" "nproc"; do
            if ! grep -q "^*\s*${limit}\s*65535" "$limits_file" 2>/dev/null; then
                echo "*    ${limit}    65535" >> "$limits_file"
            fi
        done
    fi

    # sysctl 配置
    local sysctl_file="/etc/sysctl.d/99-ops-tuning.conf"
    cat > "$sysctl_file" << 'SYSCTL'
# linux-ops-kit 系统调优
vm.swappiness = 10
net.core.somaxconn = 1024
net.ipv4.tcp_fastopen = 3
fs.inotify.max_user_watches = 524288
SYSCTL
    run_cmd "应用 sysctl 调优" "sysctl -p '$sysctl_file'"

    print_result ok "系统参数调优" "$sysctl_file"
    log_init_step "OK" "sysctl + ulimit 调优"
    write_init_state "sysctl_tuning" "ok"
    return 0
}

# ==================== NTP 时间同步 ====================

do_ntp() {
    local step_num=$1
    local total=$2
    print_step "$step_num" "$total" "NTP 时间同步"

    # 检测当前 NTP 状态
    if timedatectl status 2>/dev/null | grep -q "NTP service: active"; then
        print_result skip "NTP" "systemd-timesyncd 已运行"
        write_init_state "ntp" "skipped"
        return 0
    fi

    if systemctl is-active chronyd &>/dev/null 2>&1; then
        print_result skip "NTP" "chronyd 已运行"
        write_init_state "ntp" "skipped"
        return 0
    fi

    # 按发行版安装
    case "$OS_FAMILY" in
        debian)
            case "$OS_ID" in
                ubuntu)
                    # Ubuntu 22.04+ 默认用 systemd-timesyncd
                    if systemctl is-enabled systemd-timesyncd &>/dev/null 2>&1; then
                        systemctl start systemd-timesyncd 2>/dev/null
                        print_result ok "NTP" "systemd-timesyncd 已启用"
                    else
                        pkg_install "chrony"
                        svc_manage "chrony" enable-now
                        print_result ok "NTP" "chrony 已安装并启用"
                    fi
                    ;;
                *)
                    # Debian: 优先 chrony
                    if pkg_install --skip-missing "chrony" && systemctl start chrony 2>/dev/null; then
                        svc_manage "chrony" enable
                        print_result ok "NTP" "chrony 已安装并启用"
                    else
                        systemctl start systemd-timesyncd 2>/dev/null
                        print_result ok "NTP" "systemd-timesyncd 已启用"
                    fi
                    ;;
            esac
            ;;
        rhel)
            case "$OS_ID" in
                centos)
                    if [ "${OS_VERSION%%.*}" -eq 7 ] 2>/dev/null; then
                        pkg_install "chrony"
                        svc_manage "chrony" enable-now
                    else
                        # Alma/Rocky 8+ chrony 默认已安装
                        svc_manage "chrony" enable-now 2>/dev/null || true
                    fi
                    ;;
                *)
                    svc_manage "chrony" enable-now 2>/dev/null || true
                    ;;
            esac
            print_result ok "NTP" "chrony 已启用"
            ;;
    esac

    log_init_step "OK" "NTP 时间同步配置完成"
    write_init_state "ntp" "ok"
    return 0
}

# ==================== EPEL/PowerTools 仓库 ====================

do_epel() {
    local step_num=$1
    local total=$2

    if [ "$OS_FAMILY" != "rhel" ]; then
        return 0
    fi

    print_step "$step_num" "$total" "EPEL/PowerTools 仓库"

    if pkg_installed "epel-release"; then
        print_result skip "EPEL" "已安装"
        write_init_state "epel" "skipped"
        return 0
    fi

    # 安装 EPEL
    case "$OS_ID" in
        centos)
            if [ "${OS_VERSION%%.*}" -eq 7 ] 2>/dev/null; then
                pkg_install --skip-missing "epel-release"
            else
                pkg_install --skip-missing "epel-release"
                # 启用 PowerTools/CRB
                dnf config-manager --set-enabled powertools 2>/dev/null || \
                dnf config-manager --set-enabled crb 2>/dev/null || true
            fi
            ;;
        almalinux|rocky)
            pkg_install --skip-missing "epel-release"
            dnf config-manager --set-enabled crb 2>/dev/null || true
            ;;
    esac

    print_result ok "EPEL" "已启用 EPEL + PowerTools/CRB"
    log_init_step "OK" "EPEL/PowerTools 仓库已启用"
    write_init_state "epel" "ok"
    return 0
}

# ==================== 模块入口 ====================

run_init_system() {
    local step_num=${1:-1}
    local total=${2:-10}
    local timezone="${3:-Asia/Shanghai}"
    local hostname="${4:-}"
    local swap="${5:-}"

    do_system_update "$step_num" "$total" || true
    step_num=$((step_num + 1))
    do_timezone "$timezone" "$step_num" "$total"
    step_num=$((step_num + 1))

    if [ -n "$hostname" ]; then
        do_hostname "$hostname" "$step_num" "$total"
        step_num=$((step_num + 1))
    fi

    do_swap "$swap" "$step_num" "$total"
    step_num=$((step_num + 1))
    do_sysctl_tuning "$step_num" "$total"
    step_num=$((step_num + 1))
    do_ntp "$step_num" "$total"
    step_num=$((step_num + 1))
    do_epel "$step_num" "$total"
}
