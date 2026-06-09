# Linux 运维工具箱

一套交互式 Shell 脚本工具，让 Linux 运维变得简单——**不需要记任何命令**。

## 特点

- 🔑 **统一入口** - 一个命令打开所有功能
- 🎯 **交互式菜单** - 看着菜单选，无需记参数
- 🆕 **服务器初始化** - 新服务器一条命令从 0 到可用
- 🎨 **彩色输出** - 清晰的状态显示
- 📦 **模块化设计** - 每个功能独立模块
- 🐧 **跨发行版** - 支持 Ubuntu/Debian/CentOS/AlmaLinux/Rocky

---

## 快速开始

### 方式一：零依赖安装（🚀 新服务器推荐）

> 没有 git？没关系。一条命令搞定：

```bash
# 安装到 /opt/linux-ops-kit（默认）
curl -fsSL https://raw.githubusercontent.com/guanzhenxing/linux-ops-kit/main/bootstrap.sh | sudo bash

# 安装后自动运行 init 交互式向导
curl -fsSL https://raw.githubusercontent.com/guanzhenxing/linux-ops-kit/main/bootstrap.sh | sudo RUN_INIT=1 bash

# 安装后自动运行 init 命令行模式（传入 init 参数）
curl -fsSL https://raw.githubusercontent.com/guanzhenxing/linux-ops-kit/main/bootstrap.sh | \
  sudo RUN_INIT=1 bash -s -- -u jesen -k github:jesen --docker

# 自定义安装目录
curl -fsSL https://raw.githubusercontent.com/guanzhenxing/linux-ops-kit/main/bootstrap.sh | \
  sudo INSTALL_DIR=~/linux-ops-kit bash

# 先看脚本再决定（安全习惯）
curl -fsSL https://raw.githubusercontent.com/guanzhenxing/linux-ops-kit/main/bootstrap.sh | less
```

### 方式二：服务器初始化（已有 git 的服务器）

```bash
# 克隆仓库
git clone git@github.com:guanzhenxing/linux-ops-kit.git && cd linux-ops-kit

# 交互式向导（新手推荐）
sudo ./ops.sh init

# 最小命令行
sudo ./ops.sh init -u jesen -k github:jesen

# 完整初始化
sudo ./ops.sh init -u jesen -k github:jesen -s 2G --docker --harden-ssh --firewall --fail2ban
```

init 会自动完成：系统更新 → 创建用户 → 导入 SSH Key → SSH 加固 → 防火墙 → fail2ban → Docker CE → 安全审计。

### 方式三：日常运维（交互式菜单）

```bash
cd linux-ops-kit
./ops.sh
```

### 方式四：创建快捷命令（可选）

```bash
echo "alias ops='/opt/linux-ops-kit/ops.sh'" >> ~/.bashrc && source ~/.bashrc
```

---

## 主菜单

```
=== Linux 运维工具箱 v2.2.0 ===

 0. 服务器初始化  - 🆕 新服务器一条命令从 0 到可用
 1. 系统检查      - CPU/内存/磁盘/服务健康检查
 2. 服务管理      - 启动/停止/重启/查看服务
 3. 日志查看      - 快速查看各服务日志
 4. 网络诊断      - 端口/连通性/抓包
 5. 磁盘管理      - 空间检查/清理/挂载
 6. 监控告警      - 设置监控阈值/告警
 7. 快捷安装      - Nginx/Docker/SSL证书
 8. 命令帮助      - 搜索/查看 Linux 命令说明
00. 退出
```

### 子命令路由

除了交互式菜单，也支持子命令直接调用：

```bash
./ops.sh init                        # 服务器初始化
./ops.sh user add alice --ssh-key github:alice   # 添加用户
./ops.sh user list                   # 列出用户
./ops.sh security status             # 安全状态检查
./ops.sh security audit              # 完整安全审计
```

---

## 目录结构

