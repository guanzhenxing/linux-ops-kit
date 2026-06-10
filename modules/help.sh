#!/bin/bash
set -uo pipefail
# 命令帮助模块

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

DATA_FILE="${SCRIPT_DIR}/../data/data.json"
DATA_URL="https://raw.githubusercontent.com/jaywcjlove/linux-command/master/dist/data.json"
MD_BASE_URL="https://raw.githubusercontent.com/jaywcjlove/linux-command/master/command"

# ==================== 依赖检查 ====================

check_jq() {
    if command_exists jq; then
        return 0
    fi

    print_warn "此模块需要 jq 工具来解析 JSON 数据"
    read -r -p "是否现在安装 jq? [y/N]: " install_jq

    if [ "$install_jq" = "y" ] || [ "$install_jq" = "Y" ]; then
        local os_type=$(detect_os)
        print_info "正在安装 jq..."

        case $os_type in
            ubuntu|debian)
                apt-get update -qq && apt-get install -y -qq jq
                ;;
            centos|rhel)
                yum install -y -q jq 2>/dev/null || dnf install -y -q jq 2>/dev/null
                ;;
            *)
                print_error "不支持的系统，请手动安装 jq"
                return 1
                ;;
        esac

        if command_exists jq; then
            print_success "jq 安装成功!"
            return 0
        else
            print_error "jq 安装失败，请手动安装后重试"
            return 1
        fi
    else
        print_error "缺少 jq 依赖，无法使用此模块"
        pause
        return 1
    fi
}

# ==================== 1. 搜索命令 ====================

search_command() {
    clear
    print_title "=== 搜索命令 ==="

    read -r -p "输入命令名或关键词: " keyword

    if [ -z "$keyword" ]; then
        print_warn "请输入关键词"
        pause
        return
    fi

    clear
    print_title "=== 搜索结果: $keyword ==="

    jq -r --arg kw "$keyword" '
        to_entries[] |
        select(.key | contains($kw)) |
        "\(.key)\t\(.value.d)"
    ' "$DATA_FILE" 2>/dev/null | head -20 | column -t -s $'\t'

    if [ $(jq -r --arg kw "$keyword" 'to_entries[] | select(.key | contains($kw))' "$DATA_FILE" 2>/dev/null | wc -l) -eq 0 ]; then
        print_warn "未找到匹配的命令"
        echo ""
        pause
        return
    fi

    echo ""
    echo -e "${CYAN}输入命令名查看详情，或按 b 返回:${NC}"
    read -r -p "请选择: " cmd_choice

    if [ "$cmd_choice" = "b" ] || [ "$cmd_choice" = "B" ]; then
        return
    fi

    if [ -n "$cmd_choice" ]; then
        show_command_detail_direct "$cmd_choice"
    fi
}

# ==================== 2. 列出所有命令 ====================

list_all_commands() {
    clear
    print_title "=== 所有命令 ($(jq 'length' "$DATA_FILE" 2>/dev/null || echo "N/A") 个) ==="

    # 显示命令列表
    jq -r 'keys[]' "$DATA_FILE" 2>/dev/null | pr -a -t -4 -w 120

    echo ""
    echo -e "${CYAN}输入命令名查看详情，或按 b 返回:${NC}"
    read -r -p "请选择: " cmd_choice

    if [ "$cmd_choice" = "b" ] || [ "$cmd_choice" = "B" ]; then
        return
    fi

    if [ -n "$cmd_choice" ]; then
        show_command_detail_direct "$cmd_choice"
    fi
}

# ==================== 3. 命令详情（实时获取 MD） ====================

# 直接显示命令详情（用于从搜索结果调用）
show_command_detail_direct() {
    local cmd=$1

    # 检查命令是否存在
    if ! jq -e ".[\"$cmd\"]" "$DATA_FILE" &>/dev/null; then
        print_error "未找到命令: $cmd"
        pause
        return
    fi

    print_info "正在获取 $cmd 的详细说明..."

    # 获取 MD 内容
    local md_url="${MD_BASE_URL}/${cmd}.md"
    local md_content=$(curl -s "$md_url" 2>/dev/null)

    if [ -z "$md_content" ]; then
        print_error "获取失败，请检查网络连接"
        pause
        return
    fi

    clear
    print_title "=== 命令详情: $cmd ==="

    # 使用 less 显示 MD 内容
    echo "$md_content" | less

    echo ""
    echo -e "${CYAN}在线文档:${NC} https://wangchujiang.com/linux-command/c/$cmd.html"
    echo ""
}

