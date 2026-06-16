#!/usr/bin/env bats
# lib/os-detect.sh 的纯函数测试
# 注：get_pkg_manager 内部调用 detect_os_full（读真实 /etc/os-release），
#     无法靠 mock OS_FAMILY 测试，故按当前系统真实检测结果断言。

source "$BATS_TEST_DIRNAME/test_helper/load.bash"

@test "get_sudo_group: debian family returns sudo" {
    OS_FAMILY="debian"
    [ "$(get_sudo_group)" = "sudo" ]
}

@test "get_sudo_group: rhel family returns wheel" {
    OS_FAMILY="rhel"
    [ "$(get_sudo_group)" = "wheel" ]
}

@test "get_sudo_group: unknown family defaults to sudo" {
    OS_FAMILY="alpine"
    [ "$(get_sudo_group)" = "sudo" ]
}

@test "get_pkg_manager: exports PKG_MGR (smoke)" {
    get_pkg_manager
    [ -n "$PKG_MGR" ]
    # 已知家族才有完整命令；unknown 家族（如 macOS 开发机）命令为空
    if [ "$OS_FAMILY" != "unknown" ]; then
        [ -n "$PKG_INSTALL_CMD" ]
    fi
}

@test "get_pkg_manager: matches detect_os_full result" {
    get_pkg_manager
    case "$OS_FAMILY" in
        debian) [ "$PKG_MGR" = "apt" ] ;;
        rhel)   [ "$PKG_MGR" = "yum" ] || [ "$PKG_MGR" = "dnf" ] ;;
        *)      skip "OS family '$OS_FAMILY' not in test scope" ;;
    esac
}
