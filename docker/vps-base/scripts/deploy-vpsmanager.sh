#!/bin/bash
# ============================================================================
# Deploy VPSManager/CHOM Stack on landsraad_tst VPS
# Non-interactive wrapper that sources libraries and runs vpsmanager role
#
# Supports both Promtail and Grafana Alloy for telemetry collection
# Set TELEMETRY_COLLECTOR=alloy to use Alloy instead of Promtail
# ============================================================================
set -euo pipefail

LOG_PREFIX="[DEPLOY-VPSMANAGER]"
STACK_PATH="/opt/observability-stack"
DEPLOY_DIR="$STACK_PATH/deploy"
CHOM_PATH="/opt/chom"

echo "$LOG_PREFIX Starting VPSManager/CHOM deployment..."

# Wait for systemd to be fully ready (allow degraded since some services may fail initially)
max_wait=60
waited=0
while true; do
    status=$(systemctl is-system-running 2>/dev/null || echo "unknown")
    if [[ "$status" == "running" ]] || [[ "$status" == "degraded" ]]; then
        echo "$LOG_PREFIX Systemd is ready (status: $status)"
        break
    fi
    if [[ $waited -ge $max_wait ]]; then
        echo "$LOG_PREFIX WARNING: Systemd not fully ready after ${max_wait}s, proceeding anyway..."
        break
    fi
    echo "$LOG_PREFIX Waiting for systemd... (status: $status)"
    sleep 2
    waited=$((waited + 2))
done

# Check if deployment scripts exist
if [[ ! -d "$DEPLOY_DIR" ]]; then
    echo "$LOG_PREFIX ERROR: observability-stack not mounted at $STACK_PATH"
    exit 1
fi

# Check if CHOM application is mounted
if [[ ! -d "$CHOM_PATH" ]]; then
    echo "$LOG_PREFIX ERROR: CHOM application not mounted at $CHOM_PATH"
    exit 1
fi

# Set STACK_DIR for the deployment scripts
export STACK_DIR="$STACK_PATH"

# The observability-stack may be mounted read-only, so use a writable location for generated configs
export CONFIG_DIR="/etc/observability-stack"
mkdir -p "$CONFIG_DIR"
chmod 750 "$CONFIG_DIR"

echo "$LOG_PREFIX Using writable config directory: $CONFIG_DIR"

# Source the required libraries
echo "$LOG_PREFIX Loading deployment libraries..."
source "$DEPLOY_DIR/lib/common.sh"
source "$DEPLOY_DIR/lib/config.sh"

# Set non-interactive configuration variables
# Host configuration
export HOST_IP="${HOST_IP:-10.10.100.20}"
export HOST_NAME="${HOST_NAME:-landsraad_tst}"
export OBSERVABILITY_IP="${OBSERVABILITY_IP:-10.10.100.10}"

# Application configuration
export VPSMANAGER_REPO="${VPSMANAGER_REPO:-local}"
export VPSMANAGER_BRANCH="${VPSMANAGER_BRANCH:-main}"
export CHOM_LOCAL_PATH="${CHOM_LOCAL_PATH:-$CHOM_PATH}"

# For local deployment, we use the host IP as domain (no SSL needed in test env)
export VPSMANAGER_DOMAIN="${VPSMANAGER_DOMAIN:-$HOST_IP}"

# PHP version
export PHP_VERSION="${PHP_VERSION:-8.4}"

# Telemetry collector choice: promtail or alloy
export TELEMETRY_COLLECTOR="${TELEMETRY_COLLECTOR:-promtail}"

# Database configuration
export DB_DATABASE="${DB_DATABASE:-chom}"
export DB_USERNAME="${DB_USERNAME:-chom}"
export DB_PASSWORD="${DB_PASSWORD:-secret}"
export MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-root}"

# Non-interactive mode
export NON_INTERACTIVE="true"
export SKIP_SSL="${SKIP_SSL:-true}"
export DISABLE_IPV6="${DISABLE_IPV6:-true}"

# Exporter passwords (for monitoring)
export MYSQL_EXPORTER_PASS="${MYSQL_EXPORTER_PASS:-exporter_password}"
export REDIS_PASSWORD="${REDIS_PASSWORD:-}"

