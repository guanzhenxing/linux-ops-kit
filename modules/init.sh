#!/bin/bash
# ============================================================
# linux-ops-kit — init 模块：主调度器
# ============================================================
# 这是整个 init 系统的核心。它负责：
#
# 1. 参数解析    — 命令行参数、配置文件、默认值的三级优先级加载
# 2. 交互向导    — 无参数运行时引导用户逐步配置（五步流程）
# 3. 执行计划    — 在任何修改前打印完整计划并等待用户确认
# 4. 子模块调度  — 按安全链条顺序调度子模块（详见下方执行顺序注释）
# 5. 结果报告    — init 完成后打印总结，含安全提醒和下一步建议
#
# 执行顺序铁律（安全链条）：
#   第0步: 环境检测（只读）→ 第1步: 系统更新
#   → 第2步: 系统基础配置 → 第3步: 创建用户+SSH Key
#   → 第4步: SSH 登录验证（铁律！确认后路通畅）
#   → 第5步: SSH 加固 → 第6步: 防火墙（含二次 SSH 验证）
#   → 第7步: fail2ban+自动更新 → 第8步: Docker+常用工具
#
# 关键安全设计：
#   - 第4步验证失败 → 自动跳过第5、6步（不能在没有后路的情况下加固）
#   - 第6步执行后 → 再次验证 SSH（防止防火墙误封）
#   - 任何步骤失败 → 不阻塞其余步骤（已成功的保留）
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/os-detect.sh"
source "${SCRIPT_DIR}/lib/init-helper.sh"

source "${SCRIPT_DIR}/modules/init-system.sh"
source "${SCRIPT_DIR}/modules/init-user.sh"
source "${SCRIPT_DIR}/modules/init-security.sh"
source "${SCRIPT_DIR}/modules/init-software.sh"

VERSION="${VERSION:-2.0.0}"

# ==================== 默认值 ====================

DEFAULT_TIMEZONE="Asia/Shanghai"
DEFAULT_SWAP=""
DEFAULT_HOSTNAME=""
DEFAULT_USER=""
DEFAULT_SSH_KEY=""
DEFAULT_DOCKER="no"
DEFAULT_HARDEN_SSH="no"
DEFAULT_FAIL2BAN="no"
DEFAULT_FIREWALL="no"

# ==================== 解析命令行参数 ====================

