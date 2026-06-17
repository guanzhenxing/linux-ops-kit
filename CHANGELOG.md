# Changelog

## [2.5.0] — 2026-06-17

### Added
- CI integration smoke tests：4 发行版 Docker 矩阵（ubuntu:22.04/24.04, debian:12, almalinux:9）
- parse_args 18 用例 bats 测试覆盖
- shfmt 代码风格门禁加入 CI
- bootstrap.sh 可选 SHA256 完整性校验

### Changed
- 版本号集中管理到 `lib/version.sh`
- install.sh Docker 安装去重，统一使用 `init-software.sh` 官方源方案

### Fixed
- check.sh `services_found` 管道子 shell 变量丢失
- init.sh `--defaults` 仍弹出确认提示
- init-system.sh `do_ntp()` Debian 分支盲调用 systemctl
- init.sh `do_rollback()` grep -oP 替换为 sed（macOS 兼容）
- help.sh curl 添加 --connect-timeout
- disk.sh 清除末尾孤立文本

## [2.4.0] — 2026-06-16

### Added
- shellcheck CI 门禁（severity=warning）
- bats 单元测试基线（30 用例）
- jq 原子写入状态文件
- GitHub Actions CI（shellcheck + bats）
- MIT License

### Fixed
- sudoers 重复写入的幂等 bug

## [2.3.0] — 2026-06-14

### Added
- Docker 管理模块（status/logs/shell/clean/diagnose/compose/images/save/load）

## [2.1.0] — 2026-06-12

### Added
- init 模块（服务器一键初始化）
- Day 2 操作（user/security 子命令）
- 交互式向导 + 执行计划 + 结果报告
- SSH 自动验证 + 失败回滚
- 安全审计（只读模式）

## [2.0.0] — 2026-06-10

### Added
- 全部 8 个模块实现完成（check/service/log/network/disk/monitor/install/help）

## [1.2.0] — 2026-06-09

### Added
- help.sh 命令帮助模块

## [1.1.0] — 2026-06-08

### Added
- check.sh 系统检查模块

## [1.0.0] — 2026-06-07

### Added
- 框架搭建完成
- 统一入口 ops.sh + 交互式菜单
- lib/common.sh 核心函数库