# Standard exporter ports (matching production)
# These may already be defined in common.sh, so use default assignment
export NODE_EXPORTER_PORT="${NODE_EXPORTER_PORT:-9100}"
export NGINX_EXPORTER_PORT="${NGINX_EXPORTER_PORT:-9113}"
export MYSQLD_EXPORTER_PORT="${MYSQLD_EXPORTER_PORT:-9104}"
export PHPFPM_EXPORTER_PORT="${PHPFPM_EXPORTER_PORT:-9253}"
export PROMTAIL_PORT="${PROMTAIL_PORT:-9080}"
export ALLOY_PORT="${ALLOY_PORT:-12345}"

# Exporter versions (can be overridden via environment)
export NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-1.7.0}"
export NGINX_EXPORTER_VERSION="${NGINX_EXPORTER_VERSION:-1.1.0}"
export MYSQLD_EXPORTER_VERSION="${MYSQLD_EXPORTER_VERSION:-0.15.1}"
export PHPFPM_EXPORTER_VERSION="${PHPFPM_EXPORTER_VERSION:-0.6.0}"
export PROMTAIL_VERSION="${PROMTAIL_VERSION:-3.0.0}"
export ALLOY_VERSION="${ALLOY_VERSION:-1.0.0}"

echo "$LOG_PREFIX Configuration:"
echo "  HOST_IP: $HOST_IP"
echo "  HOST_NAME: $HOST_NAME"
echo "  OBSERVABILITY_IP: $OBSERVABILITY_IP"
echo "  VPSMANAGER_REPO: $VPSMANAGER_REPO"
echo "  CHOM_LOCAL_PATH: $CHOM_LOCAL_PATH"
echo "  VPSMANAGER_DOMAIN: $VPSMANAGER_DOMAIN"
echo "  PHP_VERSION: $PHP_VERSION"
echo "  DB_DATABASE: $DB_DATABASE"
echo "  DB_USERNAME: $DB_USERNAME"
echo "  SKIP_SSL: $SKIP_SSL"
echo "  TELEMETRY_COLLECTOR: $TELEMETRY_COLLECTOR"

# Source the vpsmanager role script (this defines the functions)
echo "$LOG_PREFIX Loading vpsmanager role..."
source "$DEPLOY_DIR/roles/vpsmanager.sh"

# Override functions that need non-interactive behavior

# Override install_php to use Debian 13's native PHP packages (no Sury repo needed)
install_php() {
    log_step "Installing PHP ${PHP_VERSION} from Debian repositories..."

    # Debian 13 (trixie) has PHP 8.4 in default repos, no need for Sury
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
        php${PHP_VERSION}-opcache || true

    # Configure PHP-FPM for monitoring
    configure_phpfpm_for_monitoring

    log_success "PHP ${PHP_VERSION} installed"
}

# Override configure_phpfpm_for_monitoring to properly enable status pages
configure_phpfpm_for_monitoring() {
    log_step "Configuring PHP-FPM for monitoring..."

    local fpm_conf="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

    if [[ ! -f "$fpm_conf" ]]; then
        log_warn "PHP-FPM pool config not found at $fpm_conf"
        return 1
    fi

    # Enable status page for monitoring (required for phpfpm_exporter)
    if grep -q "^;pm.status_path" "$fpm_conf"; then
        sed -i 's/^;pm.status_path.*/pm.status_path = \/fpm-status/' "$fpm_conf"
    elif ! grep -q "^pm.status_path" "$fpm_conf"; then
        echo "pm.status_path = /fpm-status" >> "$fpm_conf"
    fi

    # Enable ping path
    if grep -q "^;ping.path" "$fpm_conf"; then
        sed -i 's/^;ping.path.*/ping.path = \/fpm-ping/' "$fpm_conf"
    elif ! grep -q "^ping.path" "$fpm_conf"; then
        echo "ping.path = /fpm-ping" >> "$fpm_conf"
    fi

    # Performance tuning
    sed -i 's/^pm = .*/pm = dynamic/' "$fpm_conf" || true
    sed -i 's/^pm.max_children = .*/pm.max_children = 20/' "$fpm_conf" || true
    sed -i 's/^pm.start_servers = .*/pm.start_servers = 5/' "$fpm_conf" || true
    sed -i 's/^pm.min_spare_servers = .*/pm.min_spare_servers = 3/' "$fpm_conf" || true
    sed -i 's/^pm.max_spare_servers = .*/pm.max_spare_servers = 10/' "$fpm_conf" || true

    # PHP.ini optimization
    local php_ini="/etc/php/${PHP_VERSION}/fpm/php.ini"
    if [[ -f "$php_ini" ]]; then
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' "$php_ini" || true
        sed -i 's/^post_max_size = .*/post_max_size = 100M/' "$php_ini" || true
        sed -i 's/^memory_limit = .*/memory_limit = 256M/' "$php_ini" || true
        sed -i 's/^max_execution_time = .*/max_execution_time = 120/' "$php_ini" || true
        sed -i 's/^;opcache.enable=.*/opcache.enable=1/' "$php_ini" || true
        sed -i 's/^;opcache.memory_consumption=.*/opcache.memory_consumption=256/' "$php_ini" || true
    fi

    log_success "PHP-FPM configured for monitoring"
}