parse_args() {
    OPTS_TIMEZONE="$DEFAULT_TIMEZONE"
    OPTS_SWAP="$DEFAULT_SWAP"
    OPTS_HOSTNAME="$DEFAULT_HOSTNAME"
    OPTS_USER="$DEFAULT_USER"
    OPTS_SSH_KEY="$DEFAULT_SSH_KEY"
    OPTS_DOCKER="$DEFAULT_DOCKER"
    OPTS_HARDEN_SSH="$DEFAULT_HARDEN_SSH"
    OPTS_FAIL2BAN="$DEFAULT_FAIL2BAN"
    OPTS_FIREWALL="$DEFAULT_FIREWALL"
    OPTS_DRY_RUN="no"
    OPTS_DEFAULTS="no"
    OPTS_FORCE="no"
    OPTS_SKIP_UPGRADE="no"
    OPTS_CONFIG=""
    OPTS_MIRROR=""
    OPTS_ROLLBACK="no"
    OPTS_EXTRA_PORTS=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -t|--timezone)
                OPTS_TIMEZONE="$2"; shift 2 ;;
            -s|--swap)
                OPTS_SWAP="$2"; shift 2 ;;
            -n|--hostname)
                OPTS_HOSTNAME="$2"; shift 2 ;;
            -u|--user)
                OPTS_USER="$2"; shift 2 ;;
            -k|--ssh-key)
                OPTS_SSH_KEY="$2"; shift 2 ;;
            -d|--docker)
                OPTS_DOCKER="yes"; shift ;;
            --harden-ssh)
                OPTS_HARDEN_SSH="yes"; shift ;;
            --fail2ban)
                OPTS_FAIL2BAN="yes"; shift ;;
            --firewall)
                OPTS_FIREWALL="yes"; shift ;;
            --skip-upgrade)
                OPTS_SKIP_UPGRADE="yes"; shift ;;
            --dry-run)
                OPTS_DRY_RUN="yes"; shift ;;
            --defaults)
                OPTS_DEFAULTS="yes"; shift ;;
            --force)
                OPTS_FORCE="yes"; shift ;;
            --config)
                OPTS_CONFIG="$2"; shift 2 ;;
            --mirror)
                OPTS_MIRROR="$2"; shift 2 ;;
            --rollback)
                OPTS_ROLLBACK="yes"; shift ;;
            --extra-ports)
                OPTS_EXTRA_PORTS="$2"; shift 2 ;;
            help)
                show_usage
                exit 0
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "未知参数: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # 加载配置文件
    if [ -n "$OPTS_CONFIG" ] && [ -f "$OPTS_CONFIG" ]; then
        source "$OPTS_CONFIG"
        OPTS_USER="${OPSI_USER:-$OPTS_USER}"
        OPTS_SSH_KEY="${OPSI_SSH_KEY:-$OPTS_SSH_KEY}"
        OPTS_TIMEZONE="${OPSI_TIMEZONE:-$OPTS_TIMEZONE}"
        OPTS_SWAP="${OPSI_SWAP:-$OPTS_SWAP}"
        OPTS_DOCKER="${OPSI_DOCKER:-$OPTS_DOCKER}"
        OPTS_HARDEN_SSH="${OPSI_HARDEN_SSH:-$OPTS_HARDEN_SSH}"
        OPTS_FIREWALL="${OPSI_FIREWALL:-$OPTS_FIREWALL}"
    fi
}

show_usage() {
    cat << 'USAGE'
用法: ./ops.sh init [OPTIONS]

系统配置:
  -t, --timezone ZONE       时区（默认 Asia/Shanghai）
  -s, --swap SIZE           创建 swap（如 2G）
  -n, --hostname NAME      设置 hostname

用户管理:
  -u, --user USERNAME       创建 sudo 用户
  -k, --ssh-key SOURCE      SSH Key（github:USER / gitlab:USER / 路径）

安全加固:
  --harden-ssh              SSH 加固（禁用 root 登录 + 密码认证）
  --fail2ban                fail2ban 入侵防护
  --firewall                配置防火墙
  --lock-root               锁定 root 账户

软件安装:
  -d, --docker              安装 Docker CE + Compose

控制选项:
  --skip-upgrade            跳过系统更新
  --dry-run                 只显示计划，不执行
  --defaults                全默认模式（跳过交互）
  --force                   强制重新初始化
  --config FILE             从配置文件读取参数
  --mirror SOURCE           镜像源（aliyun|tuna|ustc）
  --rollback                回滚上次初始化

示例:
  ./ops.sh init                            # 交互模式
  ./ops.sh init -u jesen -k github:jesen   # 最小命令行
  ./ops.sh init --defaults -u jesen -d     # 全默认模式
USAGE
}

# ==================== 计划阶段 ====================

