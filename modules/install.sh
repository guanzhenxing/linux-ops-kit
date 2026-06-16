#!/bin/bash
set -uo pipefail
# 快捷安装模块 - 常用软件安装/SSL证书/配置模板/环境套件

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# ==================== 常用软件安装 ====================

install_software() {
    clear
    print_title "=== 常用软件安装 ==="

    if ! is_root; then
        print_error "软件安装需要 root 权限"
        print_info "请使用: sudo ops.sh 或以 root 用户运行"
        echo ""
        pause
        return
    fi

    local os_type=$(detect_os)

    # 软件列表
    echo -e "${BOLD}可用软件:${NC}"
    echo ""

    local softwares=("nginx" "docker" "nodejs" "git" "mysql" "redis" "postgresql" "mongodb")
    local status=()

    for sw in "${softwares[@]}"; do
        local installed="❌ 未安装"
        local sw_cmd="$sw"

        case "$sw" in
            mysql)      sw_cmd="mysql" ;;
            postgresql) sw_cmd="psql" ;;
            mongodb)    sw_cmd="mongod" ;;
            nodejs)     sw_cmd="node" ;;
        esac

        if command_exists "$sw_cmd"; then
            local ver=$("$sw_cmd" --version 2>/dev/null | head -1)
            installed="✅ 已安装 ${CYAN}($ver)${NC}"
        fi

        status+=("$installed")

        local idx=$(( ${#status[@]} ))
        echo -e "  ${GREEN}$idx${NC}. $sw  $installed"
    done

    echo ""
    read -r -p "选择要安装的软件编号 (0 返回): " num

    [ "$num" = "0" ] && return

    if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "${#softwares[@]}" ]; then
        print_error "无效选择"
        sleep 1
        return
    fi

    local sw="${softwares[$((num - 1))]}"
    local current_status="${status[$((num - 1))]}"

    if [[ "$current_status" == *"已安装"* ]]; then
        if ! confirm "$sw 已安装，是否重新安装?"; then
            return
        fi
    fi

    install_single "$sw" "$os_type"
}

install_single() {
    local sw="$1"
    local os_type="$2"

    echo ""
    print_info "正在安装 $sw ..."

    case "$sw" in
        nginx)
            if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
                run_cmd "安装 Nginx" "apt-get update -qq && apt-get install -y nginx"
            else
                run_cmd "安装 Nginx" "yum install -y nginx || dnf install -y nginx"
            fi
            ;;
        docker)
            if confirm_yes "是否使用官方脚本安装 Docker?"; then
                run_cmd "使用官方脚本安装 Docker" "curl -fsSL https://get.docker.com | sh" && \
                systemctl enable docker && systemctl start docker
                print_info "将当前用户加入 docker 组: usermod -aG docker $USER"
            else
                if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
                    run_cmd "安装 Docker (系统包)" "apt-get update -qq && apt-get install -y docker.io docker-compose" && \
                    systemctl enable docker && systemctl start docker
                else
                    run_cmd "安装 Docker (系统包)" "yum install -y docker docker-compose || dnf install -y docker docker-compose" && \
                    systemctl enable docker && systemctl start docker
                fi
            fi
            ;;
        nodejs)
            read -r -p "输入 Node.js 版本 (如 18, 20, 22，默认 20): " node_ver
            node_ver=${node_ver:-20}
            if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
                run_cmd "安装 Node.js $node_ver" "curl -fsSL https://deb.nodesource.com/setup_${node_ver}.x | bash - && apt-get install -y nodejs"
            else
                run_cmd "安装 Node.js $node_ver" "curl -fsSL https://rpm.nodesource.com/setup_${node_ver}.x | bash - && yum install -y nodejs || dnf install -y nodejs"
            fi
            ;;
        git)
            if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
                run_cmd "安装 Git" "apt-get update -qq && apt-get install -y git"
            else
                run_cmd "安装 Git" "yum install -y git || dnf install -y git"
            fi
            ;;
        mysql)
            if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
                run_cmd "安装 MySQL Server" "apt-get update -qq && apt-get install -y mysql-server" && \
                systemctl enable mysql && systemctl start mysql
            else
                run_cmd "安装 MySQL Server" "yum install -y mysql-server || dnf install -y mysql-server" && \
                systemctl enable mysqld && systemctl start mysqld
            fi
            ;;
        redis)
            if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
                run_cmd "安装 Redis" "apt-get update -qq && apt-get install -y redis-server" && \
                systemctl enable redis-server && systemctl start redis-server
            else
                run_cmd "安装 Redis" "yum install -y redis || dnf install -y redis" && \
                systemctl enable redis && systemctl start redis
            fi
            ;;
        postgresql)
            read -r -p "输入 PostgreSQL 版本 (如 14, 15, 16，默认 15): " pg_ver
            pg_ver=${pg_ver:-15}
            if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
                run_cmd "安装 PostgreSQL" "apt-get update -qq && apt-get install -y postgresql postgresql-contrib"
            else
                run_cmd "安装 PostgreSQL" "yum install -y postgresql-server postgresql-contrib || dnf install -y postgresql-server postgresql-contrib" && \
                postgresql-setup initdb 2>/dev/null && \
                systemctl enable postgresql && systemctl start postgresql
            fi
            ;;
        mongodb)
            if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
                run_cmd "安装 MongoDB 7.0" "apt-get install -y gnupg curl && curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor" && \
                echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] http://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" \
                    | tee /etc/apt/sources.list.d/mongodb-org-7.0.list && \
                apt-get update -qq && apt-get install -y mongodb-org
            else
                tee /etc/yum.repos.d/mongodb-org-7.0.repo << 'REPO'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/$releasever/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
