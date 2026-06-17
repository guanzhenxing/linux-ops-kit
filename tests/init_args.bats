#!/usr/bin/env bats
# modules/init.sh parse_args 参数解析测试
# 验证命令行参数到 OPTS_* 变量的映射正确性

source "$BATS_TEST_DIRNAME/test_helper/load.bash"
source "$PROJECT_ROOT/modules/init.sh"

# ---------- 布尔开关 ----------

@test "parse_args: --defaults sets OPTS_DEFAULTS=yes" {
    parse_args --defaults
    [ "$OPTS_DEFAULTS" = "yes" ]
}

@test "parse_args: --force sets OPTS_FORCE=yes" {
    parse_args --force
    [ "$OPTS_FORCE" = "yes" ]
}

@test "parse_args: --dry-run sets OPTS_DRY_RUN=yes" {
    parse_args --dry-run
    [ "$OPTS_DRY_RUN" = "yes" ]
}

@test "parse_args: --skip-upgrade sets OPTS_SKIP_UPGRADE=yes" {
    parse_args --skip-upgrade
    [ "$OPTS_SKIP_UPGRADE" = "yes" ]
}

@test "parse_args: --rollback sets OPTS_ROLLBACK=yes" {
    parse_args --rollback
    [ "$OPTS_ROLLBACK" = "yes" ]
}

@test "parse_args: --docker sets OPTS_DOCKER=yes" {
    parse_args --docker
    [ "$OPTS_DOCKER" = "yes" ]
}

@test "parse_args: --harden-ssh sets OPTS_HARDEN_SSH=yes" {
    parse_args --harden-ssh
    [ "$OPTS_HARDEN_SSH" = "yes" ]
}

@test "parse_args: --fail2ban sets OPTS_FAIL2BAN=yes" {
    parse_args --fail2ban
    [ "$OPTS_FAIL2BAN" = "yes" ]
}

@test "parse_args: --firewall sets OPTS_FIREWALL=yes" {
    parse_args --firewall
    [ "$OPTS_FIREWALL" = "yes" ]
}

# ---------- 值参数 ----------

@test "parse_args: -u sets OPTS_USER" {
    parse_args -u alice
    [ "$OPTS_USER" = "alice" ]
}

@test "parse_args: --ssh-key github: sets OPTS_SSH_KEY" {
    parse_args -k github:jesen
    [ "$OPTS_SSH_KEY" = "github:jesen" ]
}

@test "parse_args: -t sets OPTS_TIMEZONE" {
    parse_args -t UTC
    [ "$OPTS_TIMEZONE" = "UTC" ]
}

@test "parse_args: -s sets OPTS_SWAP" {
    parse_args -s 4G
    [ "$OPTS_SWAP" = "4G" ]
}

@test "parse_args: -n sets OPTS_HOSTNAME" {
    parse_args -n myserver
    [ "$OPTS_HOSTNAME" = "myserver" ]
}

@test "parse_args: --mirror sets OPTS_MIRROR" {
    parse_args --mirror aliyun
    [ "$OPTS_MIRROR" = "aliyun" ]
}

@test "parse_args: --extra-ports sets OPTS_EXTRA_PORTS" {
    parse_args --extra-ports "8080 9090"
    [ "$OPTS_EXTRA_PORTS" = "8080 9090" ]
}

# ---------- 组合参数 ----------

@test "parse_args: combined flags all set correctly" {
    parse_args --defaults -u bob -k github:bob --docker --firewall --mirror tuna
    [ "$OPTS_DEFAULTS" = "yes" ]
    [ "$OPTS_USER" = "bob" ]
    [ "$OPTS_SSH_KEY" = "github:bob" ]
    [ "$OPTS_DOCKER" = "yes" ]
    [ "$OPTS_FIREWALL" = "yes" ]
    [ "$OPTS_MIRROR" = "tuna" ]
    # 未指定的保持默认
    [ "$OPTS_HARDEN_SSH" = "no" ]
    [ "$OPTS_FAIL2BAN" = "no" ]
}

# ---------- 默认值 ----------

@test "parse_args: no args uses defaults" {
    parse_args
    [ "$OPTS_DEFAULTS" = "no" ]
    [ "$OPTS_DOCKER" = "no" ]
    [ "$OPTS_FORCE" = "no" ]
    [ "$OPTS_DRY_RUN" = "no" ]
    [ "$OPTS_TIMEZONE" = "Asia/Shanghai" ]
    [ "$OPTS_USER" = "" ]
}

# ---------- 帮助参数不触发错误 ----------

@test "parse_args: -h exits but is not tested (help) — skip" {
    skip "parse_args 中 -h 会直接 exit 0，无法在 bats 中直接测试"
}
