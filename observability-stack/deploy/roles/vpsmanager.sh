#!/bin/bash
#===============================================================================
# VPSManager Deployment (Laravel + LEMP Stack + Monitoring)
#
# Full production deployment for Laravel application:
# - Nginx + PHP-FPM (8.2+)
# - MariaDB
# - Redis
# - Supervisor (queues)
# - Let's Encrypt SSL
# - All monitoring exporters + Promtail
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
STACK_DIR="$(dirname "$DEPLOY_DIR")"

# Application defaults
VPSMANAGER_REPO="${VPSMANAGER_REPO:-}"
VPSMANAGER_BRANCH="${VPSMANAGER_BRANCH:-main}"
VPSMANAGER_PATH="/var/www/vpsmanager"
VPSMANAGER_USER="www-data"

# PHP Version
PHP_VERSION="${PHP_VERSION:-8.2}"

# Exporter versions
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-1.7.0}"
PROMTAIL_VERSION="${PROMTAIL_VERSION:-3.0.0}"
NGINX_EXPORTER_VERSION="${NGINX_EXPORTER_VERSION:-1.1.0}"
MYSQLD_EXPORTER_VERSION="${MYSQLD_EXPORTER_VERSION:-0.15.1}"
PHPFPM_EXPORTER_VERSION="${PHPFPM_EXPORTER_VERSION:-0.6.0}"

#===============================================================================
# Main Installation Function
#===============================================================================

install_vpsmanager() {
    log_step "Installing VPSManager (Laravel Application)..."

    validate_config
    install_system_packages
    install_nginx
    install_php
    install_mariadb
    install_redis
    install_nodejs
    install_composer
    install_supervisor
    deploy_application
    configure_nginx_vhost
    setup_ssl
    configure_supervisor
    set_permissions

    # Install monitoring
    install_node_exporter
    install_nginx_exporter
    install_mysqld_exporter
    install_phpfpm_exporter
    install_promtail

    setup_firewall_vpsmanager
    start_all_services
    save_installation_info

    run_post_deploy
}

#===============================================================================
# Configuration Validation
#===============================================================================

validate_config() {
    log_step "Validating configuration..."

    if [[ -z "${VPSMANAGER_REPO:-}" ]]; then
        log_error "VPSMANAGER_REPO is required"
        log_info "Set it during installation or export VPSMANAGER_REPO=<url>"
        exit 1
    fi

    if [[ -z "${VPSMANAGER_DOMAIN:-}" ]]; then
        log_error "Domain is required for VPSManager"
        exit 1
    fi

    log_success "Configuration validated"
}

#===============================================================================
# System Packages
#===============================================================================

install_system_packages() {
    log_step "Installing system packages..."

    apt-get update -qq
    apt-get install -y -qq \
        curl \
        wget \
        unzip \
        git \
        acl \
        ufw \
        certbot \
        python3-certbot-nginx \
        jq \
        htop \
        ncdu \
        vim \
        cron

    log_success "System packages installed"
}

#===============================================================================
# Nginx
#===============================================================================

install_nginx() {
    log_step "Installing Nginx..."

    apt-get install -y -qq nginx

    # Remove default site
    rm -f /etc/nginx/sites-enabled/default

    # Optimize nginx.conf
    cat > /etc/nginx/conf.d/optimization.conf << 'EOF'
# Nginx Optimization
client_max_body_size 100M;
server_tokens off;

# Gzip
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;

# Security headers (applied in vhost)
EOF

    log_success "Nginx installed"
}

#===============================================================================
# PHP
#===============================================================================