REPO
                run_cmd "安装 MongoDB 7.0" "yum install -y mongodb-org || dnf install -y mongodb-org"
            fi
            systemctl enable mongod && systemctl start mongod
            ;;
    esac

    if [ $? -eq 0 ]; then
        print_success "$sw 安装成功"
        # 验证安装
        local verify_cmd=""
        case "$sw" in
            nginx) verify_cmd="nginx -v 2>&1" ;;
            docker) verify_cmd="docker --version" ;;
            nodejs) verify_cmd="node --version" ;;
            git) verify_cmd="git --version" ;;
            mysql) verify_cmd="mysql --version" ;;
            redis) verify_cmd="redis-server --version" ;;
            postgresql) verify_cmd="psql --version" ;;
            mongodb) verify_cmd="mongod --version" ;;
        esac
        echo -e "  版本: ${CYAN}$(eval "$verify_cmd" 2>&1 | head -1)${NC}"
        log_action "安装了 $sw"
    else
        print_error "$sw 安装失败"
    fi

    echo ""
    pause
}

# ==================== SSL 证书管理 ====================

manage_ssl() {
    clear
    print_title "=== SSL 证书管理 ==="

    if ! is_root; then
        print_error "SSL 证书管理需要 root 权限"
        echo ""
        pause
        return
    fi

    # 检查 certbot
    if ! command_exists certbot; then
        print_warn "certbot 未安装"
        local os_type=$(detect_os)
        if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
            run_cmd "安装 certbot" "apt-get update -qq && apt-get install -y certbot python3-certbot-nginx"
        else
            run_cmd "安装 certbot" "yum install -y certbot python3-certbot-nginx || dnf install -y certbot python3-certbot-nginx"
        fi
    fi

    cat << 'EOF'

1. 申请证书
2. 续期证书
3. 查看已有证书
4. 吊销证书
0. 返回

EOF

    read -r -p "请选择 [0-4]: " choice

    case $choice in
        1)
            read -r -p "输入域名 (如 example.com): " domain
            if [ -z "$domain" ]; then
                return
            fi

            echo ""
            echo -e "${BOLD}验证方式:${NC}"
            echo "1. Nginx 插件 (需已配置 Nginx)"
            echo "2. 独立模式 (需 80 端口可用)"
            read -r -p "请选择 [1-2]: " method

            if [ "$method" = "1" ]; then
                run_cmd "申请 SSL 证书 (Nginx 插件): $domain" "certbot --nginx -d '$domain'"
            else
                run_cmd "申请 SSL 证书 (standalone): $domain" "certbot certonly --standalone -d '$domain'"
            fi

            if [ $? -eq 0 ]; then
                print_success "证书申请成功"
                log_action "申请了 SSL 证书: $domain"
            else
                print_error "证书申请失败"
            fi
            ;;
        2)
            print_info "正在续期证书..."
            run_cmd "续期 SSL 证书" "certbot renew"
            print_success "续期完成"
            ;;
        3)
            show_cmd "查看已有证书" "certbot certificates"
            ;;
        4)
            read -r -p "输入要吊销的域名: " domain
            if [ -n "$domain" ]; then
                run_cmd "吊销证书: $domain" "certbot revoke --cert-name '$domain'"
                print_success "证书已吊销"
                log_action "吊销了 SSL 证书: $domain"
            fi
            ;;
        0) return ;;
        *)
            print_error "无效选择"
            sleep 1
            ;;
    esac

    echo ""
    pause
}

