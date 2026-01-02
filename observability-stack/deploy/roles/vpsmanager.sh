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
# - All monitoring exporters + Promtail/Alloy
#
# Exporter Ports:
# - node_exporter:    9100
# - nginx_exporter:   9113
# - mysqld_exporter:  9104
# - phpfpm_exporter:  9253
# - promtail:         9080 (if using Promtail)
# - alloy:            12345 (if using Alloy)
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

# Telemetry collector choice: promtail or alloy
TELEMETRY_COLLECTOR="${TELEMETRY_COLLECTOR:-promtail}"

# Exporter versions
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-1.7.0}"
PROMTAIL_VERSION="${PROMTAIL_VERSION:-3.0.0}"
ALLOY_VERSION="${ALLOY_VERSION:-1.0.0}"
NGINX_EXPORTER_VERSION="${NGINX_EXPORTER_VERSION:-1.1.0}"
MYSQLD_EXPORTER_VERSION="${MYSQLD_EXPORTER_VERSION:-0.15.1}"
PHPFPM_EXPORTER_VERSION="${PHPFPM_EXPORTER_VERSION:-0.6.0}"

# Standard exporter ports
readonly NODE_EXPORTER_PORT=9100
readonly NGINX_EXPORTER_PORT=9113
readonly MYSQLD_EXPORTER_PORT=9104
readonly PHPFPM_EXPORTER_PORT=9253
readonly PROMTAIL_PORT=9080
readonly ALLOY_PORT=12345

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

    # Install monitoring exporters
    install_node_exporter
    install_nginx_exporter
    install_mysqld_exporter
    install_phpfpm_exporter

    # Install telemetry collector based on choice
    case "${TELEMETRY_COLLECTOR,,}" in
        alloy)
            install_alloy
            ;;
        promtail|*)
            install_promtail
            ;;
    esac

    setup_firewall_vpsmanager
    start_all_services

    # Run comprehensive health checks
    run_health_checks || log_warn "Some health checks failed - review above"

    # Generate Prometheus targets file
    generate_prometheus_targets

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

    if [[ -z "${HOST_NAME:-}" ]]; then
        log_error "HOST_NAME is required"
        exit 1
    fi

    if [[ -z "${HOST_IP:-}" ]]; then
        log_error "HOST_IP is required"
        exit 1
    fi

    if [[ -z "${OBSERVABILITY_IP:-}" ]]; then
        log_error "OBSERVABILITY_IP is required"
        exit 1
    fi

    # Validate telemetry collector choice
    if [[ "${TELEMETRY_COLLECTOR,,}" != "promtail" ]] && [[ "${TELEMETRY_COLLECTOR,,}" != "alloy" ]]; then
        log_warn "Unknown TELEMETRY_COLLECTOR: ${TELEMETRY_COLLECTOR}, defaulting to promtail"
        TELEMETRY_COLLECTOR="promtail"
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
        cron \
        dnsutils

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

    # Create keyrings directory if it doesn't exist
    mkdir -p /etc/apt/keyrings

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
        php${PHP_VERSION}-tokenizer || true

    # Configure PHP-FPM
    configure_phpfpm_for_monitoring

    log_success "PHP ${PHP_VERSION} installed"
}

configure_phpfpm_for_monitoring() {
    log_step "Configuring PHP-FPM for monitoring..."

    local fpm_conf="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

    if [[ ! -f "$fpm_conf" ]]; then
        log_warn "PHP-FPM pool config not found at $fpm_conf"
        return 1
    fi

    # Enable status page for monitoring (required for phpfpm_exporter)
    # Uncomment and set pm.status_path
    if grep -q "^;pm.status_path" "$fpm_conf"; then
        sed -i 's/^;pm.status_path.*/pm.status_path = \/fpm-status/' "$fpm_conf"
    elif ! grep -q "^pm.status_path" "$fpm_conf"; then
        echo "pm.status_path = /fpm-status" >> "$fpm_conf"
    fi

    # Uncomment and set ping.path
    if grep -q "^;ping.path" "$fpm_conf"; then
        sed -i 's/^;ping.path.*/ping.path = \/fpm-ping/' "$fpm_conf"
    elif ! grep -q "^ping.path" "$fpm_conf"; then
        echo "ping.path = /fpm-ping" >> "$fpm_conf"
    fi

    # Performance tuning
    sed -i 's/^pm = .*/pm = dynamic/' "$fpm_conf"
    sed -i 's/^pm.max_children = .*/pm.max_children = 20/' "$fpm_conf"
    sed -i 's/^pm.start_servers = .*/pm.start_servers = 5/' "$fpm_conf"
    sed -i 's/^pm.min_spare_servers = .*/pm.min_spare_servers = 3/' "$fpm_conf"
    sed -i 's/^pm.max_spare_servers = .*/pm.max_spare_servers = 10/' "$fpm_conf"

    # PHP.ini optimization
    local php_ini="/etc/php/${PHP_VERSION}/fpm/php.ini"
    if [[ -f "$php_ini" ]]; then
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' "$php_ini"
        sed -i 's/^post_max_size = .*/post_max_size = 100M/' "$php_ini"
        sed -i 's/^memory_limit = .*/memory_limit = 256M/' "$php_ini"
        sed -i 's/^max_execution_time = .*/max_execution_time = 120/' "$php_ini"
        sed -i 's/^;opcache.enable=.*/opcache.enable=1/' "$php_ini"
        sed -i 's/^;opcache.memory_consumption=.*/opcache.memory_consumption=256/' "$php_ini"
    fi

    log_success "PHP-FPM configured for monitoring"
}

#===============================================================================
# MariaDB
#===============================================================================