install_php() {
    log_step "Installing PHP ${PHP_VERSION}..."

    # Add PHP repository
    apt-get install -y -qq apt-transport-https lsb-release ca-certificates
    curl -sSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /etc/apt/keyrings/php.gpg
    echo "deb [signed-by=/etc/apt/keyrings/php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list

    apt-get update -qq

    # Install PHP with extensions
    apt-get install -y -qq \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-common \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-pgsql \
        php${PHP_VERSION}-sqlite3 \
        php${PHP_VERSION}-redis \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-readline \
        php${PHP_VERSION}-opcache \
        php${PHP_VERSION}-soap \
        php${PHP_VERSION}-tokenizer

    # Configure PHP-FPM
    local fpm_conf="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

    # Enable status page for monitoring
    sed -i 's/^;pm.status_path/pm.status_path/' "$fpm_conf"
    sed -i 's|^pm.status_path = .*|pm.status_path = /fpm-status|' "$fpm_conf"
    sed -i 's/^;ping.path/ping.path/' "$fpm_conf"

    # Performance tuning
    sed -i 's/^pm = dynamic/pm = dynamic/' "$fpm_conf"
    sed -i 's/^pm.max_children = .*/pm.max_children = 20/' "$fpm_conf"
    sed -i 's/^pm.start_servers = .*/pm.start_servers = 5/' "$fpm_conf"
    sed -i 's/^pm.min_spare_servers = .*/pm.min_spare_servers = 3/' "$fpm_conf"
    sed -i 's/^pm.max_spare_servers = .*/pm.max_spare_servers = 10/' "$fpm_conf"

    # PHP.ini optimization
    local php_ini="/etc/php/${PHP_VERSION}/fpm/php.ini"
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' "$php_ini"
    sed -i 's/^post_max_size = .*/post_max_size = 100M/' "$php_ini"
    sed -i 's/^memory_limit = .*/memory_limit = 256M/' "$php_ini"
    sed -i 's/^max_execution_time = .*/max_execution_time = 120/' "$php_ini"
    sed -i 's/^;opcache.enable=.*/opcache.enable=1/' "$php_ini"
    sed -i 's/^;opcache.memory_consumption=.*/opcache.memory_consumption=256/' "$php_ini"

    log_success "PHP ${PHP_VERSION} installed"
}

#===============================================================================
# MariaDB
#===============================================================================

install_mariadb() {
    log_step "Installing MariaDB..."

    apt-get install -y -qq mariadb-server mariadb-client

    # Start MariaDB
    systemctl enable mariadb
    systemctl start mariadb

    # Generate secure password
    DB_ROOT_PASS=$(generate_password)
    DB_APP_PASS=$(generate_password)

    # Secure installation
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';"
    mysql -u root -p"${DB_ROOT_PASS}" -e "DELETE FROM mysql.user WHERE User='';"
    mysql -u root -p"${DB_ROOT_PASS}" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -u root -p"${DB_ROOT_PASS}" -e "DROP DATABASE IF EXISTS test;"
    mysql -u root -p"${DB_ROOT_PASS}" -e "FLUSH PRIVILEGES;"

    # Create application database and user
    mysql -u root -p"${DB_ROOT_PASS}" << EOF
CREATE DATABASE IF NOT EXISTS vpsmanager CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'vpsmanager'@'localhost' IDENTIFIED BY '${DB_APP_PASS}';
GRANT ALL PRIVILEGES ON vpsmanager.* TO 'vpsmanager'@'localhost';
FLUSH PRIVILEGES;
EOF

    # Create exporter user
    MYSQL_EXPORTER_PASS=$(generate_password)
    mysql -u root -p"${DB_ROOT_PASS}" << EOF
CREATE USER IF NOT EXISTS 'exporter'@'localhost' IDENTIFIED BY '${MYSQL_EXPORTER_PASS}';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';
FLUSH PRIVILEGES;
EOF

    # Save credentials
    mkdir -p /root/.credentials
    chmod 700 /root/.credentials
    cat > /root/.credentials/mysql << EOF
DB_ROOT_PASS=${DB_ROOT_PASS}
DB_APP_USER=vpsmanager
DB_APP_PASS=${DB_APP_PASS}
DB_NAME=vpsmanager
MYSQL_EXPORTER_PASS=${MYSQL_EXPORTER_PASS}
EOF
    chmod 600 /root/.credentials/mysql

    log_success "MariaDB installed (credentials saved to /root/.credentials/mysql)"
}

#===============================================================================
# Redis
#===============================================================================

install_redis() {
    log_step "Installing Redis..."

    apt-get install -y -qq redis-server

    # Configure Redis
    sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf
    sed -i 's/^# maxmemory .*/maxmemory 256mb/' /etc/redis/redis.conf
    sed -i 's/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf

    systemctl enable redis-server
    systemctl restart redis-server

    log_success "Redis installed"
}

#===============================================================================
# Node.js
#===============================================================================

install_nodejs() {
    log_step "Installing Node.js..."

    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y -qq nodejs

    # Install global packages
    npm install -g npm@latest

    log_success "Node.js $(node --version) installed"
}