# ==================== 配置模板 ====================

show_templates() {
    clear
    print_title "=== 配置模板 ==="

    cat << 'EOF'
1. Nginx 静态站点配置
2. Nginx 反向代理配置
3. Nginx HTTPS 配置
4. Docker 镜像加速配置
5. Docker Compose 模板
0. 返回

EOF

    read -r -p "请选择 [0-5]: " choice

    case $choice in
        1) template_nginx_static ;;
        2) template_nginx_proxy ;;
        3) template_nginx_https ;;
        4) template_docker_mirror ;;
        5) template_docker_compose ;;
        0) return ;;
        *)
            print_error "无效选择"
            sleep 1
            ;;
    esac
}

template_nginx_static() {
    read -r -p "输入域名 (如 example.com): " domain
    read -r -p "输入站点根目录 (如 /var/www/html): " root_dir
    domain=${domain:-example.com}
    root_dir=${root_dir:-/var/www/html}

    local conf_file="/etc/nginx/sites-available/$domain"
    if [ -f "$conf_file" ] && ! confirm "$conf_file 已存在，覆盖?"; then
        return
    fi

    mkdir -p "$root_dir"
    mkdir -p /etc/nginx/sites-available 2>/dev/null

    cat > "$conf_file" << TEOF
server {
    listen 80;
    server_name $domain;
    root $root_dir;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # 静态文件缓存
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    access_log /var/log/nginx/${domain}.access.log;
    error_log /var/log/nginx/${domain}.error.log;
}
TEOF

    # 创建软链接
    ln -sf "$conf_file" "/etc/nginx/sites-enabled/$domain" 2>/dev/null

    print_success "配置已生成: $conf_file"
    print_info "执行 nginx -t 测试配置，然后 systemctl reload nginx"
    log_action "生成了 Nginx 静态站点配置: $domain"

    echo ""
    pause
}

template_nginx_proxy() {
    read -r -p "输入域名: " domain
    read -r -p "输入后端地址 (如 http://127.0.0.1:3000): " backend
    domain=${domain:-example.com}
    backend=${backend:-http://127.0.0.1:3000}

    local conf_file="/etc/nginx/sites-available/$domain"
    if [ -f "$conf_file" ] && ! confirm "$conf_file 已存在，覆盖?"; then
        return
    fi

    mkdir -p /etc/nginx/sites-available 2>/dev/null

    cat > "$conf_file" << TEOF
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass $backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    access_log /var/log/nginx/${domain}.access.log;
    error_log /var/log/nginx/${domain}.error.log;
}
TEOF

    ln -sf "$conf_file" "/etc/nginx/sites-enabled/$domain" 2>/dev/null

    print_success "配置已生成: $conf_file"
    log_action "生成了 Nginx 反向代理配置: $domain"

    echo ""
    pause
}

