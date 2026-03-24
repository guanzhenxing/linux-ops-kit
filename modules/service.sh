#!/bin/bash
# 模块占位文件 - 此模块开发中

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

clear
print_title "=== 此模块开发中 ==="

print_info "该功能正在开发中，敬请期待..."
print_info "预计下一版本上线"

echo ""
pause
