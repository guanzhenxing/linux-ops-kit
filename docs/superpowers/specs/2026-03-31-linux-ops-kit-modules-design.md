# Linux Ops Kit - 剩余模块设计文档

**日期**: 2026-03-31
**状态**: 设计中
**目标**: 完成 linux-ops-kit 剩余 6 个功能模块（service/log/network/disk/monitor/install）

## 背景

linux-ops-kit 是一个交互式 Shell 脚本运维工具箱，已完成框架搭建和 2 个模块（check.sh、help.sh）。本设计覆盖剩余 6 个模块的详细实现方案。

**开发策略**: 逐模块深度开发，按路线图顺序：service → log → network → disk → monitor → install

**兼容性**: Ubuntu/Debian 为主，兼容 CentOS/RHEL（与现有模块一致）

**通用模式（所有模块遵循）**:
- 入口函数 `show_[module]_menu()` 提供交互菜单
- 使用 `lib/common.sh` 的颜色输出（print_info/warn/error/success/title）和交互函数（confirm/pause/menu_choice）
- 兼容性：通过 `detect_os`、`has_systemd`、`command_exists` 处理发行版差异
- 安全：危险操作前 `confirm` 确认，需 root 操作 `require_root` 检查
- 日志：关键操作通过 `log_action` 记录

---

## 模块 1：service.sh — 服务管理

### 菜单结构

```
===== 服务管理 =====
1. 服务状态概览
2. 管理单个服务
0. 返回主菜单
```

### 功能 1：服务状态概览

- 定义常见服务列表：nginx, apache2/httpd, mysql/mysqld, postgresql, docker, redis-server/redis, mongod, elasticsearch, php-fpm, ssh/sshd, cron/crond, firewalld/ufw
- 遍历列表，用 `service_exists` 检测是否安装，`systemctl is-active` / `service status` 检测运行状态
- 输出格式：`服务名  [✅ 运行中 / ❌ 已停止 / ⬜ 未安装]`
- 最后显示统计：共检测 X 个，Y 个运行中，Z 个已停止

### 功能 2：管理单个服务

- 用户输入服务名
- 先检查服务是否存在（`service_exists`），不存在则提示
- 显示子菜单：
  ```
  管理 [服务名]:
  1. 启动
  2. 停止
  3. 重启
  4. 查看状态
  5. 开机自启
  6. 禁止自启
  0. 返回
  ```
- 启停操作前自动检查 root 权限（`require_root`）
- 操作后显示执行结果

### 复用

- `common.sh`: `has_systemd`, `service_exists`, `require_root`, `print_*`, `confirm`, `log_action`

---

## 模块 2：log.sh — 日志查看

### 菜单结构

```
===== 日志管理 =====
1. 系统日志
2. 服务日志
3. 实时跟踪
4. 日志搜索
0. 返回主菜单
```

### 功能 1：系统日志

- 子菜单选择：
  - systemd 日志（journalctl）：最近 50 条 / 按时间范围 / 按优先级
  - 内核日志（dmesg）：最近 50 条 / 搜索关键词
  - syslog（/var/log/syslog）：最近 50 条
- 使用 `less` 分页显示，支持颜色高亮

### 功能 2：服务日志

- 预定义服务日志路径映射表：
  ```bash
  declare -A SERVICE_LOGS
  SERVICE_LOGS=(
    ["nginx"]="/var/log/nginx/error.log /var/log/nginx/access.log"
    ["apache2"]="/var/log/apache2/error.log"
    ["mysql"]="/var/log/mysql/error.log"
    ["postgresql"]="/var/log/postgresql/"
    ["docker"]="journalctl -u docker"
  )
  ```
- 用户选择服务 → 显示该服务可用的日志文件 → 选择查看哪个
- 自动检测日志文件是否存在

### 功能 3：实时跟踪

- 用户选择日志文件（从服务日志列表或手动输入路径）
- 使用 `tail -f` 实时跟踪
- 提示 Ctrl+C 退出

### 功能 4：日志搜索

- 输入关键词和可选时间范围
- 支持 `grep` 搜索普通日志文件
- 支持 `journalctl` 搜索 systemd 日志
- 时间范围选项：最近 1 小时 / 6 小时 / 24 小时 / 7 天 / 自定义