template_nginx_https() {
    read -r -p "输入域名: " domain
    domain=${domain:-example.com}

    local conf_file="/etc/nginx/sites-available/$domain"
    if [ -f "$conf_file" ] && ! confirm "$conf_file 已存在，覆盖?"; then
        return
    fi

    mkdir -p /etc/nginx/sites-available 2>/dev/null

    cat > "$conf_file" << TEOF
# HTTP 重定向到 HTTPS
server {
    listen 80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}

# HTTPS
server {
    listen 443 ssl http2;
    server_name $domain;

    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;

    # SSL 优化
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    root /var/www/$domain;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    access_log /var/log/nginx/${domain}.access.log;
    error_log /var/log/nginx/${domain}.error.log;
}
TEOF

    ln -sf "$conf_file" "/etc/nginx/sites-enabled/$domain" 2>/dev/null

    print_success "配置已生成: $conf_file"
    print_info "请先使用 SSL 证书管理申请证书"
    log_action "生成了 Nginx HTTPS 配置: $domain"

    echo ""
    pause
}

template_docker_mirror() {
    local daemon_json="/etc/docker/daemon.json"

    if [ -f "$daemon_json" ] && ! confirm "$daemon_json 已存在，覆盖?"; then
        return
    fi

    read -r -p "输入镜像加速地址 (留空使用默认): " mirror_url
    mirror_url=${mirror_url:-"https://mirror.ccs.tencentyun.com"}

    mkdir -p /etc/docker

    cat > "$daemon_json" << TEOF
{
    "registry-mirrors": ["$mirror_url"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2"
}
TEOF

    print_success "配置已生成: $daemon_json"
    print_info "执行 systemctl daemon-reload && systemctl restart docker 生效"
    log_action "生成了 Docker 镜像加速配置"

    echo ""
    pause
}

template_docker_compose() {
    local output_dir
    read -r -p "输入输出目录 (默认当前目录): " output_dir
    output_dir=${output_dir:-.}

    local compose_file="$output_dir/docker-compose.yml"
    if [ -f "$compose_file" ] && ! confirm "$compose_file 已存在，覆盖?"; then
        return
    fi

    cat << 'EOF'
选择模板类型:
1. Web 应用 (Nginx + App)
2. WordPress (Nginx + MySQL + PHP)
3. LNMP (Nginx + MySQL + PHP-FPM)
EOF

    read -r -p "请选择 [1-3]: " tmpl_choice

    case $tmpl_choice in
        1)
            cat > "$compose_file" << 'TEOF'
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./html:/usr/share/nginx/html
    restart: unless-stopped

  app:
    image: node:20-alpine
    working_dir: /app
    volumes:
      - ./app:/app
    ports:
      - "3000:3000"
    command: npm start
    restart: unless-stopped
TEOF
            ;;
        2)
            cat > "$compose_file" << 'TEOF'
version: '3.8'

services:
  wordpress:
    image: wordpress:latest
    ports:
      - "80:80"
    environment:
      WORDPRESS_DB_HOST: mysql:3306
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: wordpress
      WORDPRESS_DB_NAME: wordpress
    volumes:
      - ./wp-content:/var/www/html/wp-content
    depends_on:
      - mysql
    restart: unless-stopped

  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wordpress
      MYSQL_PASSWORD: wordpress
    volumes:
      - mysql_data:/var/lib/mysql
    restart: unless-stopped

volumes:
  mysql_data:
TEOF
            ;;
        3)
            cat > "$compose_file" << 'TEOF'
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./html:/usr/share/nginx/html
    depends_on:
      - php-fpm
    restart: unless-stopped

  php-fpm:
    image: php:8.2-fpm-alpine
    volumes:
      - ./html:/usr/share/nginx/html
    restart: unless-stopped

  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword
    volumes:
      - mysql_data:/var/lib/mysql
    restart: unless-stopped