install_mariadb() {
    log_step "Installing MariaDB..."

    # Check if MariaDB is already installed
    local mariadb_installed=false
    if command -v mysql &>/dev/null && systemctl is-active --quiet mariadb 2>/dev/null; then
        mariadb_installed=true
        log_info "MariaDB is already installed and running"
    fi

    # Install if not present
    if ! $mariadb_installed; then
        apt-get install -y -qq mariadb-server mariadb-client

        # Start MariaDB
        systemctl enable mariadb
        systemctl start mariadb
    fi

    # Check if root password is already set
    local root_password_set=false
    if ! mysql -e "SELECT 1" &>/dev/null; then
        root_password_set=true
    fi

    # Handle password configuration
    if $mariadb_installed && $root_password_set; then
        log_warn "MariaDB root password is already configured"

        # Check if credentials file exists
        if [[ -f /root/.credentials/mysql ]]; then
            log_info "Loading existing credentials from /root/.credentials/mysql"
            source /root/.credentials/mysql

            # Test the credentials
            if mysql -u root -p"${DB_ROOT_PASS}" -e "SELECT 1" &>/dev/null 2>&1; then
                log_success "Existing credentials validated"
            else
                log_error "Credentials file exists but password is incorrect"
                if [[ "${NON_INTERACTIVE:-false}" == "true" ]]; then
                    log_error "Cannot prompt for password in non-interactive mode"
                    return 1
                fi
                read -s -p "Enter MariaDB root password: " DB_ROOT_PASS
                echo

                if ! mysql -u root -p"${DB_ROOT_PASS}" -e "SELECT 1" &>/dev/null 2>&1; then
                    log_error "Authentication failed"
                    return 1
                fi
            fi
        else
            log_warn "No credentials file found"
            if [[ "${NON_INTERACTIVE:-false}" == "true" ]]; then
                log_error "Cannot prompt for password in non-interactive mode"
                return 1
            fi
            read -s -p "Enter existing MariaDB root password: " DB_ROOT_PASS
            echo

            if ! mysql -u root -p"${DB_ROOT_PASS}" -e "SELECT 1" &>/dev/null 2>&1; then
                log_error "Authentication failed"
                return 1
            fi

            log_success "Root password validated"
        fi
    else
        # Fresh installation - generate and set new password
        DB_ROOT_PASS=$(generate_password)

        log_info "Setting up MariaDB with new root password..."
        mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';" || {
            log_error "Failed to set root password"
            return 1
        }

        # Secure installation
        mysql -u root -p"${DB_ROOT_PASS}" -e "DELETE FROM mysql.user WHERE User='';"
        mysql -u root -p"${DB_ROOT_PASS}" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
        mysql -u root -p"${DB_ROOT_PASS}" -e "DROP DATABASE IF EXISTS test;"
        mysql -u root -p"${DB_ROOT_PASS}" -e "FLUSH PRIVILEGES;"

        log_success "MariaDB secured"
    fi

    # Generate application password if not already set
    if [[ -z "${DB_APP_PASS:-}" ]]; then
        DB_APP_PASS=$(generate_password)
    fi

    # Create application database and user
    log_step "Setting up application database..."
    mysql -u root -p"${DB_ROOT_PASS}" << EOF
CREATE DATABASE IF NOT EXISTS vpsmanager CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'vpsmanager'@'localhost' IDENTIFIED BY '${DB_APP_PASS}';
GRANT ALL PRIVILEGES ON vpsmanager.* TO 'vpsmanager'@'localhost';
FLUSH PRIVILEGES;
EOF

    # Create exporter user for monitoring
    if [[ -z "${MYSQL_EXPORTER_PASS:-}" ]]; then
        MYSQL_EXPORTER_PASS=$(generate_password)
    fi

    log_step "Setting up database exporter user..."
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

    log_success "MariaDB configured (credentials saved to /root/.credentials/mysql)"
}

#===============================================================================
# Redis
#===============================================================================

install_redis() {
    log_step "Installing Redis..."

    apt-get install -y -qq redis-server

    # Generate secure Redis password
    REDIS_PASSWORD=$(openssl rand -base64 16)

    # Configure Redis
    sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf
    sed -i 's/^# maxmemory .*/maxmemory 256mb/' /etc/redis/redis.conf
    sed -i 's/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf

    # Add password protection
    sed -i "s/^# requirepass .*/requirepass ${REDIS_PASSWORD}/" /etc/redis/redis.conf

    # Bind to localhost only (security)
    sed -i 's/^bind .*/bind 127.0.0.1 ::1/' /etc/redis/redis.conf

    # Save credentials
    mkdir -p /root/.credentials
    echo "REDIS_PASSWORD=${REDIS_PASSWORD}" > /root/.credentials/redis
    chmod 600 /root/.credentials/redis

    systemctl enable redis-server
    systemctl restart redis-server

    # Test connection
    if redis-cli -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q PONG; then
        log_success "Redis installed and secured with password"
        log_info "Redis password saved to /root/.credentials/redis"
    else
        log_error "Redis authentication test failed"
        return 1
    fi

    # Export for use in Laravel .env
    export REDIS_PASSWORD
}

#===============================================================================
# Node.js
#===============================================================================