# Override validate_config to skip domain requirement for local testing
validate_config() {
    log_step "Validating configuration (non-interactive mode)..."

    # For local deployment, domain is not required - we use IP
    if [[ "$VPSMANAGER_REPO" == "local" ]]; then
        if [[ ! -d "$CHOM_LOCAL_PATH" ]]; then
            log_error "CHOM_LOCAL_PATH does not exist: $CHOM_LOCAL_PATH"
            exit 1
        fi
        log_info "Using local CHOM application from: $CHOM_LOCAL_PATH"
    elif [[ -z "${VPSMANAGER_REPO:-}" ]]; then
        log_error "VPSMANAGER_REPO is required"
        exit 1
    fi

    # Validate telemetry collector choice
    if [[ "${TELEMETRY_COLLECTOR,,}" != "promtail" ]] && [[ "${TELEMETRY_COLLECTOR,,}" != "alloy" ]]; then
        log_warn "Unknown TELEMETRY_COLLECTOR: ${TELEMETRY_COLLECTOR}, defaulting to promtail"
        export TELEMETRY_COLLECTOR="promtail"
    fi

    log_success "Configuration validated"
}

# Override deploy_application for local deployment
deploy_application() {
    log_step "Deploying VPSManager/CHOM application (local mode)..."

    local VPSMANAGER_PATH="/var/www/vpsmanager"
    local VPSMANAGER_USER="www-data"

    # Create symlink or copy from local path
    if [[ "$VPSMANAGER_REPO" == "local" ]]; then
        log_info "Using local CHOM application from $CHOM_LOCAL_PATH..."

        # Create target directory
        mkdir -p "$(dirname "$VPSMANAGER_PATH")"

        # Remove existing installation
        rm -rf "$VPSMANAGER_PATH"

        # Create symlink to mounted code
        ln -sf "$CHOM_LOCAL_PATH" "$VPSMANAGER_PATH"

        log_info "Symlinked $VPSMANAGER_PATH -> $CHOM_LOCAL_PATH"
    else
        # Clone from repository
        if [[ -d "${VPSMANAGER_PATH}/.git" ]]; then
            log_info "Repository exists, pulling latest..."
            cd "$VPSMANAGER_PATH"
            git fetch origin
            git reset --hard "origin/${VPSMANAGER_BRANCH}"
        else
            log_info "Cloning repository..."
            git clone --branch "$VPSMANAGER_BRANCH" "$VPSMANAGER_REPO" "$VPSMANAGER_PATH"
        fi
    fi

    cd "$VPSMANAGER_PATH"

    # Source database credentials if they exist
    if [[ -f /root/.credentials/mysql ]]; then
        source /root/.credentials/mysql
    else
        # Use configured values
        DB_ROOT_PASS="${MYSQL_ROOT_PASSWORD}"
        DB_APP_USER="${DB_USERNAME}"
        DB_APP_PASS="${DB_PASSWORD}"
        DB_NAME="${DB_DATABASE}"
    fi

    # Load Redis password if saved
    if [[ -f /root/.credentials/redis ]]; then
        source /root/.credentials/redis
    else
        REDIS_PASSWORD="${REDIS_PASSWORD:-}"
    fi

    # Create .env file from example if needed
    if [[ ! -f .env ]] && [[ -f .env.example ]]; then
        cp .env.example .env
        log_info "Created .env from .env.example"
    elif [[ ! -f .env ]]; then
        log_info "Creating minimal .env file..."
        cat > .env << EOF
APP_NAME=CHOM
APP_ENV=local
APP_DEBUG=true
APP_URL=http://${VPSMANAGER_DOMAIN}

LOG_CHANNEL=stack
LOG_LEVEL=debug

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
REDIS_PASSWORD=${REDIS_PASSWORD:-}
REDIS_PORT=6379
EOF
    fi

    # Update .env with correct values
    sed -i "s|^APP_URL=.*|APP_URL=http://${VPSMANAGER_DOMAIN}|" .env
    sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|" .env
    sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${DB_APP_USER}|" .env
    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_APP_PASS}|" .env
    if [[ -n "${REDIS_PASSWORD:-}" ]]; then
        sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=${REDIS_PASSWORD}|" .env
    fi

    # Secure .env file permissions
    chmod 644 .env

    # Ensure storage and cache directories exist with correct permissions
    mkdir -p storage/framework/{sessions,views,cache}
    mkdir -p storage/logs
    mkdir -p bootstrap/cache

    # Install Composer dependencies
    log_info "Installing Composer dependencies..."
    if [[ -f composer.phar ]]; then
        php composer.phar install --no-dev --optimize-autoloader --no-interaction 2>&1 || \
        php composer.phar install --optimize-autoloader --no-interaction 2>&1 || true
    else
        composer install --no-dev --optimize-autoloader --no-interaction 2>&1 || \
        composer install --optimize-autoloader --no-interaction 2>&1 || true
    fi

    # Generate application key if not set
    if ! grep -q "^APP_KEY=base64:" .env; then
        log_info "Generating application key..."
        php artisan key:generate --force
    fi

    # Build frontend assets if package.json exists
    if [[ -f package.json ]]; then
        log_info "Installing npm dependencies and building assets..."
        npm ci --no-audit --no-fund 2>/dev/null || npm install --no-audit --no-fund 2>/dev/null || true
        npm run build 2>/dev/null || npm run production 2>/dev/null || true
    fi

    # Run database migrations
    log_info "Running database migrations..."
    php artisan migrate --force 2>&1 || true

    # Cache configuration
    log_info "Caching configuration..."
    php artisan config:clear 2>&1 || true
    php artisan config:cache 2>&1 || true
    php artisan route:cache 2>&1 || true
    php artisan view:cache 2>&1 || true

    # Create storage link
    php artisan storage:link 2>&1 || true

    # =========================================================================
    # Fix permissions for Laravel to function properly
    # =========================================================================

    # 1. SQLite database permissions (if using SQLite)
    #    The database directory and file need www-data ownership for Laravel writes
    log_info "Setting database directory permissions..."
    chown -R ${VPSMANAGER_USER}:${VPSMANAGER_USER} "${VPSMANAGER_PATH}/database"
    chmod 775 "${VPSMANAGER_PATH}/database"
    chmod 664 "${VPSMANAGER_PATH}/database/database.sqlite" 2>/dev/null || true

    # 2. Config file permissions
    #    Config files may be created with restrictive permissions; ensure www-data can read them
    log_info "Setting config file permissions..."
    chmod 644 "${VPSMANAGER_PATH}/config/"*.php 2>/dev/null || true

    # 3. Storage and bootstrap/cache permissions
    #    These directories must be writable by www-data for caching, sessions, logs, etc.
    log_info "Setting storage and cache permissions..."
    chown -R ${VPSMANAGER_USER}:${VPSMANAGER_USER} "${VPSMANAGER_PATH}/storage" "${VPSMANAGER_PATH}/bootstrap/cache"
    chmod -R 775 "${VPSMANAGER_PATH}/storage" "${VPSMANAGER_PATH}/bootstrap/cache"

    log_success "Application deployed"
}

