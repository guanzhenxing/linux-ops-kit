#!/bin/bash
# ============================================================
# linux-ops-kit 一键引导安装脚本
# ============================================================
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/guanzhenxing/linux-ops-kit/main/bootstrap.sh | sudo bash
#
# 环境变量（可选）:
#   INSTALL_DIR  安装目录，默认 /opt/linux-ops-kit
#   RUN_INIT=1   安装后自动运行 ops.sh init
#   BRANCH       克隆分支，默认 main
#
# 设计参考:
#   Docker get.docker.com / oh-my-zsh install.sh
# ============================================================
set -euo pipefail

# ---------- 配置 ----------
INSTALL_DIR="${INSTALL_DIR:-/opt/linux-ops-kit}"
REPO_URL="https://github.com/guanzhenxing/linux-ops-kit.git"
BRANCH="${BRANCH:-main}"
RUN_INIT="${RUN_INIT:-}"

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$@"; exit 1; }

# ---------- 1. 前置检查 ----------
preflight() {
    # 必须是 root
    if [[ $EUID -ne 0 ]]; then
        die "请使用 root 运行此脚本: curl ... | sudo bash"
    fi

    # 检测操作系统
    if [[ ! -f /etc/os-release ]]; then
        die "无法检测操作系统版本（/etc/os-release 不存在）"
    fi

    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_PRETTY="${PRETTY_NAME:-Linux}"

    info "系统: ${OS_PRETTY}"
}

# ---------- 2. 安装 git ----------
ensure_git() {
    if command -v git &>/dev/null; then
        info "git 已就绪: $(git --version)"
        return 0
    fi

    warn "git 未安装，正在自动安装..."

    case "${OS_ID}" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq git
            ;;
        centos|rhel)
            yum install -y git
            ;;
        almalinux|rocky)
            dnf install -y git
            ;;
        amzn|amazonlinux)
            dnf install -y git
            ;;
        fedora)
            dnf install -y git
            ;;
        *)
            die "不支持的系统: ${OS_ID}，请手动安装 git 后重试"
            ;;
    esac

    if ! command -v git &>/dev/null; then
        die "git 安装失败，请手动安装后重试"
    fi
    info "git 安装完成: $(git --version)"
}

# ---------- 3. 克隆仓库 ----------
clone_repo() {
    if [[ -d "${INSTALL_DIR}/.git" ]]; then
        warn "${INSTALL_DIR} 已存在，正在更新..."
        cd "${INSTALL_DIR}"
        git fetch --depth 1 origin "${BRANCH}" 2>/dev/null || true
        git reset --hard "origin/${BRANCH}" 2>/dev/null || {
            warn "更新失败，将使用现有版本"
        }
    else
        info "正在克隆 linux-ops-kit → ${INSTALL_DIR} ..."
        # 移除可能存在的非 git 目录
        if [[ -d "${INSTALL_DIR}" ]]; then
            warn "目录 ${INSTALL_DIR} 已存在但非 git 仓库，备份后重新克隆"
            mv "${INSTALL_DIR}" "${INSTALL_DIR}.bak.$(date +%s)"
        fi
        git clone --depth 1 -b "${BRANCH}" "${REPO_URL}" "${INSTALL_DIR}"
    fi
}

# ---------- 4. 验证安装 ----------
verify() {
    if [[ ! -f "${INSTALL_DIR}/ops.sh" ]]; then
        die "安装验证失败: ${INSTALL_DIR}/ops.sh 不存在"
    fi
    chmod +x "${INSTALL_DIR}/ops.sh"
    info "✅ 安装验证通过"
}

# ---------- 5. 使用指引 ----------
usage_guide() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}  linux-ops-kit 安装完成！${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "  ${BOLD}服务器初始化（推荐新服务器）:${NC}"
    echo "    sudo ${INSTALL_DIR}/ops.sh init"
    echo ""
    echo -e "  ${BOLD}交互式菜单:${NC}"
    echo "    ${INSTALL_DIR}/ops.sh"
    echo ""
    echo -e "  ${BOLD}设置快捷命令:${NC}"
    echo "    echo \"alias ops='${INSTALL_DIR}/ops.sh'\" >> ~/.bashrc && source ~/.bashrc"
    echo ""
    echo -e "  ${BOLD}更新到最新版:${NC}"
    echo "    cd ${INSTALL_DIR} && git pull"
    echo ""
}

# ---------- 6. 可选: 自动运行 init ----------
maybe_run_init() {
    if [[ "${RUN_INIT}" != "1" ]]; then
        return 0
    fi

    echo ""
    info "RUN_INIT=1，自动启动服务器初始化..."
    echo ""

    # 如果有额外参数（通过 bash -s -- 传入），传递给 init
    exec "${INSTALL_DIR}/ops.sh" init "$@"
}

# ---------- 主流程 ----------
main() {
    echo -e "${BOLD}linux-ops-kit 引导安装${NC}"
    echo ""

    preflight
    ensure_git
    clone_repo
    verify
    usage_guide
    maybe_run_init "$@"
}

main "$@"
