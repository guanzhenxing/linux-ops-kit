#!/bin/bash
set -uo pipefail
# ============================================================
# linux-ops-kit — Day 2 操作：Docker 管理
# ============================================================
# 提供容器/镜像/Compose 的日常管理能力：
#   - status:  容器状态总览（运行/停止/资源占用）
#   - logs:    选择容器，查看/跟踪日志
#   - shell:   选择容器，进入 Shell
#   - clean:   清理 Docker 资源（带确认）
#   - diagnose: Docker 健康检查（daemon/端口/重启/OOM）
#   - compose: Compose 服务管理（状态/重启/重建）
#   - images:  镜像空间分析
#
# 无子命令运行 → 交互式菜单
#
# 依赖：lib/common.sh（UX 输出）、lib/os-detect.sh（发行版检测）
# 注意：Docker 安装由 modules/install.sh 负责，本模块不涉及安装
# ============================================================

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/os-detect.sh"

# ==================== 守卫函数 ====================

# 检查 Docker 是否可用（已安装 + daemon 运行中）
check_docker() {
    if ! command_exists docker; then
        print_error "Docker 未安装"
        print_info "安装方法:"
        print_info "  菜单: ./ops.sh → 选 7 (快捷安装) → 选 Docker"
        print_info "  子命令: ./ops.sh install → 选 Docker"
        exit 1
    fi
    if ! docker info &>/dev/null; then
        print_error "Docker daemon 未运行"
        print_info "启动: sudo systemctl start docker"
        exit 1
    fi
}

# ==================== 帮助信息 ====================

show_docker_help() {
    cat << 'HELP'
用法: ./ops.sh docker <子命令> [参数]

子命令:
  status (ps)    容器状态总览（运行/停止/资源占用）
  logs           选择容器，查看/跟踪日志
  shell          选择容器，进入 Shell
  clean          清理 Docker 资源（带确认）
  diagnose       Docker 健康检查
  compose        Compose 服务管理
  images         镜像空间分析
  help           显示此帮助

无子命令运行进入交互式菜单。

示例:
  ./ops.sh docker status       # 查看所有容器状态
  ./ops.sh docker logs         # 选择容器查看日志
  ./ops.sh docker shell        # 选择容器进入 Shell
  ./ops.sh docker clean        # 清理 Docker 资源
  ./ops.sh docker diagnose     # Docker 健康检查
  ./ops.sh docker compose      # Compose 项目管理
  ./ops.sh docker images       # 镜像空间分析
HELP
}

# ==================== 辅助函数 ====================

# 选择容器（交互式）
# 参数: --all 包含停止的容器 | 默认仅运行中容器
# 输出: 容器名（echo）
select_container() {
    local filter="--filter status=running"
    if [ "${1:-}" = "--all" ]; then
        filter=""
    fi

    local containers
    containers=$(docker ps ${filter:+"$filter"} --format '{{.Names}}' 2>/dev/null)

    if [ -z "$containers" ]; then
        if [ "${1:-}" = "--all" ]; then
            print_error "没有任何容器"
        else
            print_error "没有运行中的容器"
        fi
        return 1
    fi

    local container_list=()
    while IFS= read -r name; do
        container_list+=("$name")
    done <<< "$containers"

    # 只有一个容器时自动选择
    if [ ${#container_list[@]} -eq 1 ]; then
        echo "${container_list[0]}"
        return 0
    fi

    local prompt="选择容器"
    [ "${1:-}" = "--all" ] && prompt="选择容器（含已停止）"

    echo -e "\n${CYAN}${prompt}:${NC}"
    for i in "${!container_list[@]}"; do
        local idx=$((i+1))
        local name="${container_list[$i]}"
        local status
        status=$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || echo "unknown")
        if [ "$status" = "running" ]; then
            echo "  $idx. ${GREEN}${name}${NC} (运行中)"
        else
            echo "  $idx. ${name} (${status})"
        fi
    done

    while true; do
        read -r -p "请选择 [1-${#container_list[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#container_list[@]}" ]; then
            echo "${container_list[$((choice-1))]}"
            return 0
        fi
        print_error "无效选择，请输入 1-${#container_list[@]}"
    done
}