# Override setup_ssl to skip in non-interactive mode
setup_ssl() {
    if [[ "${SKIP_SSL:-false}" == "true" ]]; then
        log_info "Skipping SSL setup (SKIP_SSL=true)"
        return 0
    fi

    log_step "Setting up SSL certificate..."

    # Check if we're using an IP address (no SSL possible)
    if [[ "$VPSMANAGER_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_warn "Domain is an IP address - SSL certificates not available for IP addresses"
        log_info "Application will be accessible via HTTP only"
        return 0
    fi

    log_warn "SSL setup skipped for test environment"
    return 0
}

# Override install_mariadb for non-interactive setup
install_mariadb() {
    log_step "Installing MariaDB..."

    # Install MariaDB
    apt-get install -y -qq mariadb-server mariadb-client

    # Ensure MariaDB is started
    systemctl enable mariadb
    systemctl start mariadb || true

    # Wait for MariaDB to be ready
    local max_wait=30
    local waited=0
    while ! mysqladmin ping --silent 2>/dev/null; do
        sleep 1
        waited=$((waited + 1))
        if [[ $waited -ge $max_wait ]]; then
            log_error "MariaDB failed to start within ${max_wait}s"
            return 1
        fi
    done

    # Set root password and create application database
    log_info "Configuring MariaDB..."

    # Use provided credentials
    local DB_ROOT_PASS="${MYSQL_ROOT_PASSWORD}"
    local DB_APP_USER="${DB_USERNAME}"
    local DB_APP_PASS="${DB_PASSWORD}"
    local DB_NAME="${DB_DATABASE}"

    # Try to set root password (will fail if already set, which is OK)
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';" 2>/dev/null || true

    # Create database and user
    mysql -u root -p"${DB_ROOT_PASS}" << EOF || mysql << EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_APP_USER}'@'localhost' IDENTIFIED BY '${DB_APP_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_APP_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

    # Create exporter user for monitoring
    local MYSQL_EXPORTER_PASS="${MYSQL_EXPORTER_PASS:-exporter_password}"
    mysql -u root -p"${DB_ROOT_PASS}" << EOF 2>/dev/null || mysql << EOF 2>/dev/null || true
CREATE USER IF NOT EXISTS 'exporter'@'localhost' IDENTIFIED BY '${MYSQL_EXPORTER_PASS}';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';
FLUSH PRIVILEGES;
EOF

    # Save credentials
    mkdir -p /root/.credentials
    chmod 700 /root/.credentials
    cat > /root/.credentials/mysql << EOF
DB_ROOT_PASS=${DB_ROOT_PASS}
DB_APP_USER=${DB_APP_USER}
DB_APP_PASS=${DB_APP_PASS}
DB_NAME=${DB_NAME}
MYSQL_EXPORTER_PASS=${MYSQL_EXPORTER_PASS}
EOF
    chmod 600 /root/.credentials/mysql

    log_success "MariaDB configured (credentials saved to /root/.credentials/mysql)"
}

# Override install_redis for non-interactive setup
install_redis() {
    log_step "Installing Redis..."

    apt-get install -y -qq redis-server

    # Generate or use existing Redis password
    local REDIS_PASSWORD="${REDIS_PASSWORD:-$(openssl rand -base64 16)}"

    # Configure Redis
    sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf || true
    sed -i 's/^# maxmemory .*/maxmemory 256mb/' /etc/redis/redis.conf || true
    sed -i 's/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf || true

    # Add password protection
    if grep -q "^requirepass" /etc/redis/redis.conf; then
        sed -i "s|^requirepass .*|requirepass ${REDIS_PASSWORD}|" /etc/redis/redis.conf
    elif grep -q "^# requirepass" /etc/redis/redis.conf; then
        sed -i "s|^# requirepass .*|requirepass ${REDIS_PASSWORD}|" /etc/redis/redis.conf
    else
        echo "requirepass ${REDIS_PASSWORD}" >> /etc/redis/redis.conf
    fi

    # Bind to localhost only
    sed -i 's/^bind .*/bind 127.0.0.1 ::1/' /etc/redis/redis.conf || true

    # Save credentials
    mkdir -p /root/.credentials
    echo "REDIS_PASSWORD=${REDIS_PASSWORD}" > /root/.credentials/redis
    chmod 600 /root/.credentials/redis

    # Export for use elsewhere
    export REDIS_PASSWORD

    systemctl enable redis-server
    systemctl restart redis-server || true

    # Test connection
    sleep 2
    if redis-cli -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q PONG; then
        log_success "Redis installed and secured with password"
    else
        log_warn "Redis may need manual verification"
    fi
}

# Override configure_nginx_vhost for non-SSL setup
configure_nginx_vhost() {
    log_step "Configuring Nginx virtual host..."

    local VPSMANAGER_PATH="/var/www/vpsmanager"

    cat > /etc/nginx/sites-available/vpsmanager << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${VPSMANAGER_DOMAIN} _;
    root ${VPSMANAGER_PATH}/public;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    index index.php index.html;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php\$ {
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

    # PHP-FPM status for monitoring (localhost only)
    location ~ ^/(fpm-status|fpm-ping)\$ {
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

    # Remove default site and enable vpsmanager
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/vpsmanager /etc/nginx/sites-enabled/

    # Test nginx configuration
    nginx -t || {
        log_error "Nginx configuration test failed"
        return 1
    }

    log_success "Nginx virtual host configured"
}

# Override firewall setup for container environment
setup_firewall_vpsmanager() {
    log_step "Configuring firewall..."

    # Check if ufw is available
    if ! command -v ufw &>/dev/null; then
        log_warn "UFW not available, skipping firewall configuration"
        return 0
    fi

    # In container, firewall may not work properly
    if [[ -f /.dockerenv ]] || grep -q docker /proc/1/cgroup 2>/dev/null; then
        log_info "Running in container - firewall configuration may be limited"
    fi

    ufw --force reset 2>/dev/null || true
    ufw default deny incoming 2>/dev/null || true
    ufw default allow outgoing 2>/dev/null || true

    # SSH
    ufw allow 22/tcp comment 'SSH' 2>/dev/null || true

    # HTTP/HTTPS
    ufw allow 80/tcp comment 'HTTP' 2>/dev/null || true
    ufw allow 443/tcp comment 'HTTPS' 2>/dev/null || true

    # Metrics (from observability server)
    ufw allow from "${OBSERVABILITY_IP}" to any port ${NODE_EXPORTER_PORT} proto tcp comment 'node_exporter' 2>/dev/null || true
    ufw allow from "${OBSERVABILITY_IP}" to any port ${NGINX_EXPORTER_PORT} proto tcp comment 'nginx_exporter' 2>/dev/null || true
    ufw allow from "${OBSERVABILITY_IP}" to any port ${MYSQLD_EXPORTER_PORT} proto tcp comment 'mysqld_exporter' 2>/dev/null || true
    ufw allow from "${OBSERVABILITY_IP}" to any port ${PHPFPM_EXPORTER_PORT} proto tcp comment 'phpfpm_exporter' 2>/dev/null || true

    ufw --force enable 2>/dev/null || log_warn "Could not enable UFW in container"

    log_success "Firewall configured"
}

# Override start_all_services to handle container environment and telemetry collector
# CRITICAL: This function must start ALL exporters for monitoring to work
start_all_services() {
    log_step "Starting all services..."

    # Reload systemd first to pick up all service files
    systemctl daemon-reload

    # Core application services (must start first)
    local core_services=(
        nginx
        "php${PHP_VERSION}-fpm"
        mariadb
        redis-server
        supervisor
    )

    # ALL monitoring exporters - these are installed by install_vpsmanager()
    # and MUST be started for regression tests to pass
    local exporter_services=(
        node_exporter
        nginx_exporter
        mysqld_exporter
        phpfpm_exporter
    )

    # Telemetry collector based on configuration
    local telemetry_service
    case "${TELEMETRY_COLLECTOR,,}" in
        alloy)
            telemetry_service="alloy"
            ;;
        *)
            telemetry_service="promtail"
            ;;
    esac

    # Start core services first (exporters depend on some of these)
    log_info "Starting core services..."
    for svc in "${core_services[@]}"; do
        log_info "  Enabling and starting $svc..."
        systemctl enable "$svc" 2>/dev/null || true
        systemctl start "$svc" 2>/dev/null || log_warn "Failed to start $svc"
    done

    # Small delay to ensure core services are ready (needed for exporters)
    sleep 2

    # Start ALL exporters - these are critical for monitoring
    log_info "Starting monitoring exporters..."
    for svc in "${exporter_services[@]}"; do
        if [[ -f "/etc/systemd/system/${svc}.service" ]]; then
            log_info "  Enabling and starting $svc..."
            systemctl enable "$svc" 2>/dev/null || true
            systemctl start "$svc" 2>/dev/null || log_warn "Failed to start $svc"
        else
            log_warn "  Service file not found for $svc - attempting installation"
            # Attempt to install missing exporter
            case "$svc" in
                node_exporter)
                    install_node_exporter 2>/dev/null || true
                    ;;
                nginx_exporter)
                    install_nginx_exporter 2>/dev/null || true
                    ;;
                mysqld_exporter)
                    install_mysqld_exporter 2>/dev/null || true
                    ;;
                phpfpm_exporter)
                    install_phpfpm_exporter 2>/dev/null || true
                    ;;
            esac
            # Try starting after installation
            systemctl daemon-reload
            systemctl enable "$svc" 2>/dev/null || true
            systemctl start "$svc" 2>/dev/null || log_warn "Failed to start $svc after installation"
        fi
    done

    # Start telemetry collector
    log_info "Starting telemetry collector ($telemetry_service)..."
    if [[ -f "/etc/systemd/system/${telemetry_service}.service" ]]; then
        systemctl enable "$telemetry_service" 2>/dev/null || true
        systemctl start "$telemetry_service" 2>/dev/null || log_warn "Failed to start $telemetry_service"
    else
        log_warn "  Telemetry collector service file not found - attempting installation"
        case "$telemetry_service" in
            alloy)
                install_alloy 2>/dev/null || true
                ;;
            promtail)
                install_promtail 2>/dev/null || true
                ;;
        esac
        systemctl daemon-reload
        systemctl enable "$telemetry_service" 2>/dev/null || true
        systemctl start "$telemetry_service" 2>/dev/null || log_warn "Failed to start $telemetry_service after installation"
    fi

    log_success "All services started"
}