print_execution_plan() {
    print_plan_header

    print_system_info
    echo ""

    if is_initialized && [ "$OPTS_FORCE" != "yes" ]; then
        show_init_status
        echo ""
    fi

    local step=1
    local total_steps=0

    # 计算总步骤数
    total_steps=2  # 系统更新 + 时区
    [ -n "$OPTS_HOSTNAME" ] && total_steps=$((total_steps + 1))
    [ -n "$OPTS_SWAP" ] && total_steps=$((total_steps + 1))
    total_steps=$((total_steps + 2))  # sysctl + NTP
    [ "$OS_FAMILY" = "rhel" ] && total_steps=$((total_steps + 1))  # EPEL
    [ -n "$OPTS_USER" ] && total_steps=$((total_steps + 2))  # 创建用户 + SSH Key
    [ "$OPTS_HARDEN_SSH" = "yes" ] && total_steps=$((total_steps + 1))
    [ "$OPTS_FIREWALL" = "yes" ] && total_steps=$((total_steps + 1))
    [ "$OPTS_FAIL2BAN" = "yes" ] && total_steps=$((total_steps + 1))
    total_steps=$((total_steps + 1))  # 自动更新
    total_steps=$((total_steps + 1))  # 安全审计
    total_steps=$((total_steps + 1))  # 常用工具
    [ "$OPTS_DOCKER" = "yes" ] && total_steps=$((total_steps + 1))

    echo -e "${BOLD}以下操作将被执行:${NC}\n"

    # 系统配置
    echo -e "  ${BLUE}[系统]${NC}   ${step}. ✓ 系统更新         pkg_update"
    step=$((step + 1))
    echo -e "  ${BLUE}[系统]${NC}   ${step}. ✓ 时区设置         → $OPTS_TIMEZONE"
    step=$((step + 1))
    if [ -n "$OPTS_HOSTNAME" ]; then
        echo -e "  ${BLUE}[系统]${NC}   ${step}. ✓ Hostname         → $OPTS_HOSTNAME"
        step=$((step + 1))
    fi
    if [ -n "$OPTS_SWAP" ]; then
        if swapon --show --noheadings 2>/dev/null | grep -q .; then
            echo -e "  ${BLUE}[系统]${NC}   ${step}. ⊘ Swap             (已有 swap，跳过)"
        else
            echo -e "  ${BLUE}[系统]${NC}   ${step}. ✓ Swap             创建 ${OPTS_SWAP}"
        fi
        step=$((step + 1))
    fi
    echo -e "  ${BLUE}[系统]${NC}   ${step}. ✓ 系统参数调优      nofile=65535, swappiness=10"
    step=$((step + 1))
    echo -e "  ${BLUE}[系统]${NC}   ${step}. ✓ NTP 时间同步      按发行版自动选择"
    step=$((step + 1))
    if [ "$OS_FAMILY" = "rhel" ]; then
        echo -e "  ${BLUE}[系统]${NC}   ${step}. ✓ EPEL 仓库         启用 EPEL + PowerTools"
        step=$((step + 1))
    fi

    # 用户管理
    if [ -n "$OPTS_USER" ]; then
        echo -e "  ${MAGENTA}[用户]${NC}   ${step}. ✓ 创建用户         $OPTS_USER (sudo)"
        step=$((step + 1))
        echo -e "  ${MAGENTA}[用户]${NC}   ${step}. ✓ SSH Key          $OPTS_SSH_KEY"
        step=$((step + 1))
    fi

    # 安全加固
    if [ "$OPTS_HARDEN_SSH" = "yes" ]; then
        echo -e "  ${RED}[安全]${NC}   ${step}. ✓ SSH 加固         禁用 root 登录 + 密码认证"
        step=$((step + 1))
    fi
    if [ "$OPTS_FIREWALL" = "yes" ]; then
        echo -e "  ${RED}[安全]${NC}   ${step}. ✓ 防火墙           UFW/firewalld: 22/80/443"
        step=$((step + 1))
    fi
    if [ "$OPTS_FAIL2BAN" = "yes" ]; then
        echo -e "  ${RED}[安全]${NC}   ${step}. ✓ fail2ban         SSH 3次/1小时"
        step=$((step + 1))
    fi
    echo -e "  ${RED}[安全]${NC}   ${step}. ✓ 自动安全更新      按发行版自动配置"
    step=$((step + 1))
    echo -e "  ${RED}[安全]${NC}   ${step}. ✓ 安全审计          只读检查"
    step=$((step + 1))

    # 软件安装
    echo -e "  ${GREEN}[软件]${NC}   ${step}. ✓ 常用工具         curl wget git jq vim ..."
    step=$((step + 1))
    if [ "$OPTS_DOCKER" = "yes" ]; then
        echo -e "  ${GREEN}[软件]${NC}   ${step}. ✓ Docker CE        + Compose"
    fi

    echo ""
    echo -e "预计耗时: 5-10 分钟（取决于网络速度）"
    echo ""

    if [ "$OPTS_HARDEN_SSH" = "yes" ]; then
        echo -e "${YELLOW}⚠ 重要提醒:${NC}"
        echo -e "  - SSH 加固后，root 将无法直接 SSH 登录"
        echo -e "  - 请确保 SSH Key 导入正确"
        echo -e "  - 脚本会自动验证 SSH 连接，失败将回滚"
        echo ""
    fi
}