# 检测 compose 命令（V2 插件或独立版）
detect_compose_cmd() {
    if docker compose version &>/dev/null 2>&1; then
        echo "docker compose"
    elif command_exists docker-compose; then
        echo "docker-compose"
    else
        echo ""
    fi
}

# 发现 compose 项目文件
# 搜索: 当前目录、/opt/*、/home/*、/root
find_compose_files() {
    local compose_files=()

    # 当前目录
    for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        [ -f "$f" ] && compose_files+=("$(pwd)/$f")
    done

    # /opt 子目录（一层）
    for dir in /opt/*/; do
        [ -d "$dir" ] || continue
        for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
            [ -f "${dir}${f}" ] && compose_files+=("${dir}${f}")
        done
    done

    # /home 子目录（一层）
    for dir in /home/*/; do
        [ -d "$dir" ] || continue
        for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
            [ -f "${dir}${f}" ] && compose_files+=("${dir}${f}")
        done
    done

    # /root
    for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        [ -f "/root/${f}" ] && compose_files+=("/root/${f}")
    done

    if [ ${#compose_files[@]} -eq 0 ]; then
        return 1
    fi

    printf '%s\n' "${compose_files[@]}"
}

# ==================== P0: 容器状态总览 ====================

do_docker_status() {
    clear
    print_title "=== 容器状态总览 ==="

    local total running stopped
    total=$(docker ps -a -q 2>/dev/null | wc -l | tr -d ' ')
    running=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
    stopped=$((total - running))

    if [ "$total" -eq 0 ]; then
        print_info "没有任何容器"
        echo ""
        pause
        return 0
    fi

    # 概览
    echo -e "${BOLD}容器概览:${NC}  ${GREEN}${running} 运行中${NC}  ${RED}${stopped} 已停止${NC}  共 ${total} 个"
    echo ""

    # 容器列表
    echo -e "${BOLD}名称                镜像                状态               端口${NC}"
    echo "──────────────────────────────────────────────────────────────────────"

    docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | \
    while IFS=$'\t' read -r name image status ports; do
        # 截断过长的字段
        [ ${#name} -gt 18 ] && name="${name:0:15}..."
        [ ${#image} -gt 18 ] && image="${image:0:15}..."
        [ ${#status} -gt 18 ] && status="${status:0:15}..."
        [ ${#ports} -gt 20 ] && ports="${ports:0:17}..."

        if echo "$status" | grep -q "Up"; then
            printf "  ${GREEN}%-18s${NC} %-18s ${GREEN}%-18s${NC} %s\n" "$name" "$image" "$status" "$ports"
        else
            printf "  ${RED}%-18s${NC} %-18s ${RED}%-18s${NC} %s\n" "$name" "$image" "$status" "$ports"
        fi
    done

    # 运行中容器的资源占用
    if [ "$running" -gt 0 ]; then
        echo ""
        echo -e "${BOLD}资源占用 (运行中):${NC}"
        echo ""
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null | \
        head -20
    fi

    echo ""
    pause
}

# ==================== P0: 查看容器日志 ====================

do_docker_logs() {
    clear
    print_title "=== 容器日志 ==="

    local container
    container=$(select_container) || return 1

    local lines="${1:-100}"
    echo ""
    print_info "显示 ${container} 最近 ${lines} 行日志 (Ctrl+C 退出)"
    echo ""

    show_cmd "查看日志: $container" "docker logs -f --tail $lines '$container'"
}

# ==================== P0: 进入容器 Shell ====================

do_docker_shell() {
    clear
    print_title "=== 进入容器 Shell ==="

    local container
    container=$(select_container) || return 1

    # 检测可用 shell
    local shell="/bin/sh"
    if docker exec "$container" test -x /bin/bash 2>/dev/null; then
        shell="/bin/bash"
    fi

    echo ""
    print_info "进入容器 ${GREEN}${container}${NC} (${shell})"
    print_info "输入 exit 退出"
    echo ""

    docker exec -it "$container" "$shell"

    echo ""
    pause
}

# ==================== P0: 清理 Docker 资源 ====================

do_docker_clean() {
    clear
    print_title "=== Docker 资源清理 ==="

    # 显示当前占用
    echo -e "${BOLD}当前 Docker 磁盘占用:${NC}"
    echo ""
    docker system df 2>/dev/null
    echo ""

    cat << 'EOF'
清理选项:
 1. 基本清理    — 停止的容器 + 悬空镜像 + 未使用的网络
 2. 镜像清理    — 清理所有未使用的镜像（不仅是悬空的）
 3. 卷清理      — 清理未使用的卷
 4. 全部清理    — 以上全部
 0. 返回

EOF

    read -r -p "请选择 [0-4]: " choice

    local before after
    before=$(docker system df 2>/dev/null | grep "Total" | awk '{print $3}' || echo "未知")

    case $choice in
        1)
            run_cmd "清理停止的容器 + 悬空镜像 + 未使用网络" "docker system prune -f"
            ;;
        2)
            run_cmd "清理所有未使用镜像" "docker image prune -a -f"
            ;;
        3)
            run_cmd "清理未使用的卷" "docker volume prune -f"
            ;;
        4)
            run_cmd "全量清理 Docker 资源" "docker system prune -a --volumes -f"
            ;;
        0) return ;;
        *)
            print_error "无效选择"
            sleep 1
            return
            ;;
    esac

    echo ""
    after=$(docker system df 2>/dev/null | grep "Total" | awk '{print $3}' || echo "未知")
    print_success "清理完成: $before → $after"

    echo ""
    echo -e "${BOLD}清理后占用:${NC}"
    echo ""
    docker system df 2>/dev/null

    echo ""
    pause
}

# ==================== P1: Docker 诊断 ====================

do_docker_diagnose() {
    clear
    print_title "=== Docker 诊断 ==="

    local has_issue=0

    # 1. Docker 版本与存储驱动
    echo -e "${BOLD}Docker 信息:${NC}"
    local docker_ver storage_driver root_dir
    docker_ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "未知")
    storage_driver=$(docker info --format '{{.Driver}}' 2>/dev/null || echo "未知")
    root_dir=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
    echo -e "  ${GREEN}✓${NC} 版本: ${CYAN}${docker_ver}${NC}  存储驱动: ${CYAN}${storage_driver}${NC}"
    echo -e "  ${GREEN}✓${NC} 数据目录: ${CYAN}${root_dir}${NC}"

    # 2. 磁盘空间
    echo ""
    echo -e "${BOLD}磁盘使用:${NC}"
    local docker_disk
    docker_disk=$(docker system df --format '{{.Size}}' 2>/dev/null | head -1 || echo "未知")
    echo -e "  ${GREEN}✓${NC} Docker 占用: ${CYAN}${docker_disk}${NC}"

    local root_usage
    root_usage=$(df -h "$root_dir" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
    if [ -n "$root_usage" ] && [ "$root_usage" -ge 90 ]; then
        echo -e "  ${RED}✗${NC} 数据目录磁盘使用 ${RED}${root_usage}%${NC} — 空间不足"
        has_issue=1
    elif [ -n "$root_usage" ] && [ "$root_usage" -ge 80 ]; then
        echo -e "  ${YELLOW}⚠${NC} 数据目录磁盘使用 ${YELLOW}${root_usage}%${NC}"
    else
        echo -e "  ${GREEN}✓${NC} 数据目录磁盘使用正常 ($root_usage%)"
    fi

    # 3. 容器重启检查
    echo ""
    echo -e "${BOLD}容器重启检查:${NC}"
    local restart_issues=0
    while IFS=$'\t' read -r name restarts status; do
        if [ "$restarts" -gt 5 ] 2>/dev/null; then
            echo -e "  ${RED}✗${NC} ${name} — 重启 ${RED}${restarts} 次${NC} (${status})"
            has_issue=1
            restart_issues=1
        fi
    done < <(docker ps -a --format '{{.Names}}\t{{.RestartCount}}\t{{.Status}}' 2>/dev/null)
    if [ "$restart_issues" -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} 无异常重启的容器"
    fi

    # 4. OOM 检查
    echo ""
    echo -e "${BOLD}OOM 检查:${NC}"
    local oom_found=0
    while IFS=$'\t' read -r name oom; do
        if [ "$oom" = "true" ]; then
            echo -e "  ${RED}✗${NC} ${name} — ${RED}曾被 OOM Kill${NC}"
            has_issue=1
            oom_found=1
        fi
    done < <(docker ps -a --format '{{.Names}}\t{{.State.OOMKilled}}' 2>/dev/null)
    if [ "$oom_found" -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} 无 OOM 记录"
    fi

    # 5. 健康检查
    echo ""
    echo -e "${BOLD}健康检查:${NC}"
    local unhealthy_found=0
    while IFS=$'\t' read -r name health; do
        if [ "$health" = "unhealthy" ]; then
            echo -e "  ${RED}✗${NC} ${name} — ${RED}不健康${NC}"
            has_issue=1
            unhealthy_found=1
        fi
    done < <(docker ps --format '{{.Names}}\t{{.State.Health.Status}}' 2>/dev/null | grep -v "^\s*$")
    if [ "$unhealthy_found" -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} 所有容器健康"
    fi

    # 6. 日志文件大小
    echo ""
    echo -e "${BOLD}日志文件:${NC}"
    local log_size
    log_size=$(du -sh /var/lib/docker/containers/ 2>/dev/null | awk '{print $1}' || echo "未知")
    echo -e "  ${GREEN}✓${NC} 容器日志总大小: ${CYAN}${log_size}${NC}"

    # 总结
    echo ""
    if [ "$has_issue" -eq 0 ]; then
        print_success "Docker 状态正常，未发现问题"
    else
        print_warn "发现上述问题，建议进一步排查"
    fi

    echo ""
    pause
}

# ==================== P1: Compose 管理 ====================

do_docker_compose() {
    clear
    print_title "=== Compose 管理 ==="

    # 检测 compose 命令
    local compose_cmd
    compose_cmd=$(detect_compose_cmd)
    if [ -z "$compose_cmd" ]; then
        print_error "未找到 docker compose 或 docker-compose 命令"
        print_info "安装: ./ops.sh install → 选 Docker"
        echo ""
        pause
        return 1
    fi

    # 发现 compose 项目
    local compose_files
    compose_files=$(find_compose_files)
    if [ -z "$compose_files" ]; then
        print_error "未找到 docker-compose.yml / compose.yml"
        print_info "搜索范围: 当前目录、/opt/*、/home/*、/root"
        echo ""
        pause
        return 1
    fi

    # 选择项目
    local file_list=()
    while IFS= read -r f; do
        file_list+=("$f")
    done <<< "$compose_files"

    local compose_file
    if [ ${#file_list[@]} -eq 1 ]; then
        compose_file="${file_list[0]}"
        print_info "找到项目: $compose_file"
    else
        echo -e "\n${CYAN}发现 ${#file_list[@]} 个 Compose 项目:${NC}"
        for i in "${!file_list[@]}"; do
            local idx=$((i+1))
            local dir
            dir=$(dirname "${file_list[$i]}")
            echo "  $idx. ${file_list[$i]}"
            # 显示项目运行状态
            local running=0
            running=$($compose_cmd -f "${file_list[$i]}" ps -q 2>/dev/null | wc -l | tr -d ' ')
            echo "       ${CYAN}${running} 个运行中的服务${NC}"
        done
        echo ""
        read -r -p "请选择 [1-${#file_list[@]}]: " choice
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#file_list[@]}" ]; then
            print_error "无效选择"
            return 1
        fi
        compose_file="${file_list[$((choice-1))]}"
    fi

    # 项目子菜单
    compose_project_menu "$compose_file" "$compose_cmd"
}

compose_project_menu() {
    local compose_file="$1"
    local compose_cmd="$2"
    local project_dir
    project_dir=$(dirname "$compose_file")

    while true; do
        clear
        print_title "=== Compose: $compose_file ==="

        # 显示服务状态
        echo -e "${BOLD}服务状态:${NC}"
        echo ""
        cd "$project_dir" || return 1
        show_cmd "查看服务状态" "$compose_cmd -f '$compose_file' ps"
        echo ""

        cat << 'EOF'
操作:
 1. 查看服务日志
 2. 重启某个服务
 3. 重建某个服务
 4. 重启所有服务
 0. 返回

EOF

        read -r -p "请选择 [0-4]: " choice

        case $choice in
            1)
                # 选择服务查看日志
                local services
                services=$($compose_cmd -f "$compose_file" config --services 2>/dev/null)
                if [ -z "$services" ]; then
                    print_error "无法读取服务列表"
                    sleep 1
                    continue
                fi

                local svc_list=()
                while IFS= read -r svc; do
                    svc_list+=("$svc")
                done <<< "$services"

                echo ""
                for i in "${!svc_list[@]}"; do
                    echo "  $((i+1)). ${svc_list[$i]}"
                done
                echo ""
                read -r -p "选择服务 [1-${#svc_list[@]}]: " svc_choice

                if [[ "$svc_choice" =~ ^[0-9]+$ ]] && [ "$svc_choice" -ge 1 ] && [ "$svc_choice" -le "${#svc_list[@]}" ]; then
                    local svc="${svc_list[$((svc_choice-1))]}"
                    echo ""
                    print_info "显示 ${svc} 日志 (Ctrl+C 退出)"
                    echo ""
                    show_cmd "查看日志: $svc" "$compose_cmd -f '$compose_file' logs -f --tail 100 '$svc'"
                fi
                ;;
            2)
                # 选择服务重启
                local services
                services=$($compose_cmd -f "$compose_file" config --services 2>/dev/null)
                if [ -z "$services" ]; then
                    print_error "无法读取服务列表"
                    sleep 1
                    continue
                fi

                local svc_list=()
                while IFS= read -r svc; do
                    svc_list+=("$svc")
                done <<< "$services"

                echo ""
                for i in "${!svc_list[@]}"; do
                    echo "  $((i+1)). ${svc_list[$i]}"
                done
                echo ""
                read -r -p "选择服务 [1-${#svc_list[@]}]: " svc_choice

                if [[ "$svc_choice" =~ ^[0-9]+$ ]] && [ "$svc_choice" -ge 1 ] && [ "$svc_choice" -le "${#svc_list[@]}" ]; then
                    local svc="${svc_list[$((svc_choice-1))]}"
                    run_cmd "重启服务: $svc" "$compose_cmd -f '$compose_file' restart '$svc'"
                fi
                ;;
            3)
                # 选择服务重建
                local services
                services=$($compose_cmd -f "$compose_file" config --services 2>/dev/null)
                if [ -z "$services" ]; then
                    print_error "无法读取服务列表"
                    sleep 1
                    continue
                fi

                local svc_list=()
                while IFS= read -r svc; do
                    svc_list+=("$svc")
                done <<< "$services"

                echo ""
                for i in "${!svc_list[@]}"; do
                    echo "  $((i+1)). ${svc_list[$i]}"
                done
                echo ""
                read -r -p "选择服务 [1-${#svc_list[@]}]: " svc_choice

                if [[ "$svc_choice" =~ ^[0-9]+$ ]] && [ "$svc_choice" -ge 1 ] && [ "$svc_choice" -le "${#svc_list[@]}" ]; then
                    local svc="${svc_list[$((svc_choice-1))]}"
                    run_cmd "重建服务: $svc" "$compose_cmd -f '$compose_file' up -d --build '$svc'"
                fi
                ;;
            4)
                run_cmd "重启所有服务" "$compose_cmd -f '$compose_file' restart"
                ;;
            0) return ;;
            *)
                print_error "无效选择"
                sleep 1
                ;;
        esac
    done
}

