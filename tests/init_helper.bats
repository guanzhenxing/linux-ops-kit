#!/usr/bin/env bats
# lib/init-helper.sh 的状态管理与幂等检测测试
# 重点验证 jq 重写后的健壮性（含特殊字符的值不破坏 JSON）

source "$BATS_TEST_DIRNAME/test_helper/load.bash"

# ---------- 幂等检测 check_idempotent ----------

@test "check_idempotent: ok status returns success (skip)" {
    write_init_state "__init__" ""
    write_init_state "user_create" "ok"
    check_idempotent "user_create" "用户创建"
}

@test "check_idempotent: unrecorded step returns failure" {
    write_init_state "__init__" ""
    ! check_idempotent "docker_install" "Docker"
}

@test "check_idempotent: non-ok (skipped) status returns failure" {
    write_init_state "__init__" ""
    write_init_state "ssh_harden" "skipped"
    ! check_idempotent "ssh_harden" "SSH 加固"
}

# ---------- jq 健壮性（本次重写的核心）----------

@test "write_init_state: special chars do not corrupt JSON" {
    write_init_state "__init__" ""
    write_init_state "weird/key" 'a"b/c&d'
    # jq 能读回原值 = 文件未损坏（sed 实现在此会破坏）
    [ "$(jq -r '.steps["weird/key"]' "$INIT_STATE_FILE")" = 'a"b/c&d' ]
}

@test "write_init_state: repeated key updates instead of appending" {
    write_init_state "__init__" ""
    write_init_state "user_create" "ok"
    write_init_state "user_create" "failed"
    write_init_state "user_create" "ok"
    # steps 里 user_create 只有一条，值为最后一次写入
    [ "$(jq -r '.steps["user_create"]' "$INIT_STATE_FILE")" = "ok" ]
    [ "$(jq -r '.steps | length' "$INIT_STATE_FILE")" = "1" ]
}

# ---------- 状态文件存在性 ----------

@test "is_initialized: no state file returns failure" {
    rm -f "$INIT_STATE_FILE"
    ! is_initialized
}

@test "is_initialized: state file present returns success" {
    write_init_state "__init__" ""
    is_initialized
}

@test "show_init_status: not initialized does not error" {
    rm -f "$INIT_STATE_FILE"
    run show_init_status
    [ "$status" -eq 0 ]
}

# ---------- 外部命令探测 ----------

@test "user_exists: current user exists" {
    user_exists "$(whoami)"
}

@test "user_exists: nonexistent user fails" {
    ! user_exists "nosuchuser_xyz_999"
}

@test "docker_installed: fails when docker CLI absent" {
    if command_exists docker; then
        skip "docker installed in this env, skipping"
    fi
    ! docker_installed
}