# Override install_phpfpm_exporter for container environment
install_phpfpm_exporter() {
    log_step "Installing PHP-FPM Exporter..."

    create_system_user phpfpm_exporter phpfpm_exporter
    usermod -a -G www-data phpfpm_exporter 2>/dev/null || true

    local arch
    arch=$(get_architecture)
    local url="https://github.com/hipages/php-fpm_exporter/releases/download/v${PHPFPM_EXPORTER_VERSION:-0.6.0}/php-fpm_exporter_${PHPFPM_EXPORTER_VERSION:-0.6.0}_linux_${arch}"

    # Stop service and verify before binary update
    stop_and_verify_service "phpfpm_exporter" "/usr/local/bin/phpfpm_exporter" || true

    download_file "$url" /usr/local/bin/phpfpm_exporter
    chmod +x /usr/local/bin/phpfpm_exporter

    # Find PHP-FPM socket dynamically
    local fpm_socket
    fpm_socket=$(find /run/php/ -name "php*-fpm.sock" 2>/dev/null | head -1)
    if [[ -z "$fpm_socket" ]]; then
        fpm_socket="/run/php/php${PHP_VERSION}-fpm.sock"
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
    log_success "PHP-FPM Exporter installed (port ${PHPFPM_EXPORTER_PORT}, socket: ${fpm_socket})"
}