# ==================== 交互式向导 ====================

interactive_wizard() {
    clear
    print_title "欢迎使用 linux-ops-kit 服务器初始化向导 v${VERSION}"

    cat << 'INTRO'
本向导将帮助你完成一台新服务器的初始化配置。
全过程约需 5-10 分钟，你可以随时按 Ctrl+C 安全退出。

在开始之前，请确认:
  ✓ 你以 root 身份登录
  ✓ 服务器可以访问互联网
  ✓ 你有一个 GitHub 账号（用于导入 SSH Key，推荐）

INTRO
    pause

    print_separator
    echo -e "${BOLD}第一步 / 共五步: 创建管理员用户${NC}\n"

    OPTS_USER=$(input_with_default "管理员用户名" "admin")

    echo ""
    local key_choice
    key_choice=$(select_option "如何导入 SSH Key?" \
        "从 GitHub 拉取 (推荐)" \
        "从 GitLab 拉取" \
        "手动粘贴公钥" \
        "跳过（稍后手动配置）")

    case "$key_choice" in
        1)
            read -r -p "请输入 GitHub 用户名: " gh_user
            OPTS_SSH_KEY="github:${gh_user}"
            ;;
        2)
            read -r -p "请输入 GitLab 用户名: " gl_user
            OPTS_SSH_KEY="gitlab:${gl_user}"
            ;;
        3)
            echo "请粘贴 SSH 公钥内容（以 ssh-rsa/ssh-ed25519/ecdsa 开头）:"
            read -r OPTS_SSH_KEY
            ;;
        4)
            OPTS_SSH_KEY=""
            ;;
    esac

    print_separator
    echo -e "${BOLD}第二步 / 共五步: 安全加固${NC}\n"

    if confirm_default_yes "启用 SSH 安全加固？"; then
        OPTS_HARDEN_SSH="yes"
        echo "  (将禁用 root SSH 登录和密码认证)"
    fi
    if confirm_default_yes "启用防火墙？"; then
        OPTS_FIREWALL="yes"
        echo "  (UFW/firewalld, 默认允许 SSH/HTTP/HTTPS)"
    fi
    if confirm_default_yes "启用 fail2ban 入侵防护？"; then
        OPTS_FAIL2BAN="yes"
        echo "  (SSH 密码错误 3 次将自动封禁 1 小时)"
    fi

    print_separator
    echo -e "${BOLD}第三步 / 共五步: 软件安装${NC}\n"

    if confirm_default_yes "安装 Docker CE + Docker Compose？"; then
        OPTS_DOCKER="yes"
    fi

    print_separator
    echo -e "${BOLD}第四步 / 共五步: 系统配置${NC}\n"

    OPTS_TIMEZONE=$(input_with_default "时区" "$DEFAULT_TIMEZONE")

    if confirm_yes "创建 Swap 文件？"; then
        OPTS_SWAP=$(input_with_default "Swap 大小" "2G")
    fi

    print_separator
    echo -e "${BOLD}第五步 / 共五步: 确认执行${NC}\n"

    print_execution_plan

    if ! confirm_yes "确认开始执行？"; then
        print_info "已取消初始化"
        exit 0
    fi
}