```
linux-ops-kit/
├── bootstrap.sh              # 🚀 远程引导安装（curl | bash 调用）
├── ops.sh                    # 主入口（交互菜单 + 子命令路由）
├── lib/
│   ├── common.sh             # 核心函数库（输出/交互/系统检测）
│   ├── os-detect.sh          # 🆕 发行版检测 + 包管理器抽象
│   └── init-helper.sh        # 🆕 init 辅助函数（健康检查/SSH验证/日志/状态）
├── modules/
│   ├── init.sh               # 🆕 初始化模块（主调度器）
│   ├── init-system.sh        # 🆕 系统配置（时区/swap/hostname/NTP）
│   ├── init-user.sh          # 🆕 用户管理（创建/SSH Key/sudo）
│   ├── init-security.sh      # 🆕 安全加固（SSH/防火墙/fail2ban/审计）
│   ├── init-software.sh      # 🆕 软件安装（常用工具/Docker CE）
│   ├── user.sh               # 🆕 Day 2 用户管理
│   ├── security-audit.sh     # 🆕 Day 2 安全审计
│   ├── check.sh              # 系统检查
│   ├── service.sh            # 服务管理
│   ├── log.sh                # 日志查看
│   ├── network.sh            # 网络诊断
│   ├── disk.sh               # 磁盘管理
│   ├── monitor.sh            # 监控告警
│   ├── install.sh            # 快捷安装
│   └── help.sh               # 命令帮助
└── data/
    ├── init-defaults.conf    # 🆕 init 全局默认配置
    └── data.json             # Linux 命令数据库
```

---

## 模块状态

| 模块 | 状态 | 说明 |
|------|------|------|
| **🆕 服务器初始化** | ✅ 完成 | 交互式向导、一键初始化、SSH 安全验证、自动回滚 |
| **🆕 用户管理** | ✅ 完成 | 添加/列出/删除用户，SSH Key 导入 |
| **🆕 安全审计** | ✅ 完成 | SSH/防火墙/fail2ban/自动更新状态检查、最近登录 |
| 系统检查 | ✅ 完成 | CPU/内存/磁盘/服务一键检查，带健康告警 |
| 服务管理 | ✅ 完成 | 服务启动/停止/重启/自启动管理 |
| 日志查看 | ✅ 完成 | 系统日志/服务日志/实时追踪/搜索 |
| 网络诊断 | ✅ 完成 | 端口检查/连通性/防火墙/DNS |
| 磁盘管理 | ✅ 完成 | 使用分析/清理/挂载/LVM管理 |
| 监控告警 | ✅ 完成 | 实时监控面板/阈值告警/资源报告 |
| 快捷安装 | ✅ 完成 | 软件安装/SSL证书/配置模板/环境栈部署 |
| 命令帮助 | ✅ 完成 | 搜索/列表/详情/更新命令数据库 |

---

## 🆕 Init 模块详解

### 功能概述

`./ops.sh init` 是 linux-ops-kit 的核心功能——**让新服务器从 0 到可用只需要一条命令**。

### 执行流程

```
环境检测 → 系统更新 → 系统配置 → 创建用户 → SSH 验证 →
SSH 加固 → 防火墙 → fail2ban → 安全审计 → Docker + 常用工具
```

### 安全设计

init 模块遵循"先铺后路再加固"的安全原则：

1. **SSH 加固前自动验证**：用你的 SSH Key 真实建立连接，验证成功才关闭密码认证
2. **防火墙启用后再验证**：确保 SSH 端口未被误封，失败则自动关闭防火墙
3. **验证失败自动回滚**：SSH 配置修改前自动备份，验证失败恢复原状
4. **安全审计只读**：内核参数、文件权限等服务检查不自动修改，只输出报告

### 支持的发行版

| 优先级 | 发行版 | 版本 |
|--------|-------|------|
| 🔴 P0 | Ubuntu | 20.04, 22.04, 24.04 |
| 🔴 P0 | Debian | 11, 12 |
| 🔴 P0 | CentOS / AlmaLinux / Rocky | 7, 8, 9 |
| 🟡 P1 | Amazon Linux | 2023 |
| 🟢 P2 | Fedora | 最新 |

### 使用示例

```bash
# 交互式向导（最推荐，一步步引导）
sudo ./ops.sh init

# 全默认模式（跳过问答，一键完成）
sudo ./ops.sh init --defaults -u jesen -k github:jesen

# 只创建用户，不做安全加固
sudo ./ops.sh init -u jesen -k github:jesen

# 完整初始化（Docker + SSH 加固 + 防火墙 + fail2ban）
sudo ./ops.sh init -u jesen -k github:jesen -s 2G --docker --harden-ssh --firewall --fail2ban

# 使用国内镜像源（加速 Docker 和包安装）
sudo ./ops.sh init -u jesen -k github:jesen --docker --mirror aliyun

# 预览模式（只显示计划，不执行）
sudo ./ops.sh init -u jesen --docker --dry-run

# 回滚上次初始化
sudo ./ops.sh init --rollback
```

### Day 2 操作（初始化之后的日常管理）

