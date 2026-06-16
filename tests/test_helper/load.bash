#!/usr/bin/env bash
# bats 测试公共加载文件
# 每个 .bats 文件通过 `load test_helper/load` 引入
#
# 职责：
#   1. 计算项目根目录
#   2. 把 init 写入路径（日志/状态/备份）重定向到临时目录，避免污染 /var/log、/etc
#   3. source 三大核心库（与 ops.sh 顺序一致）

# 项目根目录（load.bash 位于 tests/test_helper/，上两级即项目根）
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PROJECT_ROOT

# 每个测试用例独立临时目录（mktemp 天然隔离，互不污染）
TEST_TMPDIR="$(mktemp -d)"
export TEST_TMPDIR
export INIT_LOG_FILE="$TEST_TMPDIR/ops-init.log"
export INIT_STATE_FILE="$TEST_TMPDIR/ops-init.state"
export INIT_BACKUP_DIR="$TEST_TMPDIR/backups"
export LOG_FILE="$TEST_TMPDIR/ops-scripts.log"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/os-detect.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/init-helper.sh"