# Ensure all exporters are installed - called before start_all_services
# This is a safety net to ensure exporters are always installed even if
# the role script's install functions were not called properly
ensure_exporters_installed() {
    log_step "Ensuring all monitoring exporters are installed..."

    local exporters_to_check=(
        "node_exporter:install_node_exporter"
        "nginx_exporter:install_nginx_exporter"
        "mysqld_exporter:install_mysqld_exporter"
        "phpfpm_exporter:install_phpfpm_exporter"
    )

    for item in "${exporters_to_check[@]}"; do
        IFS=':' read -r service install_func <<< "$item"
        if [[ ! -f "/etc/systemd/system/${service}.service" ]]; then
            log_warn "$service not installed - installing now..."
            if declare -f "$install_func" > /dev/null 2>&1; then
                "$install_func" || log_warn "Failed to install $service"
            else
                log_error "Install function $install_func not found"
            fi
        else
            log_info "$service already installed"
        fi
    done

    # Also ensure telemetry collector is installed
    local telemetry_service telemetry_install_func
    case "${TELEMETRY_COLLECTOR,,}" in
        alloy)
            telemetry_service="alloy"
            telemetry_install_func="install_alloy"
            ;;
        *)
            telemetry_service="promtail"
            telemetry_install_func="install_promtail"
            ;;
    esac

    if [[ ! -f "/etc/systemd/system/${telemetry_service}.service" ]]; then
        log_warn "$telemetry_service not installed - installing now..."
        if declare -f "$telemetry_install_func" > /dev/null 2>&1; then
            "$telemetry_install_func" || log_warn "Failed to install $telemetry_service"
        fi
    else
        log_info "$telemetry_service already installed"
    fi

    systemctl daemon-reload
    log_success "All exporters installation verified"
}

