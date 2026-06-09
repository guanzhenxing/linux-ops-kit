#!/bin/bash
# linux-ops-kit — 发行版检测与包管理抽象层
# 所有跨发行版兼容逻辑集中于此

# ==================== 发行版检测 ====================

# 扩展的发行版检测，导出 OS_ID、OS_VERSION、OS_FAMILY
detect_os_full() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
        OS_VERSION="${VERSION_ID:-unknown}"

        # 根据 ID_LIKE 判断家族
        if echo "${ID_LIKE:-}" | grep -qi "debian"; then
            OS_FAMILY="debian"
        elif echo "${ID_LIKE:-}" | grep -qi "rhel\|fedora"; then
            OS_FAMILY="rhel"
        elif echo "$OS_ID" | grep -qiE "^(ubuntu|debian)$"; then
            OS_FAMILY="debian"
        elif echo "$OS_ID" | grep -qiE "^(centos|almalinux|rocky|fedora|rhel|amazon)$"; then
            OS_FAMILY="rhel"
        else
            OS_FAMILY="unknown"
        fi
    elif [ -f /etc/redhat-release ]; then
        OS_ID="centos"
        OS_VERSION=$(rpm -q --qf "%{VERSION}" centos-release 2>/dev/null || echo "unknown")
        OS_FAMILY="rhel"
    elif [ -f /etc/debian_version ]; then
        OS_ID="debian"
        OS_VERSION=$(cat /etc/debian_version)
        OS_FAMILY="debian"
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
        OS_FAMILY="unknown"
    fi

    export OS_ID OS_VERSION OS_FAMILY
}

# 向后兼容：保留原有的 detect_os（简单版）
detect_os() {
    detect_os_full
    echo "$OS_ID"
}

# ==================== 包管理器抽象 ====================

# 获取包管理器类型和命令
# 用法: eval $(get_pkg_manager)
# 导出: PKG_MGR, PKG_INSTALL_CMD, PKG_UPDATE_CMD, PKG_CACHE_CMD
get_pkg_manager() {
    detect_os_full

    case "$OS_FAMILY" in
        debian)
            PKG_MGR="apt"
            PKG_INSTALL_CMD="apt-get install -y"
            PKG_UPDATE_CMD="apt-get update && apt-get upgrade -y"
            PKG_CACHE_CMD="apt-get update"
            ;;
        rhel)
            case "$OS_ID" in
                centos)
                    if [ "${OS_VERSION%%.*}" -eq 7 ] 2>/dev/null; then
                        PKG_MGR="yum"
                        PKG_INSTALL_CMD="yum install -y"
                        PKG_UPDATE_CMD="yum update -y"
                        PKG_CACHE_CMD="yum makecache"
                    else
                        PKG_MGR="dnf"
                        PKG_INSTALL_CMD="dnf install -y"
                        PKG_UPDATE_CMD="dnf upgrade -y"
                        PKG_CACHE_CMD="dnf makecache"
                    fi
                    ;;
                fedora)
                    PKG_MGR="dnf"
                    PKG_INSTALL_CMD="dnf install -y"
                    PKG_UPDATE_CMD="dnf upgrade -y"
                    PKG_CACHE_CMD="dnf makecache"
                    ;;
                *)
                    # AlmaLinux, Rocky, Amazon Linux 等
                    if command -v dnf &>/dev/null; then
                        PKG_MGR="dnf"
                        PKG_INSTALL_CMD="dnf install -y"
                        PKG_UPDATE_CMD="dnf upgrade -y"
                        PKG_CACHE_CMD="dnf makecache"
                    else
                        PKG_MGR="yum"
                        PKG_INSTALL_CMD="yum install -y"
                        PKG_UPDATE_CMD="yum update -y"
                        PKG_CACHE_CMD="yum makecache"
                    fi
                    ;;
            esac
            ;;
        *)
            print_error "不支持的操作系统: ${OS_ID} (${OS_FAMILY})"
            PKG_MGR="unknown"
            PKG_INSTALL_CMD=""
            PKG_UPDATE_CMD=""
            PKG_CACHE_CMD=""
            ;;
    esac

    export PKG_MGR PKG_INSTALL_CMD PKG_UPDATE_CMD PKG_CACHE_CMD
}

# 缓存刷新时间戳文件
PKG_CACHE_TIMESTAMP="/tmp/.ops-kit-pkg-cache-ts"

# 刷新包管理器缓存（24 小时内不重复）
pkg_refresh_cache() {
    local now=$(date +%s)
    local last=0
    [ -f "$PKG_CACHE_TIMESTAMP" ] && last=$(cat "$PKG_CACHE_TIMESTAMP")

    if [ $((now - last)) -ge 86400 ]; then
        get_pkg_manager
        print_info "刷新包管理器缓存..."
        if [ -n "$PKG_CACHE_CMD" ]; then
            eval "$PKG_CACHE_CMD" 2>&1 | while IFS= read -r line; do :; done
        fi
        echo "$now" > "$PKG_CACHE_TIMESTAMP"
    fi
}