show_command_detail() {
    clear
    print_title "=== 命令详情 ==="

    read -r -p "输入命令名: " cmd

    if [ -z "$cmd" ]; then
        print_warn "请输入命令名"
        pause
        return
    fi

    # 检查命令是否存在
    if ! jq -e ".[\"$cmd\"]" "$DATA_FILE" &>/dev/null; then
        print_error "未找到命令: $cmd"
        pause
        return
    fi

    print_info "正在获取 $cmd 的详细说明..."

    # 获取 MD 内容
    local md_url="${MD_BASE_URL}/${cmd}.md"
    local md_content=$(curl -s "$md_url" 2>/dev/null)

    if [ -z "$md_content" ]; then
        print_error "获取失败，请检查网络连接"
        pause
        return
    fi

    clear
    print_title "=== 命令详情: $cmd ==="

    # 使用 less 显示 MD 内容
    echo "$md_content" | less

    echo ""
    echo -e "${CYAN}在线文档:${NC} https://wangchujiang.com/linux-command/c/$cmd.html"
    echo ""
    pause
}

# ==================== 4. 更新数据 ====================

update_data() {
    clear
    print_title "=== 更新命令数据 ==="

    echo ""
    read -r -p "确认更新? [y/N]: " confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        return
    fi

    print_info "正在下载最新数据..."

    mkdir -p "$(dirname "$DATA_FILE")"

    if command_exists wget; then
        wget -O "$DATA_FILE" "$DATA_URL" --show-progress
    elif command_exists curl; then
        curl -o "$DATA_FILE" "$DATA_URL" --progress-bar
    else
        print_error "需要 wget 或 curl 命令"
        pause
        return
    fi

    if [ $? -eq 0 ]; then
        local cmd_count=$(jq 'length' "$DATA_FILE" 2>/dev/null || echo "N/A")
        print_success "更新完成! 共 $cmd_count 个命令"
    else
        print_error "下载失败"
    fi

    echo ""
    pause
}


# ==================== 子命令帮助 ====================

show_help_help() {
    cat << 'HELP'
用法: ./ops.sh help <子命令> [参数]

子命令:
  search <关键词>   搜索命令
  list              列出所有命令
  detail <命令名>   查看命令详情
  update            更新命令数据
  help              显示此帮助

无子命令运行进入交互式菜单。

示例:
  ./ops.sh help search rsync
  ./ops.sh help list
  ./ops.sh help detail ls
HELP
}

# ==================== 交互式菜单 ====================

help_interactive_menu() {
    while true; do
        clear
        print_title "=== Linux 命令帮助 ==="
        echo ""
        echo "1. 搜索命令"
        echo "2. 列出所有命令"
        echo "3. 命令详情"
        echo "4. 更新数据"
        echo "b. 返回主菜单"
        echo ""

        read -r -p "请选择 [1-4/b]: " choice

        case $choice in
            1) search_command ;;
            2) list_all_commands ;;
            3) show_command_detail ;;
            4) update_data ;;
            b|B) return 0 ;;
            *)
                print_error "无效选择"
                sleep 1
                ;;
        esac
    done
}

# ==================== 主入口 ====================

main_help() {
    # 依赖检查
    if ! check_jq; then
        return 1
    fi
    if [ ! -f "$DATA_FILE" ]; then
        print_warn "数据文件不存在，请先更新数据"
        pause
        update_data
    fi

    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        search|find|grep)
            search_command
            ;;
        list|all|ls)
            list_all_commands
            ;;
        detail|show|man)
            if [ -n "$1" ]; then
                show_command_detail_direct "$1"
            else
                show_command_detail
            fi
            ;;
        update|download)
            update_data
            ;;
        help|--help)
            show_help_help
            ;;
        "")
            help_interactive_menu
            ;;
        *)
            print_error "未知子命令: $subcmd"
            show_help_help
            exit 1
            ;;
    esac
}

main_help "$@"