# Health check function for post-deployment verification
verify_deployment() {
    log_step "Verifying deployment..."
    local failed=0

    # Check core services
    local services=("nginx" "php${PHP_VERSION}-fpm" "mariadb" "redis-server")
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            log_success "[OK] $svc is running"
        else
            log_error "[FAIL] $svc is NOT running"
            ((failed++))
        fi
    done

    # Check exporters - these are REQUIRED for monitoring, not optional
    local exporter_checks=(
        "${NODE_EXPORTER_PORT}:node_exporter:Node Exporter"
        "${NGINX_EXPORTER_PORT}:nginx_exporter:Nginx Exporter"
        "${MYSQLD_EXPORTER_PORT}:mysqld_exporter:MySQL Exporter"
        "${PHPFPM_EXPORTER_PORT}:phpfpm_exporter:PHP-FPM Exporter"
    )

    for check in "${exporter_checks[@]}"; do
        IFS=':' read -r port service name <<< "$check"
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            if curl -s --connect-timeout 2 "http://localhost:${port}/metrics" 2>/dev/null | grep -q "^# "; then
                log_success "[OK] $name responding (port $port)"
            else
                log_warn "[WARN] $name running but metrics not responding on port $port"
            fi
        else
            # Exporters are required - mark as failure if not running
            log_error "[FAIL] $name not running (port $port)"
            ((failed++))
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

    if systemctl is-active --quiet "$telemetry_service" 2>/dev/null; then
        log_success "[OK] ${telemetry_service^} running (shipping logs to ${OBSERVABILITY_IP}:3100)"
    else
        log_warn "[WARN] ${telemetry_service^} not running"
    fi

    # Check Laravel application
    if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1/" 2>/dev/null | grep -qE "200|301|302"; then
        log_success "[OK] Laravel application responding"
    else
        log_warn "[WARN] Laravel application may not be ready yet"
    fi

    if [[ $failed -gt 0 ]]; then
        log_error "$failed core service(s) failed to start"
        return 1
    fi

    log_success "Deployment verification complete"
    return 0
}