# ==================== 执行阶段 ====================
#
# 安全链条执行顺序（不可随意调整）：
#   环境检测 → 系统更新 → 系统配置 → 用户创建 → SSH验证 →
#   SSH加固 → 防火墙 → fail2ban → 安全审计 → 软件安装
#
# 核心原则：
#   - "先铺后路再加固"：必须先验证新用户能SSH登录，才关掉密码认证
#   - "防火墙最后开"：先放行SSH端口，再启用防火墙，再验证连接
#   - "软件放最后"：Docker等软件安装失败不影响安全配置

execute_init() {
    local start_time
    start_time=$(date +%s)

    # init 已在计划阶段获得用户确认，子命令自动确认
    OPS_AUTO_CONFIRM=1

    # 写入初始状态
    INIT_PARAMS="[$(echo "\"$*\"" | sed 's/ /", "/g')]"
    write_init_state "__init__" ""

    detect_os_full
    local step=1
    local total=10

    # ---- 第 1 步: 系统更新 ----
    if [ "$OPTS_SKIP_UPGRADE" != "yes" ]; then
        do_system_update "$step" "$total" || true
    else
        print_result skip "系统更新" "跳过 (--skip-upgrade)"
        write_init_state "system_update" "skipped"
    fi
    step=$((step + 1))

    # ---- 第 2 步: 系统基础配置 ----
    do_timezone "$OPTS_TIMEZONE" "$step" "$total"
    step=$((step + 1))

    if [ -n "$OPTS_HOSTNAME" ]; then
        do_hostname "$OPTS_HOSTNAME" "$step" "$total"
        step=$((step + 1))
    fi

    do_swap "$OPTS_SWAP" "$step" "$total"
    step=$((step + 1))
    do_sysctl_tuning "$step" "$total"
    step=$((step + 1))
    do_ntp "$step" "$total"
    step=$((step + 1))
    do_epel "$step" "$total"
    step=$((step + 1))

    # ---- 第 3 步: 创建用户 + SSH Key ----
    if [ -n "$OPTS_USER" ]; then
        do_create_user "$OPTS_USER" "$step" "$total"
        step=$((step + 1))
        do_import_ssh_key "$OPTS_SSH_KEY" "$OPTS_USER" "$step" "$total"
        step=$((step + 1))
    else
        print_result skip "用户管理" "未指定用户，跳过"
        write_init_state "user_create" "skipped"
        write_init_state "ssh_key_import" "skipped"
        step=$((step + 2))
    fi

    # ---- 第 4 步: SSH 加固前验证 ----
    # 铁律：在关闭密码认证之前，必须确认新用户的 SSH Key 能登录。
    # 如果验证失败，整个安全加固链路（SSH加固+防火墙）都会被跳过，
    # 避免把用户锁在服务器外面。
    local ssh_ok=true
    if [ "$OPTS_HARDEN_SSH" = "yes" ] && [ -n "$OPTS_USER" ]; then
        local ssh_port
        ssh_port=$(get_ssh_port)
        if ! verify_ssh_access "$OPTS_USER" "127.0.0.1" "$ssh_port"; then
            print_error "SSH 验证失败，跳过 SSH 加固和防火墙以避免锁死"
            ssh_ok=false
            write_init_state "ssh_harden" "failed"
        fi
    fi

    # ---- 第 5 步: SSH 加固 ----
    if [ "$OPTS_HARDEN_SSH" = "yes" ] && [ "$ssh_ok" = true ]; then
        do_ssh_harden "$OPTS_USER" "$step" "$total" || true
    elif [ "$OPTS_HARDEN_SSH" = "yes" ]; then
        print_result skip "SSH 加固" "跳过（SSH 验证未通过）"
    fi
    step=$((step + 1))

    # ---- 第 6 步: 防火墙 ----
    if [ "$OPTS_FIREWALL" = "yes" ] && [ "$ssh_ok" = true ]; then
        do_firewall "$OPTS_EXTRA_PORTS" "$step" "$total"
    elif [ "$OPTS_FIREWALL" = "yes" ]; then
        print_result skip "防火墙" "跳过（SSH 验证未通过）"
        write_init_state "firewall" "skipped"
    fi
    step=$((step + 1))

    # ---- 第 7 步: fail2ban + 自动更新 ----
    if [ "$OPTS_FAIL2BAN" = "yes" ]; then
        do_fail2ban "$step" "$total"
    else
        print_result skip "fail2ban" "跳过"
        write_init_state "fail2ban" "skipped"
    fi
    step=$((step + 1))
    do_auto_updates "$step" "$total"
    step=$((step + 1))

    # ---- 安全审计 ----
    do_security_audit "$step" "$total"
    step=$((step + 1))

    # ---- 第 8 步: Docker + 常用工具 ----
    do_common_tools "$step" "$total"
    step=$((step + 1))
    if [ "$OPTS_DOCKER" = "yes" ]; then
        do_docker "$OPTS_USER" "$step" "$total" "$OPTS_MIRROR"
    else
        print_result skip "Docker CE" "跳过"
        write_init_state "docker_install" "skipped"
    fi

    # ---- 执行后报告 ----
    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))

    print_report_header
    echo -e "耗时: ${minutes} 分 ${seconds} 秒\n"
    echo -e "${BOLD}结果摘要:${NC}\n"

    # 读取状态文件并打印
    if [ -f "$INIT_STATE_FILE" ]; then
        print_state_summary
    fi

    echo ""
    echo -e "${YELLOW}⚠ 安全提醒:${NC}"
    if [ "$OPTS_HARDEN_SSH" = "yes" ] && [ "$ssh_ok" = true ]; then
        echo -e "  - root 已无法通过 SSH 直接登录"
        echo -e "  - 请用新用户登录: ${GREEN}ssh ${OPTS_USER}@<服务器IP>${NC}"
        echo -e "  - 使用 ${GREEN}sudo${NC} 执行管理命令"
    fi
    echo -e "\n${BOLD}📋 日志文件:${NC} $INIT_LOG_FILE"
    echo -e "${BOLD}📋 状态文件:${NC} $INIT_STATE_FILE"
    echo -e "\n${BOLD}下一步建议:${NC}"
    if [ -n "$OPTS_USER" ]; then
        echo -e "  - 测试 SSH 登录: ${GREEN}ssh ${OPTS_USER}@<服务器IP>${NC}"
    fi
    if [ "$OPTS_DOCKER" = "yes" ]; then
        echo -e "  - 测试 Docker:    ${GREEN}docker run --rm hello-world${NC}"
    fi
    echo -e "  - 安全状态:       ${GREEN}./ops.sh security status${NC}"
    echo -e "  - 添加其他用户:   ${GREEN}./ops.sh user add <name> --ssh-key github:<name>${NC}"
    echo ""
}