### 复用

- `common.sh`: `command_exists`, `print_*`, `pause`

---

## 模块 3：network.sh — 网络诊断

### 菜单结构

```
===== 网络诊断 =====
1. 端口检查
2. 网络接口信息
3. 连通性测试
4. 防火墙管理
0. 返回主菜单
```

### 功能 1：端口检查

- 子菜单：
  - 查看所有监听端口（`ss -tlnp` 或 `netstat -tlnp`）
  - 查看指定端口占用（输入端口号，显示进程信息）
  - 查看所有活跃连接（`ss -tnp`）
- 复用 `common.sh` 的 `get_port_info`

### 功能 2：网络接口信息

- 显示所有网络接口（`ip addr` 或 `ifconfig`）
- 显示路由表（`ip route`）
- DNS 查询：输入域名，执行 `nslookup` / `dig`
- 公网 IP 查询（`curl ifconfig.me`，需网络）

### 功能 3：连通性测试

- Ping 测试：输入目标地址，执行 `ping -c 4`
- Traceroute：执行 `traceroute` 或 `tracepath`
- 端口连通性：输入 host:port，执行 `nc -zv` 或 `timeout 3 bash -c 'echo >/dev/tcp/host/port'`

### 功能 4：防火墙管理

- 自动检测防火墙类型（优先 ufw → firewalld → iptables）
- 状态查看（只读，不需要 root）
- 规则管理需要 root：
  - ufw: `ufw status/list/allow/deny`
  - firewalld: `firewall-cmd --list-all/--add-port/--remove-port`
  - iptables: `iptables -L/-A/-D`
- 操作前确认

### 复用

- `common.sh`: `command_exists`, `require_root`, `get_port_info`, `confirm`, `print_*`

---

## 模块 4：disk.sh — 磁盘管理

### 菜单结构

```
===== 磁盘管理 =====
1. 磁盘使用分析
2. 磁盘清理
3. 磁盘挂载管理
4. LVM 管理
0. 返回主菜单
```

### 功能 1：磁盘使用分析

- 磁盘分区使用情况（`df -h`，带颜色告警，复用 check.sh 阈值逻辑）
- 大文件查找：输入目录和大小阈值（如 >100M），`find -size +100M -exec ls -lh {} \;`
- 目录占用排行：输入目录和显示数量，`du -sh * | sort -rh | head -N`
- Inode 使用情况（`df -i`）

### 功能 2：磁盘清理

- 需 root 权限，操作前 `confirm` 确认
- 清理项（每项显示预计释放空间）：
  - APT/YUM 包缓存（`apt clean` / `yum clean all`）
  - 系统日志轮转（`journalctl --vacuum-size=100M`）
  - 临时文件（/tmp, /var/tmp，只清理 >7 天的文件）
  - Docker 无用资源（`docker system prune`，如果 docker 存在）
  - 旧内核（Ubuntu: `apt autoremove`，CentOS: `package-cleanup --oldkernels`）
- 每项操作前单独确认，显示操作前后磁盘空间对比

### 功能 3：磁盘挂载管理

- 查看当前挂载信息（`mount` + `df -h`）
- 查看可用磁盘/分区（`lsblk` 或 `fdisk -l`）
- 挂载新分区：输入设备路径和挂载点，执行 `mount`
- 卸载分区：选择已挂载分区，`umount`
- fstab 管理：查看 /etc/fstab，添加/删除条目

### 功能 4：LVM 管理

- 检测 LVM 是否可用（`command_exists lvm`）
- 查看 PV（`pvs`）/ VG（`vgs`）/ LV（`lvs`）
- LV 扩容：选择 LV，输入新大小，执行 `lvextend` + `resize2fs`
- 需 root，操作前确认

### 复用

- `common.sh`: `require_root`, `confirm`, `command_exists`, `print_*`, `human_readable`

---

## 模块 5：monitor.sh — 监控告警

### 菜单结构

```
===== 监控告警 =====
1. 实时监控面板
2. 阈值告警检查
3. 资源报告
0. 返回主菜单
```