# ==================== P2: 镜像分析 ====================

do_docker_images() {
    clear
    print_title "=== 镜像空间分析 ==="

    # 总览
    echo -e "${BOLD}Docker 磁盘占用:${NC}"
    echo ""
    docker system df 2>/dev/null
    echo ""

    # Top 10 最大镜像
    echo -e "${BOLD}最大的镜像 (Top 10):${NC}"
    echo ""
    echo -e "${BOLD}仓库                  标签           大小${NC}"
    echo "──────────────────────────────────────────────"
    docker images --format '{{.Repository}}\t{{.Tag}}\t{{.Size}}' 2>/dev/null | \
    sort -t$'\t' -k3 -h -r | head -10 | \
    while IFS=$'\t' read -r repo tag size; do
        [ "$repo" = "<none>" ] && repo="${YELLOW}(none)${NC}"
        [ "$tag" = "<none>" ] && tag="${YELLOW}(none)${NC}"
        [ ${#repo} -gt 20 ] && repo="${repo:0:17}..."
        [ ${#tag} -gt 12 ] && tag="${tag:0:9}..."
        printf "  %-20s %-12s %s\n" "$repo" "$tag" "$size"
    done

    # 悬空镜像
    echo ""
    echo -e "${BOLD}悬空镜像 (dangling):${NC}"
    local dangling_count dangling_size
    dangling_count=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l | tr -d ' ')
    if [ "$dangling_count" -gt 0 ]; then
        dangling_size=$(docker images -f "dangling=true" --format '{{.Size}}' 2>/dev/null | head -1 || echo "未知")
        echo -e "  ${YELLOW}⚠${NC} ${dangling_count} 个悬空镜像 (约 ${dangling_size})"
        echo ""
        if confirm_yes "是否清理悬空镜像？"; then
            run_cmd "清理悬空镜像" "docker image prune -f"
            print_success "已清理 $dangling_count 个悬空镜像"
        fi
    else
        echo -e "  ${GREEN}✓${NC} 无悬空镜像"
    fi

    echo ""
    pause
}

# ==================== 交互式菜单 ====================

show_docker_menu() {
    clear
    print_title "=== Docker 管理 ==="

    # 快速状态栏
    local running stopped total
    total=$(docker ps -a -q 2>/dev/null | wc -l | tr -d ' ')
    running=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
    stopped=$((total - running))
    echo -e "  ${GREEN}${running} 运行中${NC}  ${RED}${stopped} 已停止${NC}  共 ${total} 个容器"
    echo ""

    cat << 'EOF'
 1. 容器状态总览    — 运行/停止/资源占用一览
 2. 查看容器日志    — 选择容器，自动跟踪日志
 3. 进入容器        — 选择容器，自动进入 Shell
 4. 清理资源        — 镜像/容器/网络/卷清理
 5. Docker 诊断     — 检查 daemon/端口/重启/OOM
 6. Compose 管理    — 服务状态/重启/重建
 7. 镜像分析        — 占用空间/悬空镜像
 0. 返回

EOF
}

docker_interactive_menu() {
    while true; do
        show_docker_menu
        read -r -p "请选择 [0-7]: " choice

        case $choice in
            1) do_docker_status ;;
            2) do_docker_logs ;;
            3) do_docker_shell ;;
            4) do_docker_clean ;;
            5) do_docker_diagnose ;;
            6) do_docker_compose ;;
            7) do_docker_images ;;
            0) return 0 ;;
            *)
                print_error "无效选择"
                sleep 1
                ;;
        esac
    done
}

# ==================== 主入口 ====================

main_docker() {
    check_docker

    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        status|ps)
            do_docker_status
            ;;
        logs)
            do_docker_logs
            ;;
        shell|exec)
            do_docker_shell
            ;;
        clean|prune)
            do_docker_clean
            ;;
        diagnose|doctor|health)
            do_docker_diagnose
            ;;
        compose|dc)
            do_docker_compose
            ;;
        images|image)
            do_docker_images
            ;;
        help|--help|-h)
            show_docker_help
            ;;
        "")
            # 无子命令 → 交互式菜单
            docker_interactive_menu
            ;;
        *)
            print_error "未知子命令: $subcmd"
            show_docker_help
            exit 1
            ;;
    esac
}

main_docker "$@"