# 打印状态摘要
print_state_summary() {
    local steps
    steps=$(grep -oE '"[^"]+": "[^"]+"' "$INIT_STATE_FILE" 2>/dev/null | grep -v '"version"\|"initialized_at"\|"ops_version"')

    local labels
    declare -A labels=(
        ["system_update"]="系统更新"
        ["timezone"]="时区设置"
        ["swap"]="Swap"
        ["sysctl_tuning"]="系统参数调优"
        ["ntp"]="NTP 时间同步"
        ["epel"]="EPEL 仓库"
        ["user_create"]="创建用户"
        ["ssh_key_import"]="SSH Key"
        ["ssh_harden"]="SSH 加固"
        ["firewall"]="防火墙"
        ["fail2ban"]="fail2ban"
        ["auto_updates"]="自动安全更新"
        ["security_audit"]="安全审计"
        ["common_tools"]="常用工具"
        ["docker_install"]="Docker CE"
    )

    local i=1
    while IFS= read -r line; do
        local key="${line%%\":*}"
        local val="${line##*\": \"}"
        key="${key#\"}"
        val="${val%\"}"

        local label="${labels[$key]:-$key}"
        case "$val" in
            ok)
                echo -e "  ${GREEN}✓${NC}  $i. $label"
                ;;
            skipped)
                echo -e "  ${YELLOW}⊘${NC}  $i. $label (跳过)"
                ;;
            failed)
                echo -e "  ${RED}✗${NC}  $i. $label (失败)"
                ;;
        esac
        i=$((i + 1))
    done <<< "$steps"
}