install_nodejs() {
    log_step "Installing Node.js..."

    # Pin to specific LTS version for stability
    local NODE_VERSION="20.11.1"
    local NPM_VERSION="10.2.5"

    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -

    # Install specific version
    apt-get install -y -qq "nodejs=${NODE_VERSION}*" || {
        log_warn "Specific version ${NODE_VERSION} not available, installing latest 20.x"
        apt-get install -y -qq nodejs
    }

    # Hold version to prevent auto-upgrades
    apt-mark hold nodejs

    # Verify installed version
    local installed_version
    installed_version=$(node --version | tr -d 'v')
    log_info "Node.js version: $installed_version"

    # Pin npm version for consistency
    npm install -g "npm@${NPM_VERSION}" || true

    log_success "Node.js $(node --version) installed and version pinned"
    log_info "To upgrade: apt-mark unhold nodejs && apt-get install nodejs"
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
REDIS_PASSWORD=${REDIS_PASSWORD}
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
    sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=${REDIS_PASSWORD}|" .env
    sed -i "s|^APP_ENV=.*|APP_ENV=production|" .env
    sed -i "s|^APP_DEBUG=.*|APP_DEBUG=false|" .env

    # Secure .env file permissions (contains sensitive credentials)
    chmod 600 .env
    chown ${VPSMANAGER_USER}:${VPSMANAGER_USER} .env
    log_success ".env file secured with 600 permissions"

    # Verify .env is in .gitignore
    if [[ ! -f .gitignore ]] || ! grep -q "^\.env$" .gitignore; then
        echo ".env" >> .gitignore
        log_info "Added .env to .gitignore"
    fi

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

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

    # Content Security Policy (adjust based on your assets)
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self';" always;

    # HSTS will be added by SSL setup automatically

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

    # Skip SSL for IP-based domains
    if [[ "$VPSMANAGER_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_warn "Domain is an IP address - SSL certificates not available for IP addresses"
        log_info "Application will be accessible via HTTP only"
        return 0
    fi

    # Skip if explicitly requested
    if [[ "${SKIP_SSL:-false}" == "true" ]]; then
        log_info "Skipping SSL setup (SKIP_SSL=true)"
        return 0
    fi

    # Get server's public IP
    local server_ip
    server_ip=$(curl -s4 https://ifconfig.me)

    # Validate DNS before attempting SSL
    log_info "Validating DNS for ${VPSMANAGER_DOMAIN}..."
    local domain_ip
    domain_ip=$(dig +short "${VPSMANAGER_DOMAIN}" A | grep -E '^[0-9.]+$' | head -1)

    if [[ -z "$domain_ip" ]]; then
        log_error "DNS not configured for ${VPSMANAGER_DOMAIN}"
        log_error "Please add an A record pointing to ${server_ip}"
        log_warn "Skipping SSL setup - domain is not yet accessible"
        return 1
    fi

    if [[ "$domain_ip" != "$server_ip" ]]; then
        log_warn "DNS mismatch: domain points to $domain_ip but server IP is $server_ip"
        log_warn "SSL certificate acquisition may fail"
        if [[ "${NON_INTERACTIVE:-false}" != "true" ]]; then
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_warn "Skipping SSL setup"
                return 1
            fi
        else
            log_warn "Non-interactive mode: skipping SSL setup due to DNS mismatch"
            return 1
        fi
    else
        log_success "DNS validated: ${VPSMANAGER_DOMAIN} -> ${server_ip}"
    fi

    # Start nginx for ACME challenge
    systemctl restart nginx

    # Get certificate
    if certbot --nginx -d "${VPSMANAGER_DOMAIN}" \
        --email "${LETSENCRYPT_EMAIL:-admin@${VPSMANAGER_DOMAIN}}" \
        --agree-tos --non-interactive --redirect; then

        # Verify certificate was actually installed
        if openssl s_client -connect "${VPSMANAGER_DOMAIN}:443" -servername "${VPSMANAGER_DOMAIN}" </dev/null 2>&1 | grep -q "Verify return code: 0"; then
            log_success "SSL certificate installed and validated"

            # Enable auto-renewal
            systemctl enable certbot.timer 2>/dev/null || true
            systemctl start certbot.timer 2>/dev/null || true

            log_info "Auto-renewal enabled via certbot.timer"
        else
            log_error "SSL certificate installed but validation failed"
            log_error "Certificate may not be properly configured"
            return 1
        fi
    else
        log_error "SSL certificate acquisition failed"
        log_error "Troubleshooting steps:"
        log_error "  1. Verify DNS: dig ${VPSMANAGER_DOMAIN}"
        log_error "  2. Check firewall: ufw status | grep -E '80|443'"
        log_error "  3. Manual retry: certbot --nginx -d ${VPSMANAGER_DOMAIN}"
        log_warn "Application will continue with HTTP-only access"
        return 1
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
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
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
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stopwaitsecs=3600
EOF
        log_info "Laravel Horizon configured"
    fi

    # Configure logrotate for Laravel logs
    cat > /etc/logrotate.d/vpsmanager << EOF
${VPSMANAGER_PATH}/storage/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 ${VPSMANAGER_USER} ${VPSMANAGER_USER}
    sharedscripts
    postrotate
        supervisorctl signal HUP vpsmanager-worker:*
    endscript
}
EOF
    log_info "Log rotation configured (14-day retention)"

    # Add scheduler cron
    (crontab -l 2>/dev/null | grep -v "artisan schedule:run"; echo "* * * * * cd ${VPSMANAGER_PATH} && php artisan schedule:run >> /dev/null 2>&1") | crontab -

    supervisorctl reread
    supervisorctl update

    log_success "Supervisor configured with log rotation"
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
# Monitoring Exporters
#===============================================================================

install_node_exporter() {
    log_step "Installing Node Exporter ${NODE_EXPORTER_VERSION}..."

    local arch
    arch=$(get_architecture)
    local tarball="node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}.tar.gz"
    local url="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${tarball}"

    create_system_user node_exporter node_exporter

    cd /tmp
    download_file "$url" "$tarball"
    tar xzf "$tarball"

    # Stop service and verify before binary update
    stop_and_verify_service "node_exporter" "/usr/local/bin/node_exporter" || true

    cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}/node_exporter" /usr/local/bin/
    chmod 755 /usr/local/bin/node_exporter
    rm -rf "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-${arch}" "/tmp/${tarball}"

    cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter \\
    --collector.systemd \\
    --collector.processes \\
    --collector.filesystem.mount-points-exclude='^/(sys|proc|dev|host|etc)(\$\$|/)' \\
    --web.listen-address=':${NODE_EXPORTER_PORT}' \\
    --web.telemetry-path='/metrics'
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
TimeoutStopSec=20

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadOnlyPaths=/

# Resource limits
MemoryMax=128M
CPUQuota=25%

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Node Exporter ${NODE_EXPORTER_VERSION} installed (port ${NODE_EXPORTER_PORT})"
}

install_nginx_exporter() {
    log_step "Installing Nginx Exporter ${NGINX_EXPORTER_VERSION}..."

    local arch
    arch=$(get_architecture)
    local tarball="nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_${arch}.tar.gz"
    local url="https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${NGINX_EXPORTER_VERSION}/${tarball}"

    create_system_user nginx_exporter nginx_exporter

    cd /tmp
    download_file "$url" "$tarball"
    tar xzf "$tarball"

    # Stop service and verify before binary update
    stop_and_verify_service "nginx_exporter" "/usr/local/bin/nginx-prometheus-exporter" || true

    cp nginx-prometheus-exporter /usr/local/bin/
    chmod 755 /usr/local/bin/nginx-prometheus-exporter
    rm -f "/tmp/${tarball}" /tmp/nginx-prometheus-exporter

    cat > /etc/systemd/system/nginx_exporter.service << EOF
[Unit]
Description=Prometheus Nginx Exporter
Documentation=https://github.com/nginxinc/nginx-prometheus-exporter
After=network-online.target nginx.service
Wants=network-online.target
BindsTo=nginx.service

[Service]
Type=simple
User=nginx_exporter
Group=nginx_exporter
ExecStart=/usr/local/bin/nginx-prometheus-exporter \\
    --nginx.scrape-uri='http://127.0.0.1:8080/stub_status' \\
    --web.listen-address=':${NGINX_EXPORTER_PORT}' \\
    --web.telemetry-path='/metrics'
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
TimeoutStopSec=20

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadOnlyPaths=/

# Resource limits
MemoryMax=64M
CPUQuota=10%

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Nginx Exporter ${NGINX_EXPORTER_VERSION} installed (port ${NGINX_EXPORTER_PORT})"
}

install_mysqld_exporter() {
    log_step "Installing MySQL Exporter ${MYSQLD_EXPORTER_VERSION}..."

    # Source credentials if available
    if [[ -f /root/.credentials/mysql ]]; then
        source /root/.credentials/mysql
    fi

    local arch
    arch=$(get_architecture)
    local tarball="mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-${arch}.tar.gz"
    local url="https://github.com/prometheus/mysqld_exporter/releases/download/v${MYSQLD_EXPORTER_VERSION}/${tarball}"

    create_system_user mysqld_exporter mysqld_exporter

    cd /tmp
    download_file "$url" "$tarball"
    tar xzf "$tarball"

    # Stop service and verify before binary update
    stop_and_verify_service "mysqld_exporter" "/usr/local/bin/mysqld_exporter" || true

    cp "mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-${arch}/mysqld_exporter" /usr/local/bin/
    chmod 755 /usr/local/bin/mysqld_exporter
    rm -rf "/tmp/mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-${arch}" "/tmp/${tarball}"

    mkdir -p /etc/mysqld_exporter
    cat > /etc/mysqld_exporter/.my.cnf << EOF
[client]
user=exporter
password=${MYSQL_EXPORTER_PASS:-exporter_password}
host=127.0.0.1
port=3306
EOF
    chown -R mysqld_exporter:mysqld_exporter /etc/mysqld_exporter
    chmod 600 /etc/mysqld_exporter/.my.cnf

    cat > /etc/systemd/system/mysqld_exporter.service << EOF
[Unit]
Description=Prometheus MySQL/MariaDB Exporter
Documentation=https://github.com/prometheus/mysqld_exporter
After=network-online.target mariadb.service mysql.service
Wants=network-online.target

[Service]
Type=simple
User=mysqld_exporter
Group=mysqld_exporter
ExecStart=/usr/local/bin/mysqld_exporter \\
    --config.my-cnf=/etc/mysqld_exporter/.my.cnf \\
    --web.listen-address=':${MYSQLD_EXPORTER_PORT}' \\
    --web.telemetry-path='/metrics' \\
    --collect.info_schema.tables \\
    --collect.info_schema.innodb_metrics \\
    --collect.global_status \\
    --collect.global_variables \\
    --collect.slave_status \\
    --collect.engine_innodb_status
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
TimeoutStopSec=20

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadOnlyPaths=/
ReadWritePaths=/etc/mysqld_exporter

# Resource limits
MemoryMax=64M
CPUQuota=10%

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "MySQL Exporter ${MYSQLD_EXPORTER_VERSION} installed (port ${MYSQLD_EXPORTER_PORT})"
}

install_phpfpm_exporter() {
    log_step "Installing PHP-FPM Exporter ${PHPFPM_EXPORTER_VERSION}..."

    create_system_user phpfpm_exporter phpfpm_exporter
    # Add to www-data group to access PHP-FPM socket
    usermod -a -G www-data phpfpm_exporter 2>/dev/null || true

    local arch
    arch=$(get_architecture)
    local url="https://github.com/hipages/php-fpm_exporter/releases/download/v${PHPFPM_EXPORTER_VERSION}/php-fpm_exporter_${PHPFPM_EXPORTER_VERSION}_linux_${arch}"

    # Stop service and verify before binary update
    stop_and_verify_service "phpfpm_exporter" "/usr/local/bin/phpfpm_exporter" || true

    download_file "$url" /usr/local/bin/phpfpm_exporter
    chmod 755 /usr/local/bin/phpfpm_exporter

    # Find PHP-FPM socket dynamically
    local fpm_socket
    fpm_socket=$(find /run/php/ -name "php*-fpm.sock" 2>/dev/null | head -1)
    if [[ -z "$fpm_socket" ]]; then
        fpm_socket="/run/php/php${PHP_VERSION}-fpm.sock"
    fi

    # Verify socket exists and is accessible
    if [[ ! -S "$fpm_socket" ]]; then
        log_warn "PHP-FPM socket not found at $fpm_socket"
        log_info "PHP-FPM exporter will wait for socket to become available"
    fi

    # Create systemd service - use unix socket format for PHP-FPM status
    # The hipages exporter uses: unix://<socket_path>;<status_path>
    cat > /etc/systemd/system/phpfpm_exporter.service << EOF
[Unit]
Description=PHP-FPM Exporter for Prometheus
Documentation=https://github.com/hipages/php-fpm_exporter
After=network-online.target php${PHP_VERSION}-fpm.service
Wants=network-online.target
Requires=php${PHP_VERSION}-fpm.service

[Service]
Type=simple
User=phpfpm_exporter
Group=phpfpm_exporter
# Use unix socket format: unix://<socket>;<status_path>
ExecStart=/usr/local/bin/phpfpm_exporter server \\
    --phpfpm.scrape-uri="unix://${fpm_socket};/fpm-status" \\
    --web.listen-address=":${PHPFPM_EXPORTER_PORT}" \\
    --web.telemetry-path="/metrics"
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
TimeoutStopSec=20

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadOnlyPaths=/

# Resource limits
MemoryMax=64M
CPUQuota=10%

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "PHP-FPM Exporter ${PHPFPM_EXPORTER_VERSION} installed (port ${PHPFPM_EXPORTER_PORT}, socket: ${fpm_socket})"
}

#===============================================================================
# Telemetry Collectors
#===============================================================================

install_promtail() {
    log_step "Installing Promtail ${PROMTAIL_VERSION}..."

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

    # Stop service and verify before binary update
    stop_and_verify_service "promtail" "/usr/local/bin/promtail" || true

    chmod +x "${binary}"
    mv "${binary}" /usr/local/bin/promtail
    rm -f /tmp/promtail.zip

    mkdir -p /etc/promtail /var/lib/promtail
    chown -R promtail:promtail /var/lib/promtail

    # Determine environment (production vs test)
    local app_env="${APP_ENV:-production}"
    if [[ "${HOST_NAME}" == *"_tst"* ]] || [[ "${HOST_NAME}" == *"-tst"* ]]; then
        app_env="test"
    fi

    cat > /etc/promtail/promtail.yaml << EOF
# Promtail Configuration for VPSManager/CHOM
# Host: ${HOST_NAME}
# Environment: ${app_env}
# Generated: $(date -Iseconds)

server:
  http_listen_port: ${PROMTAIL_PORT}
  grpc_listen_port: 0
  log_level: info

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://${OBSERVABILITY_IP}:3100/loki/api/v1/push
    tenant_id: ${HOST_NAME}
    batchwait: 1s
    batchsize: 1048576
    external_labels:
      host: ${HOST_NAME}
      env: ${app_env}
      app: chom

scrape_configs:
  # Laravel Application Logs
  - job_name: laravel
    static_configs:
      - targets: [localhost]
        labels:
          job: vpsmanager-laravel
          app: chom
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: ${VPSMANAGER_PATH}/storage/logs/*.log
    pipeline_stages:
      # Parse Laravel log format: [YYYY-MM-DD HH:MM:SS] environment.LEVEL: message
      - multiline:
          firstline: '^\[\d{4}-\d{2}-\d{2}'
          max_wait_time: 3s
      - regex:
          expression: '^\[(?P<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] (?P<channel>\w+)\.(?P<level>\w+): (?P<message>.*)'
      - labels:
          level:
          channel:
      - timestamp:
          source: timestamp
          format: '2006-01-02 15:04:05'

  # Laravel Worker/Queue Logs
  - job_name: laravel-worker
    static_configs:
      - targets: [localhost]
        labels:
          job: vpsmanager-worker
          app: chom
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: ${VPSMANAGER_PATH}/storage/logs/worker*.log
    pipeline_stages:
      - multiline:
          firstline: '^\[\d{4}-\d{2}-\d{2}'
          max_wait_time: 3s

  # Nginx Access Logs
  - job_name: nginx-access
    static_configs:
      - targets: [localhost]
        labels:
          job: vpsmanager-nginx
          log_type: access
          app: chom
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/nginx/access.log
    pipeline_stages:
      # Parse combined log format
      - regex:
          expression: '^(?P<remote_addr>[\w\.]+) - (?P<remote_user>\S+) \[(?P<time_local>[^\]]+)\] "(?P<method>\S+) (?P<request_uri>\S+) (?P<protocol>\S+)" (?P<status>\d+) (?P<body_bytes_sent>\d+) "(?P<http_referer>[^"]*)" "(?P<http_user_agent>[^"]*)"'
      - labels:
          method:
          status:

  # Nginx Error Logs
  - job_name: nginx-error
    static_configs:
      - targets: [localhost]
        labels:
          job: vpsmanager-nginx
          log_type: error
          app: chom
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/nginx/error.log
    pipeline_stages:
      - regex:
          expression: '^(?P<timestamp>\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) \[(?P<level>\w+)\] (?P<message>.*)'
      - labels:
          level:

  # PHP-FPM Logs
  - job_name: php-fpm
    static_configs:
      - targets: [localhost]
        labels:
          job: vpsmanager-phpfpm
          app: chom
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/php${PHP_VERSION}-fpm.log
    pipeline_stages:
      - regex:
          expression: '^\[(?P<timestamp>[^\]]+)\] (?P<level>\w+): (?P<message>.*)'
      - labels:
          level:

  # MySQL/MariaDB Logs
  - job_name: mysql
    static_configs:
      - targets: [localhost]
        labels:
          job: vpsmanager-mysql
          app: chom
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/mysql/*.log

  # MySQL Slow Query Log
  - job_name: mysql-slow
    static_configs:
      - targets: [localhost]
        labels:
          job: vpsmanager-mysql
          log_type: slow-query
          app: chom
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/mysql/mysql-slow.log
    pipeline_stages:
      - multiline:
          firstline: '^# Time:'
          max_wait_time: 3s

  # System Syslog
  - job_name: syslog
    static_configs:
      - targets: [localhost]
        labels:
          job: syslog
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/syslog

  # Auth Logs (security monitoring)
  - job_name: auth
    static_configs:
      - targets: [localhost]
        labels:
          job: auth
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/auth.log

  # Supervisor Logs
  - job_name: supervisor
    static_configs:
      - targets: [localhost]
        labels:
          job: vpsmanager-supervisor
          app: chom
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/supervisor/*.log

  # Redis Logs
  - job_name: redis
    static_configs:
      - targets: [localhost]
        labels:
          job: vpsmanager-redis
          app: chom
          host: ${HOST_NAME}
          env: ${app_env}
          __path__: /var/log/redis/*.log
EOF

    chown -R promtail:promtail /etc/promtail
    chmod 600 /etc/promtail/promtail.yaml

    cat > /etc/systemd/system/promtail.service << EOF
[Unit]
Description=Promtail Log Collector
Documentation=https://grafana.com/docs/loki/latest/clients/promtail/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=promtail
Group=promtail
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail.yaml
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
TimeoutStopSec=30

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/var/lib/promtail
ReadOnlyPaths=/etc/promtail /var/log ${VPSMANAGER_PATH}/storage/logs

# Resource limits
MemoryMax=256M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
EOF

    # Configure log rotation for Promtail positions
    cat > /etc/logrotate.d/promtail << 'EOF'
/var/lib/promtail/*.yaml {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 promtail promtail
}
EOF

    systemctl daemon-reload
    log_success "Promtail ${PROMTAIL_VERSION} installed (port ${PROMTAIL_PORT})"
}

install_alloy() {
    log_step "Installing Grafana Alloy ${ALLOY_VERSION}..."

    local arch
    arch=$(get_architecture)

    # Map architecture for Alloy download
    local alloy_arch="$arch"
    case "$arch" in
        amd64) alloy_arch="linux-amd64" ;;
        arm64) alloy_arch="linux-arm64" ;;
    esac

    local binary="alloy-${alloy_arch}"
    local url="https://github.com/grafana/alloy/releases/download/v${ALLOY_VERSION}/${binary}.zip"

    create_system_user alloy alloy
    usermod -a -G adm alloy
    usermod -a -G www-data alloy

    cd /tmp
    download_file "$url" "alloy.zip"
    unzip -o alloy.zip

    # Stop service and verify before binary update
    stop_and_verify_service "alloy" "/usr/local/bin/alloy" || true

    chmod +x "${binary}"
    mv "${binary}" /usr/local/bin/alloy
    rm -f /tmp/alloy.zip

    mkdir -p /etc/alloy /var/lib/alloy
    chown -R alloy:alloy /var/lib/alloy

    # Determine environment
    local app_env="${APP_ENV:-production}"
    if [[ "${HOST_NAME}" == *"_tst"* ]] || [[ "${HOST_NAME}" == *"-tst"* ]]; then
        app_env="test"
    fi

    # Create Alloy configuration (River format)
    cat > /etc/alloy/config.alloy << EOF
// Grafana Alloy Configuration for VPSManager/CHOM
// Host: ${HOST_NAME}
// Environment: ${app_env}
// Generated: $(date -Iseconds)

// HTTP server configuration
server {
    http_listen_addr = "0.0.0.0:${ALLOY_PORT}"
    log_level        = "info"
}

// Common labels for all logs
local.file "hostname" {
    filename = "/etc/hostname"
}

// Loki destination
loki.write "default" {
    endpoint {
        url        = "http://${OBSERVABILITY_IP}:3100/loki/api/v1/push"
        tenant_id  = "${HOST_NAME}"
    }
    external_labels = {
        host = "${HOST_NAME}",
        env  = "${app_env}",
        app  = "chom",
    }
}

// Laravel Application Logs
loki.source.file "laravel" {
    targets = [
        {__path__ = "${VPSMANAGER_PATH}/storage/logs/*.log", job = "vpsmanager-laravel"},
    ]
    forward_to = [loki.process.laravel.receiver]
}

loki.process "laravel" {
    stage.multiline {
        firstline     = "^\\[\\d{4}-\\d{2}-\\d{2}"
        max_wait_time = "3s"
    }
    stage.regex {
        expression = "^\\[(?P<timestamp>\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})\\] (?P<channel>\\w+)\\.(?P<level>\\w+): (?P<message>.*)"
    }
    stage.labels {
        values = {
            level   = "",
            channel = "",
        }
    }
    forward_to = [loki.write.default.receiver]
}

// Nginx Logs
loki.source.file "nginx" {
    targets = [
        {__path__ = "/var/log/nginx/access.log", job = "vpsmanager-nginx", log_type = "access"},
        {__path__ = "/var/log/nginx/error.log", job = "vpsmanager-nginx", log_type = "error"},
    ]
    forward_to = [loki.write.default.receiver]
}

// PHP-FPM Logs
loki.source.file "phpfpm" {
    targets = [
        {__path__ = "/var/log/php${PHP_VERSION}-fpm.log", job = "vpsmanager-phpfpm"},
    ]
    forward_to = [loki.write.default.receiver]
}

// MySQL/MariaDB Logs
loki.source.file "mysql" {
    targets = [
        {__path__ = "/var/log/mysql/*.log", job = "vpsmanager-mysql"},
    ]
    forward_to = [loki.write.default.receiver]
}

// System Logs
loki.source.file "system" {
    targets = [
        {__path__ = "/var/log/syslog", job = "syslog"},
        {__path__ = "/var/log/auth.log", job = "auth"},
    ]
    forward_to = [loki.write.default.receiver]
}

// Supervisor Logs
loki.source.file "supervisor" {
    targets = [
        {__path__ = "/var/log/supervisor/*.log", job = "vpsmanager-supervisor"},
    ]
    forward_to = [loki.write.default.receiver]
}

// Redis Logs
loki.source.file "redis" {
    targets = [
        {__path__ = "/var/log/redis/*.log", job = "vpsmanager-redis"},
    ]
    forward_to = [loki.write.default.receiver]
}
EOF

    chown -R alloy:alloy /etc/alloy
    chmod 600 /etc/alloy/config.alloy

    cat > /etc/systemd/system/alloy.service << EOF
[Unit]
Description=Grafana Alloy Telemetry Collector
Documentation=https://grafana.com/docs/alloy/latest/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=alloy
Group=alloy
ExecStart=/usr/local/bin/alloy run /etc/alloy/config.alloy --storage.path=/var/lib/alloy
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
TimeoutStopSec=30

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/var/lib/alloy
ReadOnlyPaths=/etc/alloy /var/log ${VPSMANAGER_PATH}/storage/logs

# Resource limits
MemoryMax=256M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Grafana Alloy ${ALLOY_VERSION} installed (port ${ALLOY_PORT})"
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
    ufw allow from "${OBSERVABILITY_IP}" to any port ${NODE_EXPORTER_PORT} proto tcp comment 'node_exporter'
    ufw allow from "${OBSERVABILITY_IP}" to any port ${NGINX_EXPORTER_PORT} proto tcp comment 'nginx_exporter'
    ufw allow from "${OBSERVABILITY_IP}" to any port ${MYSQLD_EXPORTER_PORT} proto tcp comment 'mysqld_exporter'
    ufw allow from "${OBSERVABILITY_IP}" to any port ${PHPFPM_EXPORTER_PORT} proto tcp comment 'phpfpm_exporter'

    ufw --force enable
    log_success "Firewall configured"
}

#===============================================================================
# Start Services
#===============================================================================

start_all_services() {
    log_step "Starting all services..."

    # Core services
    local services=(
        nginx
        "php${PHP_VERSION}-fpm"
        mariadb
        redis-server
        supervisor
    )

    # Monitoring exporters
    local exporters=(
        node_exporter
        nginx_exporter
        mysqld_exporter
        phpfpm_exporter
    )

    # Telemetry collector
    local telemetry_service
    case "${TELEMETRY_COLLECTOR,,}" in
        alloy) telemetry_service="alloy" ;;
        *)     telemetry_service="promtail" ;;
    esac

    # Start core services first
    for svc in "${services[@]}"; do
        enable_and_start "$svc" || log_warn "Failed to start $svc"
    done

    # Start exporters
    for svc in "${exporters[@]}"; do
        enable_and_start "$svc" || log_warn "Failed to start $svc"
    done

    # Start telemetry collector
    enable_and_start "$telemetry_service" || log_warn "Failed to start $telemetry_service"

    log_success "All services started"
}

#===============================================================================
# Health Checks
#===============================================================================

run_health_checks() {
    log_step "Running comprehensive health checks..."

    local failed_checks=0

    # Check Nginx
    if systemctl is-active --quiet nginx; then
        if curl -s -o /dev/null -w "%{http_code}" http://localhost | grep -qE "200|301|302"; then
            log_success "[OK] Nginx is responding"
        else
            log_error "[FAIL] Nginx not responding to HTTP requests"
            ((failed_checks++))
        fi
    else
        log_error "[FAIL] Nginx service not running"
        ((failed_checks++))
    fi

    # Check PHP-FPM
    if systemctl is-active --quiet "php${PHP_VERSION}-fpm"; then
        # Verify FPM socket exists
        local fpm_socket
        fpm_socket=$(find /run/php/ -name "php*-fpm.sock" 2>/dev/null | head -1)
        if [[ -S "${fpm_socket:-}" ]]; then
            log_success "[OK] PHP-FPM running with socket at $fpm_socket"
        else
            log_warn "[WARN] PHP-FPM running but socket not found"
        fi
    else
        log_error "[FAIL] PHP-FPM not running"
        ((failed_checks++))
    fi

    # Check MariaDB
    if systemctl is-active --quiet mariadb; then
        source /root/.credentials/mysql 2>/dev/null || true
        if mysql -u root -p"${DB_ROOT_PASS:-}" -e "SELECT 1" &>/dev/null; then
            log_success "[OK] MariaDB connection OK"
        else
            log_error "[FAIL] MariaDB connection failed"
            ((failed_checks++))
        fi
    else
        log_error "[FAIL] MariaDB not running"
        ((failed_checks++))
    fi

    # Check Redis
    if systemctl is-active --quiet redis-server; then
        if [[ -f /root/.credentials/redis ]]; then
            local redis_pass
            redis_pass=$(grep "REDIS_PASSWORD=" /root/.credentials/redis | cut -d= -f2)
            if redis-cli -a "$redis_pass" ping 2>/dev/null | grep -q PONG; then
                log_success "[OK] Redis responding (authenticated)"
            else
                log_error "[FAIL] Redis authentication failed"
                ((failed_checks++))
            fi
        else
            if redis-cli ping 2>/dev/null | grep -q PONG; then
                log_success "[OK] Redis responding"
            else
                log_error "[FAIL] Redis not responding"
                ((failed_checks++))
            fi
        fi
    else
        log_error "[FAIL] Redis not running"
        ((failed_checks++))
    fi

    # Check Supervisor
    if systemctl is-active --quiet supervisor; then
        local worker_status
        worker_status=$(supervisorctl status 2>/dev/null | grep "vpsmanager-worker" | grep -c "RUNNING" || echo "0")
        if [[ $worker_status -gt 0 ]]; then
            log_success "[OK] Supervisor workers running ($worker_status workers)"
        else
            log_warn "[WARN] Supervisor workers not running yet (normal on first install)"
        fi
    else
        log_error "[FAIL] Supervisor not running"
        ((failed_checks++))
    fi

    # Check Exporters
    local exporter_checks=(
        "${NODE_EXPORTER_PORT}:node_exporter:Node Exporter"
        "${NGINX_EXPORTER_PORT}:nginx_exporter:Nginx Exporter"
        "${MYSQLD_EXPORTER_PORT}:mysqld_exporter:MySQL Exporter"
        "${PHPFPM_EXPORTER_PORT}:phpfpm_exporter:PHP-FPM Exporter"
    )

    for check in "${exporter_checks[@]}"; do
        IFS=':' read -r port service name <<< "$check"
        if systemctl is-active --quiet "$service"; then
            if curl -s --connect-timeout 2 "http://localhost:$port/metrics" 2>/dev/null | grep -q "^# "; then
                log_success "[OK] $name responding (port $port)"
            else
                log_warn "[WARN] $name service running but metrics endpoint not responding on port $port"
            fi
        else
            log_warn "[WARN] $name not running"
        fi
    done

    # Check Telemetry Collector
    local telemetry_service telemetry_port
    case "${TELEMETRY_COLLECTOR,,}" in
        alloy)
            telemetry_service="alloy"
            telemetry_port="${ALLOY_PORT}"
            ;;
        *)
            telemetry_service="promtail"
            telemetry_port="${PROMTAIL_PORT}"
            ;;
    esac

    if systemctl is-active --quiet "$telemetry_service"; then
        log_success "[OK] ${telemetry_service^} running (sending logs to ${OBSERVABILITY_IP}:3100)"
    else
        log_warn "[WARN] ${telemetry_service^} not running"
    fi

    # Check Laravel application
    if [[ -f "${VPSMANAGER_PATH}/artisan" ]]; then
        if php "${VPSMANAGER_PATH}/artisan" --version &>/dev/null; then
            log_success "[OK] Laravel application accessible"

            # Check if .env is secure
            if [[ -f "${VPSMANAGER_PATH}/.env" ]]; then
                local env_perms
                env_perms=$(stat -c "%a" "${VPSMANAGER_PATH}/.env")
                if [[ "$env_perms" == "600" ]]; then
                    log_success "[OK] .env file properly secured (600)"
                else
                    log_warn "[WARN] .env file permissions: $env_perms (should be 600)"
                fi
            fi
        else
            log_error "[FAIL] Laravel application error"
            ((failed_checks++))
        fi
    fi

    # Summary
    echo ""
    if [[ $failed_checks -eq 0 ]]; then
        log_success "=========================================="
        log_success "  All health checks passed!"
        log_success "=========================================="
    else
        log_warn "=========================================="
        log_warn "  $failed_checks health check(s) failed"
        log_warn "  Review errors above"
        log_warn "=========================================="
    fi
    echo ""

    return $failed_checks
}

#===============================================================================
# Generate Prometheus Targets File
#===============================================================================

generate_prometheus_targets() {
    log_step "Generating Prometheus targets file..."

    # Determine environment
    local app_env="${APP_ENV:-production}"
    if [[ "${HOST_NAME}" == *"_tst"* ]] || [[ "${HOST_NAME}" == *"-tst"* ]]; then
        app_env="test"
    fi

    local targets_file="/tmp/${HOST_NAME}-targets.yaml"

    cat > "$targets_file" << EOF
# Prometheus Scrape Targets for ${HOST_NAME}
# Application: CHOM (VPSManager)
# Environment: ${app_env}
# Generated: $(date -Iseconds)
#
# Instructions:
# Copy this file to /etc/prometheus/targets/ on the Observability VPS:
#   scp ${targets_file} root@${OBSERVABILITY_IP}:/etc/prometheus/targets/
#
# Prometheus will automatically discover these targets via file_sd_configs
# Job naming convention: vpsmanager-{exporter_type}

# Node Exporter - System metrics (CPU, memory, disk, network)
- targets:
    - '${HOST_IP}:${NODE_EXPORTER_PORT}'
  labels:
    instance: '${HOST_NAME}'
    job: 'vpsmanager-node'
    app: 'chom'
    env: '${app_env}'
    role: 'vpsmanager'

# Nginx Exporter - Web server metrics (connections, requests)
- targets:
    - '${HOST_IP}:${NGINX_EXPORTER_PORT}'
  labels:
    instance: '${HOST_NAME}'
    job: 'vpsmanager-nginx'
    app: 'chom'
    env: '${app_env}'
    role: 'vpsmanager'

# MySQL Exporter - Database metrics (queries, connections, InnoDB)
- targets:
    - '${HOST_IP}:${MYSQLD_EXPORTER_PORT}'
  labels:
    instance: '${HOST_NAME}'
    job: 'vpsmanager-mysql'
    app: 'chom'
    env: '${app_env}'
    role: 'vpsmanager'

# PHP-FPM Exporter - Application runtime metrics (processes, requests)
- targets:
    - '${HOST_IP}:${PHPFPM_EXPORTER_PORT}'
  labels:
    instance: '${HOST_NAME}'
    job: 'vpsmanager-phpfpm'
    app: 'chom'
    env: '${app_env}'
    role: 'vpsmanager'
EOF

    # Save locally for reference
    mkdir -p /etc/prometheus-client
    cp "$targets_file" /etc/prometheus-client/
    chmod 644 /etc/prometheus-client/*.yaml

    log_info "Prometheus targets file created: $targets_file"
    log_info "Copy to Observability VPS: scp $targets_file root@${OBSERVABILITY_IP}:/etc/prometheus/targets/"

    log_success "Prometheus targets generated with vpsmanager-* job naming"
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

    # Determine environment
    local app_env="${APP_ENV:-production}"
    if [[ "${HOST_NAME}" == *"_tst"* ]] || [[ "${HOST_NAME}" == *"-tst"* ]]; then
        app_env="test"
    fi

    cat > "$STACK_DIR/.installation" << EOF
# VPSManager Installation
# Generated: $(date -Iseconds)

ROLE=vpsmanager
HOST_NAME=${HOST_NAME}
HOST_IP=${HOST_IP}
OBSERVABILITY_IP=${OBSERVABILITY_IP}
APP_ENV=${app_env}

VPSMANAGER_DOMAIN=${VPSMANAGER_DOMAIN}
VPSMANAGER_REPO=${VPSMANAGER_REPO}
VPSMANAGER_PATH=${VPSMANAGER_PATH}

PHP_VERSION=${PHP_VERSION}
TELEMETRY_COLLECTOR=${TELEMETRY_COLLECTOR}

# Services installed
SERVICES=(nginx php-fpm mariadb redis supervisor)
EXPORTERS=(node_exporter nginx_exporter mysqld_exporter phpfpm_exporter)

# Exporter ports (standard)
NODE_EXPORTER_PORT=${NODE_EXPORTER_PORT}
NGINX_EXPORTER_PORT=${NGINX_EXPORTER_PORT}
MYSQLD_EXPORTER_PORT=${MYSQLD_EXPORTER_PORT}
PHPFPM_EXPORTER_PORT=${PHPFPM_EXPORTER_PORT}
PROMTAIL_PORT=${PROMTAIL_PORT}
ALLOY_PORT=${ALLOY_PORT}
EOF

    chmod 600 "$STACK_DIR/.installation"
    log_success "Installation info saved to $STACK_DIR/.installation"
}
