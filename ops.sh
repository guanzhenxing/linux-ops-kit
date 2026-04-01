#!/bin/bash
# Linux 运维工具箱 - 主入口
# 统一交互式菜单，不需要记任何命令

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载核心函数库
source "${SCRIPT_DIR}/lib/common.sh"

# 版本信息
VERSION="2.0.0"

# ==================== 主菜单 ====================

show_main_menu() {
    clear
    print_title "=== Linux 运维工具箱 v${VERSION} ==="

    cat << 'EOF'
1. 系统检查      - CPU/内存/磁盘/服务健康检查
2. 服务管理      - 启动/停止/重启/查看服务
3. 日志查看      - 快速查看各服务日志
4. 网络诊断      - 端口/连通性/抓包
5. 磁盘管理      - 空间检查/清理/挂载
6. 监控告警      - 设置监控阈值/告警
7. 快捷安装      - Nginx/Docker/SSL证书
8. 命令帮助      - 搜索/查看 Linux 命令说明
0. 退出

EOF
}

# ==================== 模块路由 ====================

# 路由到对应模块
route_to_module() {
    local module=$1
    local module_file="${SCRIPT_DIR}/modules/${module}.sh"

    if [ -f "$module_file" ]; then
        # 模块存在，执行
        bash "$module_file"
    else
        # 模块不存在或开发中
        print_warn "${module} 模块开发中..."
        pause
    fi
}

# ==================== 主循环 ====================

main() {
    # 检查依赖
    if [ ! -f "${SCRIPT_DIR}/lib/common.sh" ]; then
        echo "错误: 找不到核心函数库 lib/common.sh"
        exit 1
    fi

    # 主菜单循环
    while true; do
        show_main_menu
        read -p "请选择 [0-8]: " choice

        case $choice in
            1) route_to_module "check" ;;
            2) route_to_module "service" ;;
            3) route_to_module "log" ;;
            4) route_to_module "network" ;;
            5) route_to_module "disk" ;;
            6) route_to_module "monitor" ;;
            7) route_to_module "install" ;;
            8) route_to_module "help" ;;
            0)
                print_info "退出运维工具箱"
                exit 0
                ;;
            *)
                print_error "无效选择，请输入 0-8"
                sleep 1
                ;;
        esac
    done
}

# 执行主函数
main "$@"