# 统一包安装函数
# 用法: pkg_install --strict "curl wget git"
#       pkg_install --skip-missing "htop btop"
pkg_install() {
    local mode="--strict"
    local packages=""

    # 解析模式参数
    case "$1" in
        --strict|--skip-missing)
            mode="$1"
            packages="$2"
            ;;
        *)
            packages="$1"
            ;;
    esac

    [ -z "$packages" ] && return 0

    get_pkg_manager
    pkg_refresh_cache

    local failed=""
    local installed=""
    local skipped=""

    for pkg in $packages; do
        print_info "安装: $pkg"

        if eval "$PKG_INSTALL_CMD $pkg" 2>/dev/null; then
            installed="${installed} $pkg"
            log_action "[pkg_install] OK: $pkg"
        else
            if [ "$mode" = "--skip-missing" ]; then
                print_warn "跳过不可用的包: $pkg"
                skipped="${skipped} $pkg"
                log_action "[pkg_install] SKIP: $pkg (not available)"
            else
                print_error "安装失败: $pkg"
                failed="${failed} $pkg"
                log_action "[pkg_install] FAIL: $pkg"
            fi
        fi
    done

    [ -n "$installed" ] && print_success "已安装:${installed}"
    [ -n "$skipped" ]    && print_warn "已跳过:${skipped}"
    [ -n "$failed" ]     && print_error "安装失败:${failed}"

    # --strict 模式：有失败则返回非零
    if [ "$mode" = "--strict" ] && [ -n "$failed" ]; then
        return 1
    fi
    return 0
}

# 统一系统更新
# 用法: pkg_update
pkg_update() {
    get_pkg_manager
    print_step 1 1 "系统更新 ($PKG_MGR)"
    if eval "$PKG_UPDATE_CMD"; then
        print_result ok "系统更新" "完成"
        return 0
    else
        print_result fail "系统更新" "$PKG_MGR 更新失败"
        return 1
    fi
}

# ==================== 服务管理抽象 ====================

# 统一服务管理
# 用法: svc_manage "nginx" enable
#       svc_manage "nginx" start
#       svc_manage "nginx" restart
#       svc_manage "nginx" status
svc_manage() {
    local service="$1"
    local action="$2"

    if has_systemd; then
        case "$action" in
            enable)  systemctl enable "$service" 2>/dev/null ;;
            disable) systemctl disable "$service" 2>/dev/null ;;
            start)   systemctl start "$service" 2>/dev/null ;;
            stop)    systemctl stop "$service" 2>/dev/null ;;
            restart) systemctl restart "$service" 2>/dev/null ;;
            status)  systemctl is-active "$service" 2>/dev/null ;;
            enable-now) systemctl enable --now "$service" 2>/dev/null ;;
            *)       systemctl "$action" "$service" 2>/dev/null ;;
        esac
    else
        # sysvinit 兜底（当前目标发行版均使用 systemd，预留给未来兼容）
        case "$action" in
            enable)  chkconfig "$service" on 2>/dev/null ;;
            disable) chkconfig "$service" off 2>/dev/null ;;
            start)   service "$service" start 2>/dev/null ;;
            stop)    service "$service" stop 2>/dev/null ;;
            restart) service "$service" restart 2>/dev/null ;;
            status)  service "$service" status 2>/dev/null ;;
            *)       service "$service" "$action" 2>/dev/null ;;
        esac
    fi
}

# ==================== 发行版信息获取 ====================

# 获取当前 SSH 端口
get_ssh_port() {
    local port
    port=$(grep -E "^Port\s+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    echo "${port:-22}"
}

# 获取 SSH 配置目录策略
get_ssh_config_dir() {
    if [ -d /etc/ssh/sshd_config.d ]; then
        echo "sshd_config.d"
    else
        # CentOS 7: 尝试创建并添加 Include
        if grep -q "^Include.*sshd_config.d" /etc/ssh/sshd_config 2>/dev/null; then
            mkdir -p /etc/ssh/sshd_config.d 2>/dev/null
            echo "sshd_config.d"
        else
            echo "direct"
        fi
    fi
}

# 获取 sudo 组名
get_sudo_group() {
    case "$OS_FAMILY" in
        debian) echo "sudo" ;;
        rhel)   echo "wheel" ;;
        *)      echo "sudo" ;;
    esac
}

# ==================== 初始化入口 ====================

# 首次被 source 时自动运行发行版检测
detect_os_full