### 功能 1：实时监控面板

- 使用 `tput` + `clear` 实现终端刷新（不依赖 `watch`）
- 每 2 秒刷新，Ctrl+C 退出
- 显示内容：
  - CPU 使用率和负载
  - 内存使用（总量/已用/可用/swap）
  - 磁盘使用（各分区使用率）
  - 网络流量（当前连接数，如果可获取）
  - TOP 5 进程（CPU 和内存）
- 使用 `tput cup` 定位光标，避免全屏闪烁

### 功能 2：阈值告警检查

- 使用模块内变量存储阈值（不依赖外部配置文件）：
  ```
  CPU_WARN=80    CPU_CRIT=90
  MEM_WARN=80    MEM_CRIT=90
  DISK_WARN=80   DISK_CRIT=90
  ```
- 子菜单：
  - 查看当前阈值
  - 修改阈值
  - 执行一次性检查（遍历所有指标，超阈值变色告警）
- 输出格式：
  ```
  [OK]    CPU 使用率: 45.2% (阈值: 80%)
  [WARN]  内存使用率: 85.3% (阈值: 80%)
  [CRIT]  磁盘 /: 92.1% (阈值: 90%)
  ```

### 功能 3：资源报告

- 生成文本格式报告，保存到文件或终端显示
- 内容包含：
  - 系统信息（hostname, OS, kernel, uptime）
  - CPU 信息（型号、核心数、负载）
  - 内存信息
  - 磁盘分区信息
  - 网络接口信息
  - TOP 10 进程（CPU + 内存）
  - 最近登录用户
- 报告文件保存路径：`/tmp/system-report-$(date +%Y%m%d-%H%M%S).txt`

### 复用

- `common.sh`: `get_cpu_usage`, `get_memory_usage`, `get_disk_usage`, `detect_os`, `print_*`

---

## 模块 6：install.sh — 快速安装

### 菜单结构

```
===== 快速安装 =====
1. 常用软件安装
2. SSL 证书管理
3. 配置模板
4. 环境套件部署
0. 返回主菜单
```

### 功能 1：常用软件安装

- 软件列表，每个自动检测是否已安装：
  - Nginx
  - Docker + Docker Compose
  - Node.js（通过 NodeSource 源）
  - Git
  - MySQL / MariaDB
  - Redis
  - PostgreSQL
  - MongoDB
- 安装前显示：软件名、当前状态、将要执行的命令
- 确认后执行安装
- 安装后验证：检查版本号或服务状态

### 功能 2：SSL 证书管理

- 检测 certbot 是否安装
- 子菜单：
  - 申请证书：输入域名，执行 `certbot certonly --nginx/standalone`
  - 续期证书：`certbot renew`
  - 查看已有证书：`certbot certificates`
  - 吊销证书：输入域名
- 每步操作前确认

### 功能 3：配置模板

- Nginx 配置模板：
  - 静态站点
  - 反向代理
  - PHP-FPM 站点
  - HTTPS 重定向
- Docker 配置模板：
  - daemon.json（镜像加速）
  - docker-compose.yml 模板
- 生成模板到指定路径，不覆盖已有文件

### 功能 4：环境套件部署

- LNMP 套件：Linux + Nginx + MySQL + PHP
- LEMP 套件：Linux + Nginx + MySQL/MariaDB + PHP-FPM
- Docker 开发环境：Docker + Docker Compose + Portainer
- 逐步安装每个组件，每步显示进度
- 安装完成后显示各组件版本和状态

### 复用

- `common.sh`: `detect_os`, `command_exists`, `service_exists`, `require_root`, `confirm`, `print_*`, `log_action`

---

## 实现顺序

1. service.sh
2. log.sh
3. network.sh
4. disk.sh
5. monitor.sh
6. install.sh
7. 更新 ops.sh 主菜单版本号

## 验证方案

每个模块完成后：
1. `bash -n modules/[name].sh` 语法检查通过
2. 在 Ubuntu 环境下运行 `ops.sh` 进入对应模块，测试所有菜单项
3. 验证错误处理（无效输入、权限不足、服务不存在等）
4. 验证颜色输出正常显示