#===============================================================================
# Composer
#===============================================================================

install_composer() {
    log_step "Installing Composer..."

    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    log_success "Composer installed"
}

#===============================================================================
# Supervisor
#===============================================================================

install_supervisor() {
    log_step "Installing Supervisor..."

    apt-get install -y -qq supervisor

    systemctl enable supervisor
    systemctl start supervisor

    log_success "Supervisor installed"
}

#===============================================================================
# Application Deployment
#===============================================================================

deploy_application() {
    log_step "Deploying VPSManager application..."

    # Create directory
    mkdir -p "$VPSMANAGER_PATH"

    # Clone repository
    if [[ -d "${VPSMANAGER_PATH}/.git" ]]; then
        log_info "Repository exists, pulling latest..."
        cd "$VPSMANAGER_PATH"
        git fetch origin
        git reset --hard "origin/${VPSMANAGER_BRANCH}"
    else
        log_info "Cloning repository..."
        git clone --branch "$VPSMANAGER_BRANCH" "$VPSMANAGER_REPO" "$VPSMANAGER_PATH"
    fi

    cd "$VPSMANAGER_PATH"

    # Load database credentials
    source /root/.credentials/mysql

    # Create .env file
    if [[ ! -f .env ]]; then
        if [[ -f .env.example ]]; then
            cp .env.example .env
        else
            cat > .env << EOF
APP_NAME=VPSManager
APP_ENV=production
APP_DEBUG=false
APP_URL=https://${VPSMANAGER_DOMAIN}

LOG_CHANNEL=stack
LOG_LEVEL=warning

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_APP_USER}
DB_PASSWORD=${DB_APP_PASS}

CACHE_DRIVER=redis
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

MAIL_MAILER=smtp
MAIL_HOST=
MAIL_PORT=587
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_ENCRYPTION=tls
EOF
        fi
    fi

    # Update .env with correct values
    sed -i "s|^APP_URL=.*|APP_URL=https://${VPSMANAGER_DOMAIN}|" .env
    sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|" .env
    sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${DB_APP_USER}|" .env
    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_APP_PASS}|" .env
    sed -i "s|^APP_ENV=.*|APP_ENV=production|" .env
    sed -i "s|^APP_DEBUG=.*|APP_DEBUG=false|" .env

    # Install dependencies
    log_info "Installing Composer dependencies..."
    composer install --no-dev --optimize-autoloader --no-interaction

    # Generate key if not set
    if ! grep -q "^APP_KEY=base64:" .env; then
        php artisan key:generate --force
    fi

    # Build frontend assets
    if [[ -f package.json ]]; then
        log_info "Building frontend assets..."
        npm ci
        npm run build || npm run production || true
    fi

    # Run migrations
    log_info "Running database migrations..."
    php artisan migrate --force

    # Cache configuration
    log_info "Caching configuration..."
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache

    # Create storage link
    php artisan storage:link || true

    log_success "Application deployed"
}

#===============================================================================
# Nginx Virtual Host
#===============================================================================