# ==================== Dry-run 模式 ====================

do_dry_run() {
    print_execution_plan
    echo -e "${BLUE}--dry-run 模式: 不执行任何修改${NC}"
}

# ==================== Rollback 模式 ====================

do_rollback() {
    print_title "回滚上次初始化"

    if [ ! -f "$INIT_LOG_FILE" ]; then
        print_error "未找到操作日志: $INIT_LOG_FILE"
        print_info  "没有可回滚的操作"
        exit 1
    fi

    print_info "读取操作日志: $INIT_LOG_FILE"

    local backups
    backups=$(grep "BACKUP" "$INIT_LOG_FILE" 2>/dev/null | tac)

    if [ -z "$backups" ]; then
        print_info "没有可回滚的备份操作"
        exit 0
    fi

    echo "$backups" | while IFS= read -r line; do
        local src dst
        src=$(echo "$line" | grep -oP '(?<=BACKUP\] ).*(?= →)' 2>/dev/null || echo "$line" | sed 's/.*\] //' | sed 's/ →.*//')
        dst=$(echo "$line" | grep -oP '(?<=→ ).*' 2>/dev/null || echo "")
        if [ -f "$dst" ] && [ -n "$src" ]; then
            cp "$dst" "$src" 2>/dev/null && print_info "已恢复: $src"
        fi
    done

    rm -f "$INIT_STATE_FILE"
    print_success "回滚完成"
}

# ==================== 主入口 ====================

main_init() {
    # 解析参数
    parse_args "$@"

    # 加载配置优先级: 命令行 > ~/.ops-init.conf > data/init-defaults.conf
    local user_conf="${HOME}/.ops-init.conf"
    local default_conf="${SCRIPT_DIR}/data/init-defaults.conf"

    if [ -n "$OPTS_CONFIG" ] && [ -f "$OPTS_CONFIG" ]; then
        source "$OPTS_CONFIG"
    elif [ -f "$user_conf" ]; then
        source "$user_conf"
    elif [ -f "$default_conf" ]; then
        source "$default_conf"
    fi

    # Rollback 模式
    if [ "$OPTS_ROLLBACK" = "yes" ]; then
        do_rollback
        exit $?
    fi

    # Dry-run 模式
    if [ "$OPTS_DRY_RUN" = "yes" ]; then
        do_dry_run
        exit 0
    fi

    # 检查是否已初始化
    if is_initialized && [ "$OPTS_FORCE" != "yes" ]; then
        print_warn "服务器已完成初始化"
        show_init_status
        print_info "如需重新初始化，请使用 --force"
        exit 0
    fi

    # 启动前健康检查
    preflight_check || {
        print_error "环境检查未通过，退出"
        exit 1
    }

    # 交互模式（无参数或仅指定用户时进入）
    if [ "$OPTS_DEFAULTS" != "yes" ]; then
        local has_interactive_args=false
        # 如果用户指定了任何关键参数，跳过交互
        if [ "$OPTS_DOCKER" != "no" ] || [ "$OPTS_HARDEN_SSH" != "no" ] || \
           [ "$OPTS_FAIL2BAN" != "no" ] || [ "$OPTS_FIREWALL" != "no" ]; then
            has_interactive_args=true
        fi

        if [ "$has_interactive_args" = false ]; then
            # 没有显式指定关键参数 → 进入交互模式
            interactive_wizard
        fi
    fi

    # 执行前计划
    print_execution_plan
    if ! confirm_yes "是否继续？"; then
        print_info "已取消初始化"
        exit 0
    fi

    # 执行初始化
    execute_init "$@"
}

# 如果直接运行此脚本
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main_init "$@"
fi
