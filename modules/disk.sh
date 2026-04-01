#!/bin/bash
# 磁盘管理模块 - 使用分析/清理/挂载/LVM管理

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# ==================== 磁盘使用分析 ====================

analyze_disk() {
    clear
    print_title "=== 磁盘使用分析 ==="

    cat << 'EOF'
1. 磁盘分区使用情况
2. 查找大文件
3. 目录占用排行
4. Inode 使用情况
0. 返回

EOF

    read -p "请选择 [0-4]: " choice

    case $choice in
        1)
            echo ""
            print_info "磁盘分区使用情况:"
            echo ""
            echo -e "${BOLD}文件系统        总容量  已用    可用    使用%  挂载点${NC}"
            echo "------------------------------------------------------"
            df -h | grep -vE '^Filesystem|tmpfs|cdrom|udev|overlay' | while read -r line; do
                local usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
                if [ "$usage" -ge 90 ]; then
                    echo -e "${RED}$line${NC} ${RED}⚠️${NC}"
                elif [ "$usage" -ge 80 ]; then
                    echo -e "${YELLOW}$line${NC} ${YELLOW}⚠${NC}"
                else
                    echo -e "${GREEN}$line${NC}"
                fi
            done
            echo ""
            pause
            ;;
        2)
            read -p "搜索目录 (默认 /): " search_dir
            search_dir=${search_dir:-/}

            read -p "最小文件大小 (如 100M, 1G, 默认 100M): " min_size
            min_size=${min_size:-100M}

            echo ""
            print_info "查找 $search_dir 下大于 $min_size 的文件..."
            echo ""

            find "$search_dir" -xdev -type f -size "+$min_size" -exec ls -lh {} \; 2>/dev/null | \
                awk '{print $5, $9}' | sort -rh | head -20

            if [ ${PIPESTATUS[0]} -ne 0 ]; then
                print_warn "可能需要 root 权限才能访问某些目录"
            fi
            echo ""
            pause
            ;;
        3)
            read -p "分析目录 (默认 /): " target_dir
            target_dir=${target_dir:-/}

            read -p "显示前 N 个 (默认 10): " top_n
            top_n=${top_n:-10}

            echo ""
            print_info "目录占用排行 TOP $top_n ($target_dir):"
            echo ""

            du -sh "$target_dir"/* 2>/dev/null | sort -rh | head "$top_n"
            echo ""
            pause
            ;;
        4)
            echo ""
            print_info "Inode 使用情况:"
            echo ""
            df -i | grep -vE '^Filesystem|tmpfs|cdrom|udev|overlay' | while read -r line; do
                local usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
                if [ "$usage" -ge 90 ]; then
                    echo -e "${RED}$line${NC} ${RED}⚠️${NC}"
                elif [ "$usage" -ge 80 ]; then
                    echo -e "${YELLOW}$line${NC} ${YELLOW}⚠${NC}"
                else
                    echo "$line"
                fi
            done
            echo ""
            pause
            ;;
        0) return ;;
        *)
            print_error "无效选择"
            sleep 1
            ;;
    esac
}

# ==================== 磁盘清理 ====================

clean_disk() {
    clear
    print_title "=== 磁盘清理 ==="

    if ! is_root; then
        print_error "磁盘清理需要 root 权限"
        print_info "请使用: sudo ops.sh 或以 root 用户运行"
        echo ""
        pause
        return
    fi

    # 显示当前磁盘使用
    local disk_before=$(df -h / | tail -1 | awk '{print $5}')
    echo -e "当前根分区使用: ${BOLD}$disk_before${NC}"
    echo ""

    cat << 'EOF'
1. 清理包管理器缓存
2. 清理系统日志
3. 清理临时文件
4. 清理 Docker 资源
5. 清理旧内核
6. 一键全部清理
0. 返回

EOF

    read -p "请选择 [0-6]: " choice

    case $choice in
        1) clean_pkg_cache ;;
        2) clean_system_logs ;;
        3) clean_temp_files ;;
        4) clean_docker ;;
        5) clean_old_kernels ;;
        6)
            echo ""
            print_info "执行一键清理..."
            echo ""
            clean_pkg_cache
            clean_system_logs
            clean_temp_files
            clean_docker
            clean_old_kernels

            echo ""
            local disk_after=$(df -h / | tail -1 | awk '{print $5}')
            print_success "清理完成！磁盘使用: $disk_before → $disk_after"
            ;;
        0) return ;;
        *)
            print_error "无效选择"
            sleep 1
            ;;
    esac

    echo ""
    pause
}

clean_pkg_cache() {
    echo -e "${BOLD}[清理]${NC} 包管理器缓存..."
    local os_type=$(detect_os)

    if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
        local before=$(du -sh /var/cache/apt/archives/ 2>/dev/null | awk '{print $1}')
        apt-get clean -y 2>/dev/null
        apt-get autoremove -y 2>/dev/null
        local after=$(du -sh /var/cache/apt/archives/ 2>/dev/null | awk '{print $1}')
        print_success "APT 缓存已清理: $before → $after"
    elif [ "$os_type" = "centos" ] || [ "$os_type" = "rhel" ]; then
        yum clean all -y 2>/dev/null || dnf clean all -y 2>/dev/null
        print_success "YUM/DNF 缓存已清理"
    else
        print_warn "不支持的发行版，跳过包缓存清理"
    fi
    echo ""
}

clean_system_logs() {
    echo -e "${BOLD}[清理]${NC} 系统日志..."

    if command_exists journalctl; then
        local before=$(journalctl --disk-usage 2>/dev/null | awk '{print $7,$8}')
        journalctl --vacuum-size=100M --vacuum-time=7d 2>/dev/null
        local after=$(journalctl --disk-usage 2>/dev/null | awk '{print $7,$8}')
        print_success "Journal 日志已清理: $before → $after"
    else
        # 清理传统日志
        find /var/log -name "*.gz" -mtime +7 -delete 2>/dev/null
        find /var/log -name "*.old" -mtime +7 -delete 2>/dev/null
        find /var/log -name "*.1" -mtime +7 -delete 2>/dev/null
        print_success "旧日志文件已清理"
    fi
    echo ""
}

clean_temp_files() {
    echo -e "${BOLD}[清理]${NC} 临时文件..."

    local count=0
    count=$(find /tmp -type f -mtime +7 ! -name ".X*-lock" 2>/dev/null | wc -l)
    local count2=0
    count2=$(find /var/tmp -type f -mtime +7 2>/dev/null | wc -l)

    local total=$((count + count2))

    if [ "$total" -eq 0 ]; then
        print_info "无需要清理的临时文件"
    else
        find /tmp -type f -mtime +7 ! -name ".X*-lock" -delete 2>/dev/null
        find /var/tmp -type f -mtime +7 -delete 2>/dev/null
        print_success "已清理 $total 个临时文件 (>7天)"
    fi
    echo ""
}

clean_docker() {
    if ! command_exists docker; then
        return
    fi

    echo -e "${BOLD}[清理]${NC} Docker 资源..."

    if ! docker info &>/dev/null; then
        print_warn "Docker 未运行，跳过"
        echo ""
        return
    fi

    local before=$(docker system df 2>/dev/null | head -2 | tail -1 | awk '{print $3}')
    docker system prune -f 2>/dev/null
    local after=$(docker system df 2>/dev/null | head -2 | tail -1 | awk '{print $3}')
    print_success "Docker 资源已清理: $before → $after"
    echo ""
}

clean_old_kernels() {
    echo -e "${BOLD}[清理]${NC} 旧内核..."
    local os_type=$(detect_os)

    if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
        apt-get autoremove -y --purge 2>/dev/null
        print_success "旧内核包已清理"
    elif [ "$os_type" = "centos" ] || [ "$os_type" = "rhel" ]; then
        if command_exists package-cleanup; then
            package-cleanup --oldkernels --count=2 -y 2>/dev/null
            print_success "旧内核已清理 (保留最近2个)"
        else
            print_info "安装 package-cleanup: yum install yum-utils"
        fi
    else
        print_warn "不支持的发行版，跳过内核清理"
    fi
    echo ""
}

# ==================== 磁盘挂载管理 ====================

manage_mount() {
    clear
    print_title "=== 磁盘挂载管理 ==="

    cat << 'EOF'
1. 查看当前挂载信息
2. 查看可用磁盘/分区
3. 挂载分区
4. 卸载分区
5. 查看 /etc/fstab
0. 返回

EOF

    read -p "请选择 [0-5]: " choice

    case $choice in
        1)
            echo ""
            print_info "当前挂载信息:"
            echo ""
            echo -e "${BOLD}设备            挂载点      文件系统  大小    已用    使用%${NC}"
            echo "----------------------------------------------------------------"
            df -hT | grep -vE '^Filesystem|tmpfs|cdrom|udev|overlay' | \
                awk '{printf "%-15s %-11s %-9s %-7s %-7s %s\n", $1, $7, $2, $3, $4, $6}'
            echo ""
            pause
            ;;
        2)
            echo ""
            print_info "可用磁盘和分区:"
            echo ""
            if command_exists lsblk; then
                lsblk -f
            else
                fdisk -l 2>/dev/null | grep -E "^Disk /dev|^/dev"
            fi
            echo ""
            pause
            ;;
        3)
            if ! is_root; then
                print_error "此操作需要 root 权限"
                sleep 1
                return
            fi

            read -p "输入设备路径 (如 /dev/sdb1): " device
            read -p "输入挂载点 (如 /mnt/data): " mount_point

            if [ -z "$device" ] || [ -z "$mount_point" ]; then
                print_error "设备路径和挂载点不能为空"
                sleep 1
                return
            fi

            if ! [ -b "$device" ]; then
                print_error "设备 $device 不存在"
                sleep 1
                return
            fi

            mkdir -p "$mount_point"

            if confirm "挂载 $device 到 $mount_point ?"; then
                mount "$device" "$mount_point"
                if [ $? -eq 0 ]; then
                    print_success "挂载成功"
                    log_action "挂载了 $device 到 $mount_point"
                else
                    print_error "挂载失败"
                fi
            fi
            echo ""
            pause
            ;;
        4)
            if ! is_root; then
                print_error "此操作需要 root 权限"
                sleep 1
                return
            fi

            echo ""
            print_info "当前挂载的非系统分区:"
            echo ""
            mount | grep -vE 'proc|sys|dev|tmpfs|cgroup|overlay' | awk '{print $1, "on", $3}'
            echo ""

            read -p "输入要卸载的挂载点或设备: " target

            if [ -z "$target" ]; then
                return
            fi

            if confirm "确定卸载 $target ?"; then
                umount "$target"
                if [ $? -eq 0 ]; then
                    print_success "卸载成功"
                    log_action "卸载了 $target"
                else
                    print_error "卸载失败（可能正在使用中）"
                    print_info "使用 'lsof +D $target' 查看占用进程"
                fi
            fi
            echo ""
            pause
            ;;
        5)
            echo ""
            print_info "/etc/fstab 内容:"
            echo ""
            cat /etc/fstab | grep -v "^#" | grep -v "^$"
            echo ""
            pause
            ;;
        0) return ;;
        *)
            print_error "无效选择"
            sleep 1
            ;;
    esac
}

# ==================== LVM 管理 ====================

manage_lvm() {
    clear
    print_title "=== LVM 管理 ==="

    if ! command_exists lvm; then
        print_error "LVM 工具未安装"
        print_info "安装: apt install lvm2 或 yum install lvm2"
        echo ""
        pause
        return
    fi

    cat << 'EOF'
1. 查看物理卷 (PV)
2. 查看卷组 (VG)
3. 查看逻辑卷 (LV)
4. 扩展逻辑卷
0. 返回

EOF

    read -p "请选择 [0-4]: " choice

    case $choice in
        1)
            echo ""
            print_info "物理卷 (PV):"
            echo ""
            pvs 2>/dev/null || pvdisplay 2>/dev/null
            echo ""
            pause
            ;;
        2)
            echo ""
            print_info "卷组 (VG):"
            echo ""
            vgs 2>/dev/null || vgdisplay 2>/dev/null
            echo ""
            pause
            ;;
        3)
            echo ""
            print_info "逻辑卷 (LV):"
            echo ""
            lvs 2>/dev/null || lvdisplay 2>/dev/null
            echo ""
            pause
            ;;
        4)
            if ! is_root; then
                print_error "此操作需要 root 权限"
                sleep 1
                return
            fi

            echo ""
            print_info "当前逻辑卷:"
            echo ""
            lvs 2>/dev/null
            echo ""

            read -p "输入逻辑卷路径 (如 /dev/vg0/lv0): " lv_path
            if [ -z "$lv_path" ]; then
                return
            fi

            read -p "输入新大小 (如 +10G 或 20G): " new_size
            if [ -z "$new_size" ]; then
                return
            fi

            if confirm "扩展逻辑卷 $lv_path 到 $new_size ?"; then
                lvextend -L "$new_size" "$lv_path" 2>/dev/null
                if [ $? -eq 0 ]; then
                    # 扩展文件系统
                    local fs_type=$(lsblk -n -o FSTYPE "$lv_path" 2>/dev/null)
                    if [ "$fs_type" = "ext4" ]; then
                        resize2fs "$lv_path"
                    elif [ "$fs_type" = "xfs" ]; then
                        xfs_growfs "$lv_path"
                    fi
                    print_success "逻辑卷已扩展"
                    log_action "扩展了逻辑卷 $lv_path 到 $new_size"
                else
                    print_error "扩展失败，请检查卷组是否有足够空间"
                fi
            fi
            echo ""
            pause
            ;;
        0) return ;;
        *)
            print_error "无效选择"
            sleep 1
            ;;
    esac
}

# ==================== 主菜单 ====================

show_menu() {
    clear
    print_title "=== 磁盘管理 ==="

    cat << 'EOF'
1. 磁盘使用分析    - 分区/大文件/目录排行/Inode
2. 磁盘清理        - 包缓存/日志/临时文件/Docker/旧内核
3. 磁盘挂载管理    - 查看/挂载/卸载/fstab
4. LVM 管理        - PV/VG/LV 查看/扩展
b. 返回主菜单

EOF
}

# ==================== 主循环 ====================

main() {
    while true; do
        show_menu
        read -p "请选择 [1-4/b]: " choice

        case $choice in
            1) analyze_disk ;;
            2) clean_disk ;;
            3) manage_mount ;;
            4) manage_lvm ;;
            b|B) return 0 ;;
            *)
                print_error "无效选择"
                sleep 1
                ;;
        esac
    done
}

main "$@"
