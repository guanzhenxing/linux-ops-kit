# Linux 运维工具箱

一套交互式 Shell 脚本工具，让 Linux 运维变得简单——**不需要记任何命令**。

## 特点

- 🔑 **统一入口** - 一个命令打开所有功能
- 🎯 **交互式菜单** - 看着菜单选，无需记参数
- 🎨 **彩色输出** - 清晰的状态显示
- 📦 **模块化设计** - 每个功能独立模块

## 快速开始

### 1. 上传到服务器

```bash
scp -r linux-ops-kit/ user@server:~/ops-scripts
```

### 2. 运行

```bash
cd ~/ops-scripts
./ops.sh
```

### 3. 创建快捷命令（可选）

```bash
# 添加到 ~/.bashrc 或 ~/.zshrc
alias ops='cd ~/ops-scripts && ./ops.sh'

# 以后直接输入 ops 即可
```

## 目录结构

```
linux-ops-kit/
├── ops.sh          # 主入口（运行这个！）
├── lib/
│   └── common.sh   # 核心函数库
├── modules/        # 功能模块
│   ├── check.sh    # 系统检查
│   ├── service.sh  # 服务管理
│   ├── log.sh      # 日志查看
│   ├── network.sh  # 网络诊断
│   ├── disk.sh     # 磁盘管理
│   ├── monitor.sh  # 监控告警
│   ├── install.sh  # 快捷安装
│   └── help.sh     # 命令帮助
├── data/           # 数据文件
│   └── data.json   # Linux命令数据库
└── docs/           # 文档
```

## 主菜单

```
=== Linux 运维工具箱 ===

1. 系统检查      - CPU/内存/磁盘/服务健康检查
2. 服务管理      - 启动/停止/重启/查看服务
3. 日志查看      - 快速查看各服务日志
4. 网络诊断      - 端口/连通性/抓包
5. 磁盘管理      - 空间检查/清理/挂载
6. 监控告警      - 设置监控阈值/告警
7. 快捷安装      - Nginx/Docker/SSL证书
8. 命令帮助      - 搜索/查看 Linux 命令说明
0. 退出
```

## 当前状态

| 模块 | 状态 | 功能说明 |
|------|------|----------|
| 主入口框架 | ✅ 完成 | 统一菜单入口 |
| 核心函数库 | ✅ 完成 | 颜色输出、系统检测、通用函数 |
| check.sh | ✅ 完成 | 系统信息/CPU/内存/磁盘/服务检查 |
| help.sh | ✅ 完成 | 搜索命令/列出所有/命令详情/更新数据 |
| service.sh | ✅ 完成 | 服务启动/停止/重启/自启动管理 |
| log.sh | ✅ 完成 | 系统日志/服务日志/实时追踪/搜索 |
| network.sh | ✅ 完成 | 端口检查/连通性/防火墙/DNS |
| disk.sh | ✅ 完成 | 使用分析/清理/挂载/LVM管理 |
| monitor.sh | ✅ 完成 | 实时监控面板/阈值告警/资源报告 |
| install.sh | ✅ 完成 | 软件安装/SSL证书/配置模板/环境栈部署 |

## 核心函数 (lib/common.sh)

脚本提供以下通用函数：

```bash
# 输出函数
print_info "消息"     # 绿色信息
print_warn "警告"     # 黄色警告
print_error "错误"    # 红色错误
print_success "成功"  # 绿色加粗成功

# 交互函数
confirm "确定？"      # 确认提示
pause                # 任意键继续

# 系统检测
detect_os            # 检测操作系统
service_exists nginx  # 检测服务是否存在
command_exists docker # 检测命令是否存在

# 系统信息
get_cpu_usage        # 获取 CPU 使用率
get_memory_usage     # 获取内存使用情况
get_disk_usage /     # 获取磁盘使用情况
get_port_info 80     # 获取端口占用情况
```

## 模块功能详解

### check.sh - 系统检查 ✅

```
=== 系统检查 ===

1. 全部检查      - 依次显示所有信息 + 健康状态总结
2. 系统信息      - 内核/系统/架构/运行时间/主机名
3. CPU 检查      - 使用率/核心数/负载/TOP5进程
4. 内存检查      - 总量/使用率/缓存/交换分区
5. 磁盘检查      - 各分区使用情况/Inode状态
6. 服务检查      - 运行中服务状态/手动查询特定服务
```

**告警阈值**：
- 磁盘 ≥ 90%: 🔴 红色警告
- 磁盘 ≥ 80%: 🟡 黄色提醒
- 内存 ≥ 90%: 🔴 红色警告
- Inode ≥ 90%: 🔴 红色警告

