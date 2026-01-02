#!/bin/bash
################################################################################
# CHOM Application - Production Deployment Script
#
# Purpose: Deploy CHOM Laravel application to production VPS
# Features: Armored, Safe, Idempotent
#
# Usage: ./deploy-chom.sh [--dry-run] [--rollback] [--force] [--skip-migrations]
#
# Environment Variables:
#   DOMAIN                - Domain name (default: landsraad.arewel.com)
#   SSL_EMAIL            - Email for Let's Encrypt (default: admin@arewel.com)
#   DB_PASSWORD          - Database password (auto-generated if not set)
#   REDIS_PASSWORD       - Redis password (auto-generated if not set)
#   OBSERVABILITY_IP     - Observability server IP (default: 51.254.139.78)
#   SKIP_MIGRATIONS      - Skip database migrations (default: false)
#   SKIP_BACKUPS         - Skip backup creation (default: false)
################################################################################

set -euo pipefail

################################################################################
# Configuration
################################################################################

# Script metadata
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly STATE_DIR="/var/lib/chom-deploy"
readonly STATE_FILE="${STATE_DIR}/chom-state.json"
readonly LOG_DIR="/var/log/chom-deploy"
readonly LOG_FILE="${LOG_DIR}/chom-$(date +%Y%m%d-%H%M%S).log"
readonly BACKUP_DIR="/var/backups/chom"

# Deployment configuration
readonly DOMAIN="${DOMAIN:-landsraad.arewel.com}"
readonly SSL_EMAIL="${SSL_EMAIL:-admin@arewel.com}"
readonly OBSERVABILITY_IP="${OBSERVABILITY_IP:-51.254.139.78}"
readonly SKIP_MIGRATIONS="${SKIP_MIGRATIONS:-false}"
readonly SKIP_BACKUPS="${SKIP_BACKUPS:-false}"

# Application paths
readonly APP_DIR="/var/www/chom"
readonly APP_USER="www-data"
readonly APP_GROUP="www-data"

# PHP Version
readonly PHP_VERSION="8.3"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Flags
DRY_RUN=false
ROLLBACK=false
FORCE=false

################################################################################
# Utility Functions
################################################################################

log_info() {
    local msg="$1"
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$LOG_FILE"
}

log_warn() {
    local msg="$1"
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$LOG_FILE"
}

log_error() {
    local msg="$1"
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$LOG_FILE"
}

log_debug() {
    local msg="$1"
    echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $msg" >> "$LOG_FILE"
}

execute() {
    local cmd="$1"
    log_debug "Executing: $cmd"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would execute: $cmd"
        return 0
    fi

    if eval "$cmd"; then
        log_debug "Command succeeded: $cmd"
        return 0
    else
        local exit_code=$?
        log_error "Command failed (exit code $exit_code): $cmd"
        return $exit_code
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

service_running() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null
}

save_state() {
    local key="$1"
    local value="$2"

    if [ "$DRY_RUN" = true ]; then
        return 0
    fi

    mkdir -p "$STATE_DIR"

    if [ ! -f "$STATE_FILE" ]; then
        echo '{}' > "$STATE_FILE"
    fi

    local temp_file=$(mktemp)
    jq --arg key "$key" --arg value "$value" '.[$key] = $value' "$STATE_FILE" > "$temp_file"
    mv "$temp_file" "$STATE_FILE"

    log_debug "State saved: $key = $value"
}