configure_nginx_vhost() {
    log_step "Configuring Nginx virtual host..."

    cat > /etc/nginx/sites-available/vpsmanager << EOF
server {
    listen 80;
    server_name ${VPSMANAGER_DOMAIN};
    root ${VPSMANAGER_PATH}/public;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";

    index index.php;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

    # PHP-FPM status for monitoring (localhost only)
    location ~ ^/(fpm-status|fpm-ping)$ {
        access_log off;
        allow 127.0.0.1;
        deny all;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}

# Nginx stub_status for monitoring
server {
    listen 127.0.0.1:8080;
    server_name localhost;

    location /stub_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/vpsmanager /etc/nginx/sites-enabled/

    nginx -t
    log_success "Nginx virtual host configured"
}

#===============================================================================
# SSL Setup
#===============================================================================

setup_ssl() {
    log_step "Setting up SSL certificate..."

    # Start nginx for ACME challenge
    systemctl restart nginx

    # Get certificate
    if certbot --nginx -d "${VPSMANAGER_DOMAIN}" \
        --email "${LETSENCRYPT_EMAIL:-admin@${VPSMANAGER_DOMAIN}}" \
        --agree-tos --non-interactive --redirect; then
        log_success "SSL certificate installed"
    else
        log_warn "SSL certificate failed - check DNS and try again with: certbot --nginx -d ${VPSMANAGER_DOMAIN}"
    fi
}

#===============================================================================
# Supervisor Configuration
#===============================================================================

configure_supervisor() {
    log_step "Configuring Supervisor for Laravel queues..."

    cat > /etc/supervisor/conf.d/vpsmanager-worker.conf << EOF
[program:vpsmanager-worker]
process_name=%(program_name)s_%(process_num)02d
command=php ${VPSMANAGER_PATH}/artisan queue:work redis --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=${VPSMANAGER_USER}
numprocs=2
redirect_stderr=true
stdout_logfile=${VPSMANAGER_PATH}/storage/logs/worker.log
stopwaitsecs=3600
EOF

    # Check if Laravel Horizon is installed
    if [[ -f "${VPSMANAGER_PATH}/artisan" ]] && php "${VPSMANAGER_PATH}/artisan" list 2>/dev/null | grep -q horizon; then
        cat > /etc/supervisor/conf.d/vpsmanager-horizon.conf << EOF
[program:vpsmanager-horizon]
process_name=%(program_name)s
command=php ${VPSMANAGER_PATH}/artisan horizon
autostart=true
autorestart=true
user=${VPSMANAGER_USER}
redirect_stderr=true
stdout_logfile=${VPSMANAGER_PATH}/storage/logs/horizon.log
stopwaitsecs=3600
EOF
        log_info "Laravel Horizon configured"
    fi

    # Add scheduler cron
    (crontab -l 2>/dev/null | grep -v "artisan schedule:run"; echo "* * * * * cd ${VPSMANAGER_PATH} && php artisan schedule:run >> /dev/null 2>&1") | crontab -

    supervisorctl reread
    supervisorctl update

    log_success "Supervisor configured"
}

#===============================================================================
# Permissions
#===============================================================================

set_permissions() {
    log_step "Setting file permissions..."

    chown -R ${VPSMANAGER_USER}:${VPSMANAGER_USER} "$VPSMANAGER_PATH"
    chmod -R 755 "$VPSMANAGER_PATH"
    chmod -R 775 "${VPSMANAGER_PATH}/storage"
    chmod -R 775 "${VPSMANAGER_PATH}/bootstrap/cache"

    # Set ACL for log files
    setfacl -R -m u:${VPSMANAGER_USER}:rwX "${VPSMANAGER_PATH}/storage"
    setfacl -dR -m u:${VPSMANAGER_USER}:rwX "${VPSMANAGER_PATH}/storage"

    log_success "Permissions set"
}

#===============================================================================
# Monitoring Exporters (from monitored.sh)
#===============================================================================

install_node_exporter() {
    log_step "Installing Node Exporter..."

    local arch
    arch=$(get_architecture)
    local tarball="node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}.tar.gz"
    local url="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${tarball}"

    create_system_user node_exporter node_exporter

    cd /tmp
    download_file "$url" "$tarball"
    tar xzf "$tarball"

    # Stop service and verify before binary update
    stop_and_verify_service "node_exporter" "/usr/local/bin/node_exporter" || {
        log_error "Failed to stop node_exporter safely"
        return 1
    }

    cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}/node_exporter" /usr/local/bin/
    rm -rf "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}" "/tmp/${tarball}"

    cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network-online.target

[Service]
Type=simple
User=node_exporter
ExecStart=/usr/local/bin/node_exporter --collector.systemd --collector.processes
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Node Exporter installed"
}

install_nginx_exporter() {
    log_step "Installing Nginx Exporter..."

    local arch
    arch=$(get_architecture)
    local tarball="nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_${arch}.tar.gz"
    local url="https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${NGINX_EXPORTER_VERSION}/${tarball}"

    create_system_user nginx_exporter nginx_exporter

    cd /tmp
    download_file "$url" "$tarball"
    tar xzf "$tarball"

    # Stop service and verify before binary update
    stop_and_verify_service "nginx_exporter" "/usr/local/bin/nginx-prometheus-exporter" || {
        log_error "Failed to stop nginx_exporter safely"
        return 1
    }

    cp nginx-prometheus-exporter /usr/local/bin/
    rm -f "/tmp/${tarball}" /tmp/nginx-prometheus-exporter

    cat > /etc/systemd/system/nginx_exporter.service << 'EOF'
[Unit]
Description=Nginx Exporter
After=network-online.target nginx.service

[Service]
Type=simple
User=nginx_exporter
ExecStart=/usr/local/bin/nginx-prometheus-exporter --nginx.scrape-uri=http://127.0.0.1:8080/stub_status
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Nginx Exporter installed"
}

install_mysqld_exporter() {
    log_step "Installing MySQL Exporter..."

    source /root/.credentials/mysql

    local arch
    arch=$(get_architecture)
    local tarball="mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-${arch}.tar.gz"
    local url="https://github.com/prometheus/mysqld_exporter/releases/download/v${MYSQLD_EXPORTER_VERSION}/${tarball}"

    create_system_user mysqld_exporter mysqld_exporter

    cd /tmp
    download_file "$url" "$tarball"
    tar xzf "$tarball"

    # Stop service and verify before binary update
    stop_and_verify_service "mysqld_exporter" "/usr/local/bin/mysqld_exporter" || {
        log_error "Failed to stop mysqld_exporter safely"
        return 1
    }

    cp "mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-${arch}/mysqld_exporter" /usr/local/bin/
    rm -rf "/tmp/mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-${arch}" "/tmp/${tarball}"

    mkdir -p /etc/mysqld_exporter
    cat > /etc/mysqld_exporter/.my.cnf << EOF
[client]
user=exporter
password=${MYSQL_EXPORTER_PASS}
EOF
    chown -R mysqld_exporter:mysqld_exporter /etc/mysqld_exporter
    chmod 600 /etc/mysqld_exporter/.my.cnf

    cat > /etc/systemd/system/mysqld_exporter.service << 'EOF'
[Unit]
Description=MySQL Exporter
After=network-online.target mariadb.service

[Service]
Type=simple
User=mysqld_exporter
ExecStart=/usr/local/bin/mysqld_exporter --config.my-cnf=/etc/mysqld_exporter/.my.cnf
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "MySQL Exporter installed"
}

install_phpfpm_exporter() {
    log_step "Installing PHP-FPM Exporter..."

    create_system_user phpfpm_exporter phpfpm_exporter

    local arch
    arch=$(get_architecture)
    local url="https://github.com/hipages/php-fpm_exporter/releases/download/v${PHPFPM_EXPORTER_VERSION}/php-fpm_exporter_${PHPFPM_EXPORTER_VERSION}_linux_${arch}"

    download_file "$url" /usr/local/bin/phpfpm_exporter
    chmod +x /usr/local/bin/phpfpm_exporter

    cat > /etc/systemd/system/phpfpm_exporter.service << EOF
[Unit]
Description=PHP-FPM Exporter
After=network-online.target

[Service]
Type=simple
User=phpfpm_exporter
ExecStart=/usr/local/bin/phpfpm_exporter --phpfpm.scrape-uri="tcp://127.0.0.1:8080/fpm-status"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "PHP-FPM Exporter installed"
}

install_promtail() {
    log_step "Installing Promtail..."

    local arch
    arch=$(get_architecture)
    local binary="promtail-linux-${arch}"
    local url="https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/${binary}.zip"

    create_system_user promtail promtail
    usermod -a -G adm promtail
    usermod -a -G www-data promtail

    cd /tmp
    download_file "$url" "promtail.zip"
    unzip -o promtail.zip
    chmod +x "${binary}"

    # Stop service and verify before binary update
    stop_and_verify_service "promtail" "/usr/local/bin/promtail" || {
        log_error "Failed to stop promtail safely"
        return 1
    }

    mv "${binary}" /usr/local/bin/promtail
    rm -f /tmp/promtail.zip

    mkdir -p /etc/promtail /var/lib/promtail
    chown -R promtail:promtail /var/lib/promtail

    cat > /etc/promtail/promtail.yaml << EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://${OBSERVABILITY_IP}:3100/loki/api/v1/push

scrape_configs:
  - job_name: vpsmanager
    static_configs:
      - targets: [localhost]
        labels:
          job: vpsmanager
          host: ${HOST_NAME}
          __path__: ${VPSMANAGER_PATH}/storage/logs/*.log

  - job_name: nginx
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx
          host: ${HOST_NAME}
          __path__: /var/log/nginx/*.log

  - job_name: php-fpm
    static_configs:
      - targets: [localhost]
        labels:
          job: php-fpm
          host: ${HOST_NAME}
          __path__: /var/log/php${PHP_VERSION}-fpm.log

  - job_name: syslog
    static_configs:
      - targets: [localhost]
        labels:
          job: syslog
          host: ${HOST_NAME}
          __path__: /var/log/syslog

  - job_name: mysql
    static_configs:
      - targets: [localhost]
        labels:
          job: mysql
          host: ${HOST_NAME}
          __path__: /var/log/mysql/*.log
EOF

    chown -R promtail:promtail /etc/promtail
    chmod 600 /etc/promtail/promtail.yaml

    cat > /etc/systemd/system/promtail.service << 'EOF'
[Unit]
Description=Promtail
After=network-online.target

[Service]
Type=simple
User=promtail
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail.yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Promtail installed"
}

#===============================================================================
# Firewall
#===============================================================================

setup_firewall_vpsmanager() {
    log_step "Configuring firewall..."

    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing

    # SSH
    ufw allow 22/tcp comment 'SSH'

    # HTTP/HTTPS
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'

    # Metrics (only from observability VPS)
    ufw allow from "${OBSERVABILITY_IP}" to any port 9100 proto tcp comment 'node_exporter'
    ufw allow from "${OBSERVABILITY_IP}" to any port 9113 proto tcp comment 'nginx_exporter'
    ufw allow from "${OBSERVABILITY_IP}" to any port 9104 proto tcp comment 'mysqld_exporter'
    ufw allow from "${OBSERVABILITY_IP}" to any port 9253 proto tcp comment 'phpfpm_exporter'

    ufw --force enable
    log_success "Firewall configured"
}

#===============================================================================
# Start Services
#===============================================================================

start_all_services() {
    log_step "Starting all services..."

    local services=(
        nginx
        "php${PHP_VERSION}-fpm"
        mariadb
        redis-server
        supervisor
        node_exporter
        nginx_exporter
        mysqld_exporter
        phpfpm_exporter
        promtail
    )

    for svc in "${services[@]}"; do
        enable_and_start "$svc" || log_warn "Failed to start $svc"
    done

    log_success "All services started"
}

#===============================================================================
# Post-Deploy
#===============================================================================

run_post_deploy() {
    log_step "Running post-deployment tasks..."

    cd "$VPSMANAGER_PATH"

    # Clear and rebuild caches
    php artisan optimize:clear
    php artisan optimize

    # Restart queue workers
    supervisorctl restart all || true

    log_success "Post-deployment complete"
}

#===============================================================================
# Save Installation Info
#===============================================================================

save_installation_info() {
    log_step "Saving installation info..."

    mkdir -p "$STACK_DIR"

    cat > "$STACK_DIR/.installation" << EOF
# VPSManager Installation
# Generated: $(date -Iseconds)

ROLE=vpsmanager
HOST_NAME=${HOST_NAME}
HOST_IP=${HOST_IP}
OBSERVABILITY_IP=${OBSERVABILITY_IP}

VPSMANAGER_DOMAIN=${VPSMANAGER_DOMAIN}
VPSMANAGER_REPO=${VPSMANAGER_REPO}
VPSMANAGER_PATH=${VPSMANAGER_PATH}

PHP_VERSION=${PHP_VERSION}

# Services installed
SERVICES=(nginx php-fpm mariadb redis supervisor)
EXPORTERS=(node_exporter nginx_exporter mysqld_exporter phpfpm_exporter promtail)
EOF

    chmod 600 "$STACK_DIR/.installation"

    # Generate Prometheus target file
    cat > "/tmp/${HOST_NAME}-targets.yaml" << EOF
# Prometheus targets for ${HOST_NAME} (VPSManager)
# Copy to /etc/prometheus/targets/ on Observability VPS

- targets: ['${HOST_IP}:9100']
  labels:
    instance: ${HOST_NAME}
    job: node
    app: vpsmanager

- targets: ['${HOST_IP}:9113']
  labels:
    instance: ${HOST_NAME}
    job: nginx
    app: vpsmanager

- targets: ['${HOST_IP}:9104']
  labels:
    instance: ${HOST_NAME}
    job: mysql
    app: vpsmanager

- targets: ['${HOST_IP}:9253']
  labels:
    instance: ${HOST_NAME}
    job: phpfpm
    app: vpsmanager
EOF

    log_success "Installation info saved"
}
