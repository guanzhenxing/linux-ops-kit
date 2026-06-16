#!/usr/bin/env bats
# lib/common.sh 的纯函数与输出函数测试
# 注：bats-core 对非 ASCII 测试名支持不佳，测试名用英文；断言内的中文为测试数据。

source "$BATS_TEST_DIRNAME/test_helper/load.bash"

# ---------- 纯函数 ----------

@test "human_readable: value < 1024 stays in bytes" {
    [ "$(human_readable 0)" = "0 B" ]
    [ "$(human_readable 512)" = "512 B" ]
}

@test "human_readable: >= 1024 converts to KB" {
    [ "$(human_readable 1024)" = "1.00 KB" ]
    [ "$(human_readable 2048)" = "2.00 KB" ]
}

@test "is_root: non-privileged env returns non-zero" {
    if is_root; then
        skip "running as root, cannot verify non-root branch"
    fi
    ! is_root
}

@test "command_exists: builtin command exists" {
    command_exists "ls"
}

@test "command_exists: nonexistent command fails" {
    ! command_exists "definitely_no_such_cmd_xyz_001"
}

# ---------- 输出函数（捕获 stdout）----------

@test "print_info outputs [INFO] tag and message" {
    run print_info "hello world"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO]"* ]]
    [[ "$output" == *"hello world"* ]]
}

@test "print_error outputs [ERROR] tag" {
    run print_error "boom"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[ERROR]"* ]]
}

@test "print_success outputs [SUCCESS] tag" {
    run print_success "done"
    [[ "$output" == *"[SUCCESS]"* ]]
}

@test "print_result: ok status includes step name and detail" {
    run print_result ok "系统更新" "完成"
    [[ "$output" == *"系统更新"* ]]
    [[ "$output" == *"完成"* ]]
}

@test "print_result: skip status includes step name" {
    run print_result skip "Swap" "已存在 2G"
    [[ "$output" == *"Swap"* ]]
}

@test "print_result: fail status includes step name" {
    run print_result fail "系统更新" "apt 返回 100"
    [[ "$output" == *"系统更新"* ]]
}

# ---------- 交互函数（喂 stdin）----------

@test "confirm_yes: input y returns success" {
    printf 'y\n' | confirm_yes "确定" 2>/dev/null
}

@test "confirm_yes: input n returns failure" {
    ! printf 'n\n' | confirm_yes "确定" 2>/dev/null
}

@test "confirm_yes: empty input defaults to No (failure)" {
    ! printf '\n' | confirm_yes "确定" 2>/dev/null
}
