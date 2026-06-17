#!/bin/bash
# ============================================================
# Linux 运维工具箱 - 主入口
# ============================================================
# 两种使用方式：
#   1. 子命令模式: ./ops.sh init -u jesen -k github:jesen
#   2. 交互菜单模式: ./ops.sh（无参数运行）
#
# 子命令路由：
#   init      → modules/init.sh（服务器初始化，最核心）
#   user      → modules/user.sh（Day 2 用户管理）
#   security  → modules/security-audit.sh（Day 2 安全审计）
#   docker    → modules/docker.sh（Day 2 Docker 管理）
#
# 无参数运行 → 交互式菜单 → 各模块独立脚本
#
# 设计原则：
#   - 子命令和交互菜单共享同一套模块文件
#   - ops.sh 只做路由，不包含业务逻辑
#   - 新模块只需在 dispatch_subcommand 中添加 case 分支
# ============================================================

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载核心函数库
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/os-detect.sh"

# 版本信息
source "${SCRIPT_DIR}/lib/version.sh"
VERSION="2.4.0"
# ==================== 主菜单 ====================

show_main_menu() {
    clear
    print_title "=== Linux 运维工具箱 v${VERSION} ==="

    cat << 'EOF'
 0. 服务器初始化  - 🆕 新服务器一条命令从 0 到可用
 1. 系统检查      - CPU/内存/磁盘/服务健康检查
 2. 服务管理      - 启动/停止/重启/查看服务
 3. 日志查看      - 快速查看各服务日志
 4. 网络诊断      - 端口/连通性/抓包
 5. 磁盘管理      - 空间检查/清理/挂载
 6. 监控告警      - 设置监控阈值/告警
 7. 快捷安装      - Nginx/Docker/SSL证书
 8. 命令帮助      - 搜索/查看 Linux 命令说明
 9. Docker 管理    - 容器/镜像/Compose 管理
 00. 退出

EOF
}

# ==================== 统一模块路由（透传参数） ====================

run_module() {
    local module_file="${SCRIPT_DIR}/modules/${1}.sh"
    shift
    if [ -f "$module_file" ]; then
        bash "$module_file" "$@"
    else
        print_warn "${1} 模块开发中..."
        pause
    fi
}

# ==================== 子命令路由 ====================

# 子命令分发
dispatch_subcommand() {
    local cmd="$1"
    shift
    [ $# -eq 0 ] && set -- ""

    case "$cmd" in
        init)        run_module "init" "$@" ;;
        check)       run_module "check" "$@" ;;
        service)     run_module "service" "$@" ;;
        log)         run_module "log" "$@" ;;
        network)     run_module "network" "$@" ;;
        disk)        run_module "disk" "$@" ;;
        monitor)     run_module "monitor" "$@" ;;
        install)     run_module "install" "$@" ;;
        help)        run_module "help" "$@" ;;
        user)        run_module "user" "$@" ;;
        security)    run_module "security-audit" "$@" ;;
        docker)      run_module "docker" "$@" ;;
        --help|-h)
            show_subcommand_help
            ;;
        version|--version|-v)
            echo "linux-ops-kit v${VERSION}"
            ;;
        "")
            main_menu
            ;;
        *)
            main_menu
            ;;
    esac
}


# ==================== 交互式菜单 ====================

main_menu() {
    # 检查依赖
    if [ ! -f "${SCRIPT_DIR}/lib/common.sh" ]; then
        echo "错误: 找不到核心函数库 lib/common.sh"
        exit 1
    fi

    # 主菜单循环
    while true; do
        show_main_menu
        read -r -p "请选择 [0-9 / 00 退出]: " choice

        case $choice in
            0) dispatch_subcommand "init" ;;
            1) dispatch_subcommand "check" ;;
            2) dispatch_subcommand "service" ;;
            3) dispatch_subcommand "log" ;;
            4) dispatch_subcommand "network" ;;
            5) dispatch_subcommand "disk" ;;
            6) dispatch_subcommand "monitor" ;;
            7) dispatch_subcommand "install" ;;
            8) dispatch_subcommand "help" ;;
            9) dispatch_subcommand "docker" ;;
            00)
                print_info "退出运维工具箱"
                exit 0
                ;;
            *)
                print_error "无效选择，请输入 0-9"
                sleep 1
                ;;
        esac
    done
}

# ==================== 主入口 ====================

main() {
    # 有子命令参数时走子命令路由
    if [ $# -gt 0 ]; then
        dispatch_subcommand "$@"
    else
        main_menu
    fi
}

# 替换帮助中的版本号
show_subcommand_help() {
    cat << HELPTEXT
linux-ops-kit v${VERSION} — Linux 运维工具箱

所有模块均支持两种使用方式：
  ./ops.sh <模块>           → 进入交互式菜单
  ./ops.sh <模块> <子命令>   → 直接执行

模块列表:
  init        服务器初始化
  check       系统检查（all/system/cpu/mem/disk/service）
  service     服务管理（overview/status <name>/start/stop/restart/disable/enable）
  log         日志查看（system/service/follow/search）
  network     网络诊断（port/iface/dns/ping/traceroute/firewall）
  disk        磁盘管理（usage/find-large/clean/mount/lvm/inode）
  monitor     监控告警（dashboard/check/report）
  install     快捷安装（nginx/docker/nodejs/mysql/redis/ssl/lnmp 等）
  help        命令帮助（search/list/detail/update）
  user        用户管理（add/list/del）
  security    安全审计与状态检查（audit/status）
  docker      Docker 管理（ps/logs/exec/prune/diagnose/compose/image/save/load/export/import）

无参数运行进入交互式菜单。
HELPTEXT
}

# 执行主函数
main "$@"