### help.sh - 命令帮助 ✅

```
=== Linux 命令帮助 ===

1. 搜索命令      - 按名称搜索命令（可从结果进入详情）
2. 列出所有命令  - 多列显示所有可用命令
3. 命令详情      - 查看指定命令的完整说明（在线获取）
4. 更新数据      - 下载最新命令数据库
b. 返回主菜单
```

**功能特点**：
- 搜索后可直接输入命令名查看详情
- 命令列表使用多列紧凑显示
- 命令详情从 GitHub 实时获取 MD 文档
- 数据来源于 [jaywcjlove/linux-command](https://github.com/jaywcjlove/linux-command) 项目（600+ 命令）

### service.sh - 服务管理 ✅

```
=== 服务管理 ===

1. 服务概览      - 扫描 15 种常见服务的运行状态
2. 管理单个服务  - 启动/停止/重启/查看状态/自启动
0. 返回主菜单
```

**支持的服务**：Nginx、Apache、MySQL、PostgreSQL、Docker、Redis、MongoDB、PHP-FPM、SSH、Cron、Firewalld、Elasticsearch、Memcached、RabbitMQ、etcd、Kubelet
**兼容性**：自动适配 systemd/sysvinit，跨发行版服务名差异（如 apache2/httpd）

### log.sh - 日志查看 ✅

```
=== 日志查看 ===

1. 系统日志      - journalctl/dmesg/syslog 快速查看
2. 服务日志      - 预置 10 种服务的日志路径
3. 实时追踪      - tail -f 实时查看日志
4. 日志搜索      - 关键词搜索 + 时间范围过滤
0. 返回主菜单
```

**预置服务日志**：Nginx、Apache、MySQL、PostgreSQL、Docker、Redis、MongoDB、PHP-FPM、SSHD

### network.sh - 网络诊断 ✅

```
=== 网络诊断 ===

1. 端口检查      - 监听端口/端口占用/活动连接
2. 网络信息      - 接口IP/路由表/DNS/公网IP
3. 连通测试      - Ping/Traceroute/端口连通性
4. 防火墙管理    - 自动检测 ufw/firewalld/iptables
0. 返回主菜单
```

**兼容性**：优先使用 `ss`，回退 `netstat`；支持 `ufw`/`firewalld`/`iptables` 自动切换

### disk.sh - 磁盘管理 ✅

```
=== 磁盘管理 ===

1. 使用分析      - 分区/大文件/目录排行/Inode
2. 磁盘清理      - 包缓存/日志/临时文件/Docker/旧内核
3. 挂载管理      - 查看/挂载/卸载/fstab 编辑
4. LVM 管理      - PV/VG/LV 查看/扩展
0. 返回主菜单
```

**清理功能**：支持一键清理全部，显示清理前后磁盘对比

### monitor.sh - 监控告警 ✅

```
=== 监控告警 ===

1. 实时监控面板  - 2秒刷新，CPU/内存/磁盘/网络/TOP5
2. 阈值告警      - 查看/修改阈值，一次性检查
3. 资源报告      - 生成完整系统报告到 /tmp
0. 返回主菜单
```

**实时面板**：使用 `tput` 无闪烁刷新，进度条可视化，彩色告警（绿/黄/红）

### install.sh - 快捷安装 ✅

```
=== 快捷安装 ===

1. 常用软件      - Nginx/Docker/Node.js/Git/MySQL/Redis/PostgreSQL/MongoDB
2. SSL 证书      - 申请/续期/查看/撤销（certbot）
3. 配置模板      - Nginx/Docker Compose 模板
4. 环境部署      - LNMP/LEMP/Docker 开发环境一键部署
0. 返回主菜单
```

**配置模板**：Nginx 静态站/反向代理/HTTPS、Docker 镜像加速、Docker Compose（Web/WordPress/LNMP）

## 开发路线

- [x] 第一阶段：框架搭建
- [x] 第二阶段：系统检查模块 (check.sh)
- [x] 第三阶段：服务管理、日志查看
- [x] 第四阶段：网络诊断、磁盘管理
- [x] 第五阶段：监控告警、安装脚本、配置模板

## 版本

- **v2.0.0** - 全部 8 个模块实现完成（服务管理/日志查看/网络诊断/磁盘管理/监控告警/快捷安装）
- **v1.2.0** - help.sh 模块完成（搜索/列表/详情/更新）
- **v1.1.0** - check.sh 模块完成
- **v1.0.0** - 框架搭建完成
