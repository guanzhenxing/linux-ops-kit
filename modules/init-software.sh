#!/bin/bash
# linux-ops-kit — init 模块：软件安装
# 常用工具、Docker CE + Compose

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/os-detect.sh"
source "${SCRIPT_DIR}/lib/init-helper.sh"

# ==================== 常用工具 ====================

do_common_tools() {
    local step_num=$1
    local total=$2
    print_step "$step_num" "$total" "常用工具"

    pkg_install --skip-missing "curl wget git jq vim unzip bash-completion"

    # btop 比 htop 更现代，但两者都尝试安装
    if ! pkg_install --skip-missing "btop" 2>/dev/null; then
        pkg_install --skip-missing "htop"
    fi

    print_result ok "常用工具" "curl wget git jq vim unzip bash-completion btop/htop"
    log_init_step "OK" "常用工具安装完成"
    write_init_state "common_tools" "ok"
    return 0
}

# ==================== Docker CE + Compose ====================

do_docker() {
    local username="$1"
    local step_num=$2
    local total=$3
    local mirror="${4:-}"

    print_step "$step_num" "$total" "Docker CE + Compose"

    # 幂等检测
    if docker_installed; then
        local docker_ver
        docker_ver=$(docker --version 2>/dev/null)
        print_result skip "Docker CE" "已安装 ($docker_ver)"
        write_init_state "docker_install" "skipped"
        return 0
    fi

    # 清理旧版本
    case "$OS_FAMILY" in
        debian)
            apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
            ;;
        rhel)
            yum remove -y docker docker-client docker-common docker-latest 2>/dev/null || true
            dnf remove -y docker docker-client docker-common 2>/dev/null || true
            ;;
    esac

    # 安装依赖
    case "$OS_FAMILY" in
        debian)
            apt-get update -qq
            apt-get install -y ca-certificates curl gnupg 2>/dev/null
            ;;
        rhel)
            pkg_install --skip-missing "yum-utils device-mapper-persistent-data lvm2"
            ;;
    esac

    # 添加 Docker 官方源
    local docker_repo_base="https://download.docker.com"
    case "$mirror" in
        aliyun) docker_repo_base="https://mirrors.aliyun.com/docker-ce" ;;
        tuna)   docker_repo_base="https://mirrors.tuna.tsinghua.edu.cn/docker-ce" ;;
        ustc)   docker_repo_base="https://mirrors.ustc.edu.cn/docker-ce" ;;
    esac

    case "$OS_FAMILY" in
        debian)
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL "${docker_repo_base}/linux/${OS_ID}/gpg" 2>/dev/null | \
                gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
            chmod a+r /etc/apt/keyrings/docker.gpg

            local arch
            arch=$(dpkg --print-architecture)
            local codename
            codename=$( (. /etc/os-release && echo "$VERSION_CODENAME") 2>/dev/null || echo "stable")

            echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.gpg] ${docker_repo_base}/linux/${OS_ID} ${codename} stable" \
                > /etc/apt/sources.list.d/docker.list
            apt-get update -qq
            apt-get install -y docker-ce docker-ce-cli containerd.io 2>/dev/null
            ;;
        rhel)
            local repo_url="${docker_repo_base}/linux/centos/docker-ce.repo"
            yum-config-manager --add-repo "$repo_url" 2>/dev/null || \
            dnf config-manager --add-repo "$repo_url" 2>/dev/null
            pkg_install --skip-missing "docker-ce docker-ce-cli containerd.io"
            ;;
    esac

    if ! docker_installed; then
        print_result fail "Docker CE" "安装失败 — 请检查日志 /var/log/ops-init.log"
        print_info "常见原因:"
        print_info "  1. Docker 官方源在国内访问较慢 → 尝试: ./ops.sh init --mirror aliyun"
        print_info "  2. GPG Key 验证失败 → 检查系统时间: date"
        print_info "  3. 旧版本残留 → 手动清理: apt remove docker docker-engine"
        write_init_state "docker_install" "failed"
        return 1
    fi

    # Docker Compose
    if ! docker compose version &>/dev/null 2>&1; then
        # 尝试安装 plugin
        case "$OS_FAMILY" in
            debian)
                apt-get install -y docker-compose-plugin 2>/dev/null || true
                ;;
            rhel)
                pkg_install --skip-missing "docker-compose-plugin" 2>/dev/null || true
                ;;
        esac

        # fallback: standalone binary
        if ! docker compose version &>/dev/null 2>&1; then
            print_info "docker-compose-plugin 不可用，安装 standalone binary..."
            local compose_url="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
            if [ -n "$mirror" ]; then
                # 使用国内镜像加速
                compose_url="https://ghproxy.com/${compose_url}"
            fi
            curl -SL "$compose_url" -o /usr/local/bin/docker-compose 2>/dev/null && \
                chmod +x /usr/local/bin/docker-compose
        fi
    fi

    # Docker 配置
    mkdir -p /etc/docker
    if [ ! -f /etc/docker/daemon.json ]; then
        cat > /etc/docker/daemon.json << 'DOCKERCONF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DOCKERCONF
    fi

    # 用户加入 docker 组
    if [ -n "$username" ] && user_exists "$username"; then
        usermod -aG docker "$username" 2>/dev/null
    fi

    # 启动 Docker
    svc_manage "docker" enable-now 2>/dev/null

    local docker_ver compose_ver
    docker_ver=$(docker --version 2>/dev/null || echo "未知")
    compose_ver=$(docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || echo "未知")

    print_result ok "Docker CE" "${docker_ver} + ${compose_ver}"
    log_init_step "OK" "Docker CE 安装完成: $docker_ver"
    write_init_state "docker_install" "ok"
    return 0
}

# ==================== 模块入口 ====================

run_init_software() {
    local step_num=${1:-1}
    local total=${2:-10}
    local username="${3:-}"
    local docker_enabled="${4:-no}"
    local mirror="${5:-}"

    do_common_tools "$step_num" "$total"
    step_num=$((step_num + 1))

    if [ "$docker_enabled" = "yes" ]; then
        do_docker "$username" "$step_num" "$total" "$mirror"
    else
        print_result skip "Docker CE" "跳过"
        write_init_state "docker_install" "skipped"
    fi
}