```bash
# 用户管理
./ops.sh user add alice --ssh-key github:alice
./ops.sh user list
./ops.sh user del bob --purge

# 安全审计
./ops.sh security status    # 快速安全状态
./ops.sh security audit     # 完整安全审计
```

---

## 核心函数 (lib/common.sh)

脚本提供以下通用函数：

```bash
# 输出函数
print_info "消息"       # 绿色信息
print_warn "警告"       # 黄色警告
print_error "错误"      # 红色错误
print_success "成功"    # 绿色加粗成功
print_step 1 10 "系统更新"   # 步骤进度
print_result ok "系统更新" "完成"  # 步骤结果

# 交互函数
confirm "确定？"              # 确认提示（默认 No）
confirm_yes "启用 SSH 加固？"  # 确认提示（默认 No）
confirm_no "安装 Docker？"     # 确认提示（默认 Yes）
input_with_default "用户名" "admin"  # 带默认值的输入
select_option "选择方式" "选项1" "选项2"  # 菜单选择

# 命令透明（变更操作显示命令并确认，只读操作显示命令）
run_cmd "安装 Nginx" "apt-get install -y nginx"   # 变更操作：显示命令 + 确认后执行
show_cmd "查看磁盘" "df -h"                        # 只读操作：显示命令 + 直接执行

# 系统检测
detect_os                # 检测操作系统（简单版）
detect_os_full           # 完整检测（导出 OS_ID/OS_VERSION/OS_FAMILY）
service_exists nginx     # 检测服务是否存在
command_exists docker    # 检测命令是否存在

# 跨发行版抽象 (lib/os-detect.sh)
pkg_install "curl wget git"     # 统一包安装
pkg_install --skip-missing "htop"  # 可选包安装
pkg_update                      # 统一系统更新
svc_manage "nginx" enable-now   # 统一服务管理

# 系统信息
get_cpu_usage                  # 获取 CPU 使用率
get_memory_usage               # 获取内存使用情况
get_disk_usage /               # 获取磁盘使用情况
get_port_info 80               # 获取端口占用情况

# Init 辅助 (lib/init-helper.sh)
preflight_check                # 启动前健康检查
verify_ssh_access "user" "host" # SSH 连接验证
rollback_ssh_config            # SSH 配置回滚
check_idempotent "step" "desc"  # 幂等检测
```

---

## 开发路线

- [x] 第一阶段：框架搭建
- [x] 第二阶段：系统检查模块 (check.sh)
- [x] 第三阶段：服务管理、日志查看
- [x] 第四阶段：网络诊断、磁盘管理
- [x] 第五阶段：监控告警、安装脚本、配置模板
- [x] **第六阶段：服务器初始化 (init 模块) 🆕**
  - [x] 发行版抽象层（apt/yum/dnf 统一）
  - [x] 系统配置（时区/swap/hostname/NTP/sysctl）
  - [x] 用户管理 + SSH Key 导入
  - [x] SSH 加固 + 防火墙 + fail2ban
  - [x] Docker CE + Compose 安装
  - [x] 交互式向导 + 执行计划 + 结果报告
  - [x] SSH 自动验证 + 失败回滚
  - [x] 安全审计（只读模式）
  - [x] Day 2 操作（user/security 子命令）

---

## 设计原则

1. **安全优先** — SSH 加固前验证连接、防火墙启用后再次验证、验证失败自动回滚
2. **幂等性** — 重复运行不会重复创建用户/安装软件，已存在则跳过
3. **跨发行版** — Debian/Ubuntu 和 RHEL/CentOS 系统一抽象层
4. **优雅降级** — 不支持的发行版/功能跳过并提示，不阻塞整体流程
5. **进度反馈** — 彩色输出每一步的执行状态
6. **用户友好** — 每条错误消息包含原因解释和修复建议
7. **命令透明** — 变更操作执行前显示等价命令并要求确认（`run_cmd`），只读操作展示命令供学习（`show_cmd`）

---

## 版本

- **v2.2.0** — 🆕 命令透明机制：变更操作执行前显示命令并确认（`run_cmd`），只读操作展示命令供学习（`show_cmd`）
- **v2.1.0** — 🆕 新增 init 模块（服务器一键初始化）+ Day 2 操作（user/security）
- **v2.0.0** — 全部 8 个模块实现完成
- **v1.2.0** — help.sh 模块完成
- **v1.1.0** — check.sh 模块完成
- **v1.0.0** — 框架搭建完成
