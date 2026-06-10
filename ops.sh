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
VERSION="2.3.0"

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

# ==================== 模块路由 ====================

# 路由到对应模块
route_to_module() {
    local module=$1
    local module_file="${SCRIPT_DIR}/modules/${module}.sh"

    if [ -f "$module_file" ]; then
        bash "$module_file"
    else
        print_warn "${module} 模块开发中..."
        pause
    fi
}

# ==================== 子命令路由 ====================

# 子命令分发
dispatch_subcommand() {
    local cmd="$1"
    shift

    case "$cmd" in
        init)
            local init_file="${SCRIPT_DIR}/modules/init.sh"
            if [ -f "$init_file" ]; then
                bash "$init_file" "$@"
            else
                print_error "init 模块未安装"
                exit 1
            fi
            ;;
        user)
            local user_file="${SCRIPT_DIR}/modules/user.sh"
            if [ -f "$user_file" ]; then
                bash "$user_file" "$@"
            else
                print_error "user 模块未安装"
                exit 1
            fi
            ;;
        security)
            local sec_file="${SCRIPT_DIR}/modules/security-audit.sh"
            if [ -f "$sec_file" ]; then
                bash "$sec_file" "$@"
            else
                print_error "security 模块未安装"
                exit 1
            fi
            ;;
        docker)
            local docker_file="${SCRIPT_DIR}/modules/docker.sh"
            if [ -f "$docker_file" ]; then
                bash "$docker_file" "$@"
            else
                print_error "docker 模块未安装"
                exit 1
            fi
            ;;
        help|--help|-h)
            show_subcommand_help
            ;;
        version|--version|-v)
            echo "linux-ops-kit v${VERSION}"
            ;;
        *)
            # 如果没有子命令，进入交互式菜单
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
            1) route_to_module "check" ;;
            2) route_to_module "service" ;;
            3) route_to_module "log" ;;
            4) route_to_module "network" ;;
            5) route_to_module "disk" ;;
            6) route_to_module "monitor" ;;
            7) route_to_module "install" ;;
            8) route_to_module "help" ;;
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

子命令:
  init        初始化新服务器（交互模式: ./ops.sh init）
  user        用户管理（add/list/del）
  security    安全审计与状态检查（audit/status）
  docker      Docker 管理（status/logs/shell/clean/diagnose/compose/images）

无参数运行进入交互式菜单。

常用示例:
  ./ops.sh init                              # 交互式初始化向导
  ./ops.sh init -u jesen -k github:jesen -d  # 快速初始化
  ./ops.sh user add alice --ssh-key github:alice
  ./ops.sh security status
  ./ops.sh docker status                     # 容器状态总览
  ./ops.sh docker logs                       # 选择容器查看日志
HELPTEXT
}

# 执行主函数
main "$@"