volumes:
  mysql_data:
TEOF
            ;;
        *) return ;;
    esac

    print_success "模板已生成: $compose_file"
    log_action "生成了 Docker Compose 模板"

    echo ""
    pause
}

# ==================== 环境套件部署 ====================

deploy_stack() {
    clear
    print_title "=== 环境套件部署 ==="

    if ! is_root; then
        print_error "环境部署需要 root 权限"
        echo ""
        pause
        return
    fi

    cat << 'EOF'
1. LNMP  (Linux + Nginx + MySQL + PHP)
2. LEMP  (Linux + Nginx + MySQL + PHP-FPM)
3. Docker 开发环境 (Docker + Compose + Portainer)
0. 返回

EOF

    read -r -p "请选择 [0-3]: " choice

    case $choice in
        1) deploy_lnmp ;;
        2) deploy_lemp ;;
        3) deploy_docker_dev ;;
        0) return ;;
        *)
            print_error "无效选择"
            sleep 1
            ;;
    esac
}

deploy_lnmp() {
    local os_type=$(detect_os)

    print_info "开始部署 LNMP 环境..."
    echo ""

    # 1. Nginx
    echo -e "${BOLD}[1/3] 安装 Nginx${NC}"
    if command_exists nginx; then
        print_info "Nginx 已安装，跳过"
    else
        if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
            run_cmd "安装 Nginx" "apt-get update -qq && apt-get install -y nginx"
        else
            run_cmd "安装 Nginx" "yum install -y nginx || dnf install -y nginx"
        fi
        systemctl enable nginx && systemctl start nginx
    fi
    echo -e "  版本: $(nginx -v 2>&1)"
    echo ""

    # 2. MySQL
    echo -e "${BOLD}[2/3] 安装 MySQL${NC}"
    if command_exists mysql; then
        print_info "MySQL 已安装，跳过"
    else
        if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
            run_cmd "安装 MySQL Server" "apt-get install -y mysql-server"
            systemctl enable mysql && systemctl start mysql
        else
            run_cmd "安装 MySQL Server" "yum install -y mysql-server || dnf install -y mysql-server"
            systemctl enable mysqld && systemctl start mysqld
        fi
    fi
    echo -e "  版本: $(mysql --version 2>&1 | head -1)"
    echo ""

    # 3. PHP
    echo -e "${BOLD}[3/3] 安装 PHP${NC}"
    if command_exists php; then
        print_info "PHP 已安装，跳过"
    else
        if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
            run_cmd "安装 PHP-FPM + 扩展" "apt-get install -y php-fpm php-mysql php-common php-cli php-gd php-curl php-mbstring php-xml"
            systemctl enable php*-fpm && systemctl start php*-fpm
        else
            run_cmd "安装 PHP-FPM + 扩展" "yum install -y php-fpm php-mysqlnd php-cli php-gd php-curl php-mbstring php-xml || dnf install -y php-fpm php-mysqlnd php-cli php-gd php-curl php-mbstring php-xml"
            systemctl enable php-fpm && systemctl start php-fpm
        fi
    fi
    echo -e "  版本: $(php -v 2>&1 | head -1)"
    echo ""

    print_success "LNMP 部署完成！"
    print_info "Nginx 配置目录: /etc/nginx/"
    print_info "MySQL 数据目录: /var/lib/mysql/"
    print_info "PHP-FPM 配置目录: /etc/php/*/fpm/"
    log_action "部署了 LNMP 环境"

    echo ""
    pause
}

deploy_lemp() {
    # LEMP 基本与 LNMP 相同，PHP-FPM 已在 LNMP 中包含
    print_info "LEMP 与 LNMP 安装内容相同，PHP-FPM 模式已包含在 LNMP 部署中"
    deploy_lnmp
}