get_state() {
    local key="$1"
    local default="${2:-}"

    if [ ! -f "$STATE_FILE" ]; then
        echo "$default"
        return
    fi

    local value=$(jq -r --arg key "$key" '.[$key] // empty' "$STATE_FILE")
    if [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

step_completed() {
    local step="$1"
    local completed=$(get_state "$step" "false")
    [ "$completed" = "true" ]
}

mark_step_completed() {
    local step="$1"
    save_state "$step" "true"
    save_state "${step}_timestamp" "$(date -Iseconds)"
}

################################################################################
# Pre-flight Checks
################################################################################

preflight_checks() {
    log_info "Running pre-flight checks..."

    # Check if running as root
    if [ "$EUID" -ne 0 ] && [ "$DRY_RUN" = false ]; then
        log_error "This script must be run as root"
        return 1
    fi

    # Check OS version
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_info "Detected OS: $PRETTY_NAME"

        if [[ "$ID" != "debian" ]]; then
            log_warn "This script is designed for Debian. Your OS: $ID"
            if [ "$FORCE" = false ]; then
                log_error "Use --force to proceed anyway"
                return 1
            fi
        fi
    fi

    # Check system resources
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    local total_disk=$(df -m / | awk 'NR==2 {print $4}')

    log_info "System resources: ${total_mem}MB RAM, ${total_disk}MB disk available"

    if [ "$total_mem" -lt 3800 ]; then
        log_warn "Low memory: ${total_mem}MB (minimum 4GB recommended)"
        if [ "$FORCE" = false ]; then
            log_error "Use --force to proceed anyway"
            return 1
        fi
    fi

    if [ "$total_disk" -lt 38000 ]; then
        log_warn "Low disk space: ${total_disk}MB (minimum 40GB recommended)"
        if [ "$FORCE" = false ]; then
            log_error "Use --force to proceed anyway"
            return 1
        fi
    fi

    # Check DNS resolution
    if ! host "$DOMAIN" >/dev/null 2>&1; then
        log_error "DNS resolution failed for $DOMAIN"
        log_error "Please configure DNS before deployment"
        return 1
    fi

    local resolved_ip=$(host "$DOMAIN" | awk '/has address/ {print $4}' | head -1)
    local server_ip=$(curl -s ifconfig.me)

    if [ "$resolved_ip" != "$server_ip" ]; then
        log_warn "DNS mismatch: $DOMAIN resolves to $resolved_ip, but server IP is $server_ip"
        if [ "$FORCE" = false ]; then
            log_error "Please fix DNS or use --force to proceed"
            return 1
        fi
    else
        log_info "DNS correctly configured: $DOMAIN → $server_ip"
    fi

    # Check observability server connectivity
    if ! ping -c 1 -W 2 "$OBSERVABILITY_IP" >/dev/null 2>&1; then
        log_warn "Cannot ping observability server: $OBSERVABILITY_IP"
        if [ "$FORCE" = false ]; then
            log_error "Use --force to proceed anyway"
            return 1
        fi
    else
        log_info "Observability server reachable: $OBSERVABILITY_IP"
    fi

    # Check required commands
    local required_commands=("systemctl" "curl" "wget" "tar" "jq" "git")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done

    log_info "Pre-flight checks passed ✓"
    return 0
}

################################################################################
# Backup Functions
################################################################################

create_backup() {
    if [ "$SKIP_BACKUPS" = "true" ]; then
        log_warn "Skipping backup creation (SKIP_BACKUPS=true)"
        return 0
    fi

    if step_completed "backup_created"; then
        log_info "Backup already created, skipping"
        return 0
    fi

    log_info "Creating system backup..."

    execute "mkdir -p $BACKUP_DIR"

    local backup_timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="${BACKUP_DIR}/pre-deploy-${backup_timestamp}.tar.gz"

    # Backup paths
    local backup_paths=()
    [ -d "$APP_DIR" ] && backup_paths+=("$APP_DIR")
    [ -f /etc/nginx/sites-available/chom ] && backup_paths+=("/etc/nginx/sites-available/chom")
    [ -f /etc/php/${PHP_VERSION}/fpm/pool.d/chom.conf ] && backup_paths+=("/etc/php/${PHP_VERSION}/fpm/pool.d/chom.conf")

    # Database backup
    if command_exists mysql; then
        local db_backup="${BACKUP_DIR}/database-${backup_timestamp}.sql.gz"
        local db_password=$(get_state "db_password")

        if [ -n "$db_password" ]; then
            log_info "Creating database backup..."
            execute "mysqldump -u chom -p'${db_password}' chom | gzip > ${db_backup}"
            log_info "Database backup created: $db_backup"
            save_state "last_db_backup" "$db_backup"
        fi
    fi

    if [ ${#backup_paths[@]} -gt 0 ]; then
        execute "tar --exclude='${APP_DIR}/vendor' --exclude='${APP_DIR}/node_modules' --exclude='${APP_DIR}/storage/logs/*' -czf $backup_file ${backup_paths[*]}"
        log_info "Backup created: $backup_file"
        save_state "last_backup" "$backup_file"
    else
        log_info "No existing configurations to backup"
    fi

    mark_step_completed "backup_created"
    return 0
}

################################################################################
# Installation Functions
################################################################################

install_dependencies() {
    if step_completed "dependencies_installed"; then
        log_info "Dependencies already installed, skipping"
        return 0
    fi

    log_info "Installing system dependencies..."

    # Add PHP repository
    execute "apt-get update -qq"
    execute "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates apt-transport-https software-properties-common"
    execute "curl -sSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/php-archive-keyring.gpg"
    execute "echo 'deb [signed-by=/usr/share/keyrings/php-archive-keyring.gpg] https://packages.sury.org/php/ bookworm main' > /etc/apt/sources.list.d/php.list"

    execute "apt-get update -qq"

    # Install core dependencies
    execute "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        nginx \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-redis \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-bcmath \
        mariadb-server \
        mariadb-client \
        redis-server \
        certbot \
        python3-certbot-nginx \
        git \
        unzip \
        supervisor \
        ufw \
        fail2ban \
        jq"

    # Install Composer
    if ! command_exists composer; then
        log_info "Installing Composer..."
        execute "curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer"
    fi

    # Install Node.js (for asset compilation)
    if ! command_exists node; then
        log_info "Installing Node.js..."
        execute "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"
        execute "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs"
    fi

    mark_step_completed "dependencies_installed"
    log_info "Dependencies installed ✓"
    return 0
}

configure_mariadb() {
    if step_completed "mariadb_configured"; then
        log_info "MariaDB already configured, skipping"
        return 0
    fi

    log_info "Configuring MariaDB..."

    # Secure installation
    execute "systemctl start mariadb"
    execute "systemctl enable mariadb"

    # Generate database password if not provided
    if [ -z "${DB_PASSWORD:-}" ]; then
        DB_PASSWORD=$(openssl rand -base64 32)
        log_info "Generated database password"
    fi

    # Create database and user (idempotent)
    mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS chom CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'chom'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON chom.* TO 'chom'@'localhost';
FLUSH PRIVILEGES;
EOF

    # Save credentials
    cat > /root/.chom-db-credentials <<EOF
# CHOM Database Credentials
# Generated: $(date -Iseconds)

DB_HOST=localhost
DB_PORT=3306
DB_DATABASE=chom
DB_USERNAME=chom
DB_PASSWORD=${DB_PASSWORD}
EOF

    execute "chmod 600 /root/.chom-db-credentials"

    save_state "db_password" "$DB_PASSWORD"
    mark_step_completed "mariadb_configured"
    log_info "MariaDB configured ✓"
    return 0
}

configure_redis() {
    if step_completed "redis_configured"; then
        log_info "Redis already configured, skipping"
        return 0
    fi

    log_info "Configuring Redis..."

    # Generate Redis password if not provided
    if [ -z "${REDIS_PASSWORD:-}" ]; then
        REDIS_PASSWORD=$(openssl rand -base64 32)
        log_info "Generated Redis password"
    fi

    # Configure Redis
    execute "sed -i 's/^# requirepass.*/requirepass ${REDIS_PASSWORD}/' /etc/redis/redis.conf"
    execute "sed -i 's/^bind 127.0.0.1/bind 127.0.0.1/' /etc/redis/redis.conf"

    execute "systemctl restart redis-server"
    execute "systemctl enable redis-server"

    save_state "redis_password" "$REDIS_PASSWORD"
    mark_step_completed "redis_configured"
    log_info "Redis configured ✓"
    return 0
}

deploy_application() {
    if step_completed "application_deployed"; then
        log_info "Application already deployed, skipping"
        return 0
    fi

    log_info "Deploying application..."

    # Create application directory
    execute "mkdir -p $APP_DIR"

    # Clone or update repository
    if [ -d "${APP_DIR}/.git" ]; then
        log_info "Updating existing repository..."
        execute "cd $APP_DIR && git pull origin master"
    else
        log_info "Cloning repository..."
        execute "git clone https://github.com/calounx/mentat.git /tmp/mentat-repo"
        execute "cp -r /tmp/mentat-repo/chom/* $APP_DIR/"
        execute "rm -rf /tmp/mentat-repo"
    fi

    # Set permissions
    execute "chown -R $APP_USER:$APP_GROUP $APP_DIR"

    mark_step_completed "application_deployed"
    log_info "Application deployed ✓"
    return 0
}

configure_application() {
    if step_completed "application_configured"; then
        log_info "Application already configured, skipping"
        return 0
    fi

    log_info "Configuring application..."

    # Create .env file
    if [ ! -f "${APP_DIR}/.env" ]; then
        execute "cp ${APP_DIR}/.env.example ${APP_DIR}/.env"
    fi

    local db_password=$(get_state "db_password")
    local redis_password=$(get_state "redis_password")
    local app_key=$(get_state "app_key")

    # Generate APP_KEY if not exists
    if [ -z "$app_key" ]; then
        cd "$APP_DIR"
        app_key=$(sudo -u $APP_USER php artisan key:generate --show)
        save_state "app_key" "$app_key"
    fi

    # Update .env file
    cat > "${APP_DIR}/.env" <<EOF
# Application
APP_NAME=CHOM
APP_ENV=production
APP_KEY=${app_key}
APP_DEBUG=false
APP_URL=https://${DOMAIN}

# Database
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=chom
DB_USERNAME=chom
DB_PASSWORD=${db_password}

# Cache & Queue
CACHE_STORE=redis
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis

# Redis
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=${redis_password}
REDIS_PORT=6379

# Mail (Brevo)
MAIL_MAILER=smtp
MAIL_HOST=smtp-relay.brevo.com
MAIL_PORT=587
MAIL_USERNAME=9e9603001@smtp-brevo.com
MAIL_PASSWORD=
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=noreply@arewel.com
MAIL_FROM_NAME="CHOM Platform"

# Observability
PROMETHEUS_PUSHGATEWAY=${OBSERVABILITY_IP}:9091
LOKI_URL=http://${OBSERVABILITY_IP}:3100

# Security
SESSION_SECURE_COOKIE=true
SANCTUM_STATEFUL_DOMAINS=${DOMAIN}
EOF

    execute "chown $APP_USER:$APP_GROUP ${APP_DIR}/.env"
    execute "chmod 600 ${APP_DIR}/.env"

    mark_step_completed "application_configured"
    log_info "Application configured ✓"
    return 0
}

install_composer_dependencies() {
    if step_completed "composer_dependencies_installed"; then
        log_info "Composer dependencies already installed, skipping"
        return 0
    fi

    log_info "Installing Composer dependencies..."

    cd "$APP_DIR"
    execute "sudo -u $APP_USER composer install --no-dev --optimize-autoloader --no-interaction"

    mark_step_completed "composer_dependencies_installed"
    log_info "Composer dependencies installed ✓"
    return 0
}

run_migrations() {
    if [ "$SKIP_MIGRATIONS" = "true" ]; then
        log_warn "Skipping database migrations (SKIP_MIGRATIONS=true)"
        return 0
    fi

    if step_completed "migrations_run"; then
        log_info "Migrations already run, skipping"
        return 0
    fi

    log_info "Running database migrations..."

    cd "$APP_DIR"
    execute "sudo -u $APP_USER php artisan migrate --force"

    mark_step_completed "migrations_run"
    log_info "Migrations completed ✓"
    return 0
}

optimize_application() {
    if step_completed "application_optimized"; then
        log_info "Application already optimized, skipping"
        return 0
    fi

    log_info "Optimizing application..."

    cd "$APP_DIR"
    execute "sudo -u $APP_USER php artisan config:cache"
    execute "sudo -u $APP_USER php artisan route:cache"
    execute "sudo -u $APP_USER php artisan view:cache"
    execute "sudo -u $APP_USER php artisan event:cache"

    mark_step_completed "application_optimized"
    log_info "Application optimized ✓"
    return 0
}

configure_nginx() {
    if step_completed "nginx_configured"; then
        log_info "Nginx already configured, skipping"
        return 0
    fi

    log_info "Configuring Nginx..."

    cat > /etc/nginx/sites-available/chom <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root ${APP_DIR}/public;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

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
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

    # Metrics endpoint for Prometheus
    location /metrics {
        access_log off;
        allow ${OBSERVABILITY_IP};
        deny all;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root/index.php;
    }
}
EOF

    execute "ln -sf /etc/nginx/sites-available/chom /etc/nginx/sites-enabled/"
    execute "rm -f /etc/nginx/sites-enabled/default"
    execute "nginx -t"
    execute "systemctl reload nginx"

    mark_step_completed "nginx_configured"
    log_info "Nginx configured ✓"
    return 0
}

setup_ssl() {
    if step_completed "ssl_configured"; then
        log_info "SSL already configured, skipping"
        return 0
    fi

    log_info "Setting up SSL with Let's Encrypt..."

    execute "certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos --email ${SSL_EMAIL} --redirect"

    mark_step_completed "ssl_configured"
    log_info "SSL configured ✓"
    return 0
}

configure_supervisor() {
    if step_completed "supervisor_configured"; then
        log_info "Supervisor already configured, skipping"
        return 0
    fi

    log_info "Configuring Supervisor for queue workers..."

    cat > /etc/supervisor/conf.d/chom-worker.conf <<EOF
[program:chom-worker]
process_name=%(program_name)s_%(process_num)02d
command=php ${APP_DIR}/artisan queue:work redis --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=${APP_USER}
numprocs=2
redirect_stderr=true
stdout_logfile=${APP_DIR}/storage/logs/worker.log
stopwaitsecs=3600
EOF

    execute "supervisorctl reread"
    execute "supervisorctl update"
    execute "supervisorctl start chom-worker:*"

    mark_step_completed "supervisor_configured"
    log_info "Supervisor configured ✓"
    return 0
}

configure_firewall() {
    if step_completed "firewall_configured"; then
        log_info "Firewall already configured, skipping"
        return 0
    fi

    log_info "Configuring firewall..."

    execute "ufw --force reset"
    execute "ufw default deny incoming"
    execute "ufw default allow outgoing"

    # Allow SSH
    execute "ufw allow ssh"

    # Allow HTTP/HTTPS
    execute "ufw allow 80/tcp"
    execute "ufw allow 443/tcp"

    # Allow metrics from observability server
    execute "ufw allow from ${OBSERVABILITY_IP} to any port 9100 proto tcp comment 'Node Exporter from Observability'"

    execute "ufw --force enable"

    mark_step_completed "firewall_configured"
    log_info "Firewall configured ✓"
    return 0
}

setup_cron() {
    if step_completed "cron_configured"; then
        log_info "Cron already configured, skipping"
        return 0
    fi

    log_info "Setting up Laravel scheduler..."

    # Add Laravel scheduler to crontab
    (crontab -u $APP_USER -l 2>/dev/null; echo "* * * * * cd ${APP_DIR} && php artisan schedule:run >> /dev/null 2>&1") | crontab -u $APP_USER -

    mark_step_completed "cron_configured"
    log_info "Cron configured ✓"
    return 0
}

################################################################################
# Verification Functions
################################################################################

verify_deployment() {
    log_info "Verifying deployment..."

    local failed=0

    # Check services
    local services=("nginx" "php${PHP_VERSION}-fpm" "mariadb" "redis-server" "supervisor")
    for service in "${services[@]}"; do
        if service_running "$service"; then
            log_info "✓ Service $service is running"
        else
            log_error "✗ Service $service is not running"
            failed=$((failed + 1))
        fi
    done

    # Check database connection
    cd "$APP_DIR"
    if sudo -u $APP_USER php artisan db:show >/dev/null 2>&1; then
        log_info "✓ Database connection successful"
    else
        log_error "✗ Database connection failed"
        failed=$((failed + 1))
    fi

    # Check Redis connection
    if redis-cli -a "$(get_state "redis_password")" ping >/dev/null 2>&1; then
        log_info "✓ Redis connection successful"
    else
        log_error "✗ Redis connection failed"
        failed=$((failed + 1))
    fi

    # Check HTTP endpoint
    if curl -sf "http://localhost" >/dev/null 2>&1; then
        log_info "✓ HTTP endpoint responding"
    else
        log_error "✗ HTTP endpoint not responding"
        failed=$((failed + 1))
    fi

    # Check HTTPS
    if curl -sf "https://${DOMAIN}" >/dev/null 2>&1; then
        log_info "✓ HTTPS is working"
    else
        log_warn "✗ HTTPS check failed (may take a few moments to propagate)"
    fi

    # Check queue workers
    if supervisorctl status chom-worker:* | grep -q RUNNING; then
        log_info "✓ Queue workers running"
    else
        log_error "✗ Queue workers not running"
        failed=$((failed + 1))
    fi

    if [ $failed -eq 0 ]; then
        log_info "Deployment verification passed ✓"
        return 0
    else
        log_error "Deployment verification failed: $failed checks failed"
        return 1
    fi
}

################################################################################
# Rollback Functions
################################################################################

rollback_deployment() {
    log_warn "Rolling back deployment..."

    local backup_file=$(get_state "last_backup")
    local db_backup=$(get_state "last_db_backup")

    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log_error "No backup found to restore"
        return 1
    fi

    log_info "Restoring from backup: $backup_file"

    # Stop services
    execute "supervisorctl stop chom-worker:*"
    execute "systemctl stop php${PHP_VERSION}-fpm"
    execute "systemctl stop nginx"

    # Restore application
    execute "rm -rf ${APP_DIR}.rollback"
    execute "mv $APP_DIR ${APP_DIR}.rollback"
    execute "mkdir -p $APP_DIR"
    execute "tar -xzf $backup_file -C /"

    # Restore database if available
    if [ -n "$db_backup" ] && [ -f "$db_backup" ]; then
        log_info "Restoring database from: $db_backup"
        local db_password=$(get_state "db_password")
        execute "gunzip < $db_backup | mysql -u chom -p'${db_password}' chom"
    fi

    # Restart services
    execute "systemctl start nginx"
    execute "systemctl start php${PHP_VERSION}-fpm"
    execute "supervisorctl start chom-worker:*"

    # Clear deployment state
    execute "rm -f $STATE_FILE"

    log_info "Rollback completed"
    log_info "Failed deployment saved to: ${APP_DIR}.rollback"
    return 0
}

################################################################################
# Main Deployment Flow
################################################################################

deploy() {
    log_info "=========================================="
    log_info "CHOM Application Deployment"
    log_info "Version: $SCRIPT_VERSION"
    log_info "Domain: $DOMAIN"
    log_info "=========================================="

    # Pre-flight checks
    preflight_checks || return 1

    # Backup
    create_backup || return 1

    # Install
    install_dependencies || return 1
    configure_mariadb || return 1
    configure_redis || return 1

    # Deploy application
    deploy_application || return 1
    configure_application || return 1
    install_composer_dependencies || return 1
    run_migrations || return 1
    optimize_application || return 1

    # Configure services
    configure_nginx || return 1
    setup_ssl || return 1
    configure_supervisor || return 1
    configure_firewall || return 1
    setup_cron || return 1

    # Verify
    verify_deployment || return 1

    # Save completion
    mark_step_completed "deployment_complete"
    save_state "deployment_version" "$SCRIPT_VERSION"
    save_state "deployment_timestamp" "$(date -Iseconds)"

    log_info "=========================================="
    log_info "Deployment completed successfully!"
    log_info "=========================================="
    log_info ""
    log_info "Application URL: https://${DOMAIN}"
    log_info ""
    log_info "Credentials saved to:"
    log_info "  Database: /root/.chom-db-credentials"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Configure Brevo email (add MAIL_PASSWORD to .env)"
    log_info "  2. Create first admin user"
    log_info "  3. Import Grafana dashboards"
    log_info "  4. Run load tests"
    log_info ""
    log_info "Log file: $LOG_FILE"
    log_info ""

    return 0
}

################################################################################
# Entry Point
################################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --rollback)
                ROLLBACK=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --skip-migrations)
                SKIP_MIGRATIONS=true
                shift
                ;;
            --help|-h)
                cat <<EOF
Usage: $0 [OPTIONS]

Options:
    --dry-run           Simulate deployment without making changes
    --rollback          Rollback to previous state
    --force             Force deployment even if checks fail
    --skip-migrations   Skip database migrations
    --help, -h          Show this help message

Environment Variables:
    DOMAIN                Domain name (default: landsraad.arewel.com)
    SSL_EMAIL            Email for Let's Encrypt (default: admin@arewel.com)
    DB_PASSWORD          Database password (auto-generated if not set)
    REDIS_PASSWORD       Redis password (auto-generated if not set)
    OBSERVABILITY_IP     Observability server IP (default: 51.254.139.78)
    SKIP_MIGRATIONS      Skip database migrations (default: false)
    SKIP_BACKUPS         Skip backup creation (default: false)

Examples:
    # Normal deployment
    ./deploy-chom.sh

    # Dry run
    ./deploy-chom.sh --dry-run

    # Force deployment
    DOMAIN=custom.domain.com ./deploy-chom.sh --force

    # Rollback
    ./deploy-chom.sh --rollback
EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Create log directory
    mkdir -p "$LOG_DIR"

    # Execute rollback or deployment
    if [ "$ROLLBACK" = true ]; then
        rollback_deployment
        exit $?
    else
        deploy
        exit $?
    fi
}

# Run main function
main "$@"