# Run the main installation function
echo "$LOG_PREFIX Running VPSManager stack installation..."
install_vpsmanager

# Ensure all exporters are installed (safety net)
echo ""
echo "$LOG_PREFIX Verifying exporter installation..."
ensure_exporters_installed

# Explicitly start all services (including exporters)
echo ""
echo "$LOG_PREFIX Starting all services..."
start_all_services

# Run verification
echo ""
verify_deployment

# Print deployment summary
echo ""
echo "$LOG_PREFIX ========================================"
echo "$LOG_PREFIX VPSManager deployment complete!"
echo "$LOG_PREFIX ========================================"
echo "$LOG_PREFIX"
echo "$LOG_PREFIX Application Endpoints:"
echo "  - Web Application: http://${HOST_IP}"
echo "  - MySQL:           ${HOST_IP}:3306"
echo "  - Redis:           ${HOST_IP}:6379"
echo ""
echo "$LOG_PREFIX Monitoring Endpoints (vpsmanager-* job naming):"
echo "  - Node Exporter:   http://${HOST_IP}:${NODE_EXPORTER_PORT}/metrics  (job: vpsmanager-node)"
echo "  - Nginx Exporter:  http://${HOST_IP}:${NGINX_EXPORTER_PORT}/metrics  (job: vpsmanager-nginx)"
echo "  - MySQL Exporter:  http://${HOST_IP}:${MYSQLD_EXPORTER_PORT}/metrics  (job: vpsmanager-mysql)"
echo "  - PHP-FPM Exporter: http://${HOST_IP}:${PHPFPM_EXPORTER_PORT}/metrics  (job: vpsmanager-phpfpm)"

# Print telemetry collector info
case "${TELEMETRY_COLLECTOR,,}" in
    alloy)
        echo "  - Alloy:           Shipping logs to ${OBSERVABILITY_IP}:3100 (port ${ALLOY_PORT})"
        ;;
    *)
        echo "  - Promtail:        Shipping logs to ${OBSERVABILITY_IP}:3100 (port ${PROMTAIL_PORT})"
        ;;
esac

echo ""
echo "$LOG_PREFIX Credentials:"
echo "  - Database: /root/.credentials/mysql"
echo "  - Redis:    /root/.credentials/redis"
echo ""
echo "$LOG_PREFIX Prometheus targets file:"
echo "  - /tmp/${HOST_NAME}-targets.yaml"
echo "  - Copy to observability VPS: scp /tmp/${HOST_NAME}-targets.yaml root@${OBSERVABILITY_IP}:/etc/prometheus/targets/"
echo ""