deploy_docker_dev() {
    local os_type=$(detect_os)

    print_info "开始部署 Docker 开发环境..."
    echo ""

    # 1. Docker
    echo -e "${BOLD}[1/3] 安装 Docker${NC}"
    if command_exists docker; then
        print_info "Docker 已安装，跳过"
    else
        if confirm_yes "使用官方脚本安装 Docker?"; then
            run_cmd "使用官方脚本安装 Docker" "curl -fsSL https://get.docker.com | sh"
        else
            if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
                run_cmd "安装 Docker (系统包)" "apt-get update -qq && apt-get install -y docker.io docker-compose"
            else
                run_cmd "安装 Docker (系统包)" "yum install -y docker docker-compose || dnf install -y docker docker-compose"
            fi
        fi
        systemctl enable docker && systemctl start docker
    fi
    echo -e "  版本: $(docker --version 2>&1)"
    echo ""

    # 2. Docker Compose
    echo -e "${BOLD}[2/3] 安装 Docker Compose${NC}"
    if command_exists docker-compose || docker compose version &>/dev/null; then
        print_info "Docker Compose 已安装，跳过"
    else
        if [ "$os_type" = "ubuntu" ] || [ "$os_type" = "debian" ]; then
            run_cmd "安装 Docker Compose" "apt-get install -y docker-compose-plugin 2>/dev/null || apt-get install -y docker-compose"
        else
            run_cmd "安装 Docker Compose" "yum install -y docker-compose-plugin || dnf install -y docker-compose-plugin"
        fi
    fi
    echo ""

    # 3. Portainer
    echo -e "${BOLD}[3/3] 安装 Portainer (可选)${NC}"
    if confirm_yes "是否安装 Portainer 管理面板?"; then
        docker volume create portainer_data 2>/dev/null
        run_cmd "启动 Portainer 容器" "docker run -d -p 9000:9000 -p 9443:9443 --name portainer --restart=unless-stopped -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest"

        if [ $? -eq 0 ]; then
            print_success "Portainer 已启动"
            print_info "访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):9000"
        fi
    fi
    echo ""

    print_success "Docker 开发环境部署完成！"
    log_action "部署了 Docker 开发环境"

    echo ""
    pause
}

# ==================== 主菜单 ====================

show_menu() {
    clear
    print_title "=== 快捷安装 ==="

    cat << 'EOF'
1. 常用软件安装    - Nginx/Docker/Node.js/Git/MySQL/Redis
2. SSL 证书管理    - Let's Encrypt 申请/续期/查看
3. 配置模板        - Nginx/Docker 配置文件生成
4. 环境套件部署    - LNMP/LEMP/Docker 开发环境
b. 返回主菜单

EOF
}

# ==================== 主入口 ====================

main_install() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    local os_type
    os_type=$(detect_os)

    case "$subcmd" in
        nginx)          install_single "nginx" "$os_type" ;;
        docker)         install_single "docker" "$os_type" ;;
        nodejs)         install_single "nodejs" "$os_type" ;;
        git)            install_single "git" "$os_type" ;;
        mysql)          install_single "mysql" "$os_type" ;;
        redis)          install_single "redis" "$os_type" ;;
        postgresql)     install_single "postgresql" "$os_type" ;;
        mongodb)        install_single "mongodb" "$os_type" ;;
        ssl|cert)       manage_ssl ;;
        template)       show_templates ;;
        lnmp)           deploy_lnmp ;;
        docker-dev)     deploy_docker_dev ;;
        help|--help)    show_install_help ;;
        "")
            main
            ;;
        *)
            print_error "未知子命令: $subcmd"
            show_install_help
            exit 1
            ;;
    esac
}
  template     配置模板（Nginx/Docker）
  lnmp         部署 LNMP 环境（Nginx+MySQL+PHP）
  docker-dev   部署 Docker 开发环境
  help         显示此帮助

无子命令运行进入交互式菜单。

示例:
  ./ops.sh install nginx
main_install "$@"
