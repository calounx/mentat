#!/usr/bin/env bash
# Prepare landsraad.arewel.com for CHOM application deployment
# This script installs and configures all required software
# Usage: ./prepare-landsraad.sh
#
# IDEMPOTENT: Safe to run multiple times - checks before installing
# - Skips if software already installed
# - Preserves existing configurations
# - Only installs/updates what's needed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/logging.sh"

# Configuration
PHP_VERSION="${PHP_VERSION:-8.2}"
POSTGRES_VERSION="${POSTGRES_VERSION:-15}"
NODE_VERSION="${NODE_VERSION:-20}"
DEPLOY_USER="${DEPLOY_USER:-stilgar}"
APP_DIR="${APP_DIR:-/var/www/chom}"
DOMAIN="${DOMAIN:-chom.arewel.com}"

init_deployment_log "prepare-landsraad-$(date +%Y%m%d_%H%M%S)"
log_section "Preparing landsraad.arewel.com"

# Update system packages
update_system() {
    log_step "Updating system packages"

    sudo apt-get update
    sudo apt-get upgrade -y
    # Install essential packages for Debian 13 (Trixie)
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        apt-transport-https \
        wget \
        git \
        unzip \
        supervisor \
        htop \
        vim \
        net-tools \
        dnsutils

    log_success "System packages updated"
}

# Install PHP and extensions
install_php() {
    log_step "Installing PHP ${PHP_VERSION} and extensions"

    # Check if PHP is already installed
    if command -v php &>/dev/null; then
        local installed_version=$(php -v | head -1 | awk '{print $2}' | cut -d. -f1,2)
        if [[ "$installed_version" == "$PHP_VERSION" ]]; then
            log_success "PHP ${PHP_VERSION} already installed"
            php -v | head -1 | tee -a "$LOG_FILE"
            return 0
        else
            log_info "PHP $installed_version found, installing PHP ${PHP_VERSION}"
        fi
    fi

    # Add Sury PHP repository for latest PHP versions
    if [[ ! -f /etc/apt/sources.list.d/php.list ]]; then

        # Get Debian codename (e.g., trixie for Debian 13)
        DEBIAN_CODENAME=$(lsb_release -sc)

        # Download and install GPG key using proper keyring location
        if [[ ! -f /etc/apt/trusted.gpg.d/php.gpg ]]; then
            wget -qO - https://packages.sury.org/php/apt.gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/php.gpg
        fi
        echo "deb https://packages.sury.org/php/ ${DEBIAN_CODENAME} main" | sudo tee /etc/apt/sources.list.d/php.list
        sudo apt-get update
    fi

    sudo apt-get install -y \
        php${PHP_VERSION} \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-common \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-pgsql \
        php${PHP_VERSION}-redis \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-soap \
        php${PHP_VERSION}-imagick \
        php${PHP_VERSION}-opcache

    # Enable and start PHP-FPM
    sudo systemctl enable php${PHP_VERSION}-fpm
    sudo systemctl start php${PHP_VERSION}-fpm

    log_success "PHP ${PHP_VERSION} installed and configured"

    php -v | head -1 | tee -a "$LOG_FILE"
}

# Install Composer
install_composer() {
    log_step "Installing Composer"

    if command -v composer &> /dev/null; then
        log_success "Composer is already installed"
        composer --version | tee -a "$LOG_FILE"
        return 0
    fi

    # Download and install Composer
    curl -sS https://getcomposer.org/installer | php
    sudo mv composer.phar /usr/local/bin/composer
    sudo chmod +x /usr/local/bin/composer

    log_success "Composer installed"
    composer --version | tee -a "$LOG_FILE"
}

# Install Node.js and NPM
install_nodejs() {
    log_step "Installing Node.js ${NODE_VERSION}"

    if command -v node &> /dev/null; then
        local current_version=$(node --version)
        log_success "Node.js is already installed: $current_version"
        return 0
    fi

    # Install Node.js from NodeSource
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo -E bash -
    sudo apt-get install -y nodejs

    log_success "Node.js installed"
    node --version | tee -a "$LOG_FILE"
    npm --version | tee -a "$LOG_FILE"
}

# Install PostgreSQL
install_postgresql() {
    log_step "Installing PostgreSQL ${POSTGRES_VERSION}"

    # Check if PostgreSQL is already installed
    if command -v psql &>/dev/null; then
        local installed_version=$(psql --version | awk '{print $3}' | cut -d. -f1)
        if [[ "$installed_version" == "$POSTGRES_VERSION" ]]; then
            log_success "PostgreSQL ${POSTGRES_VERSION} already installed"
            psql --version | tee -a "$LOG_FILE"
            return 0
        else
            log_info "PostgreSQL $installed_version found, upgrading to ${POSTGRES_VERSION}"
        fi
    fi

    # Add PostgreSQL repository
    if [[ ! -f /etc/apt/sources.list.d/pgdg.list ]]; then
        # Get Debian codename
        DEBIAN_CODENAME=$(lsb_release -cs)

        # Download and install GPG key
        if [[ ! -f /etc/apt/trusted.gpg.d/postgresql.gpg ]]; then
            wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
        fi
        echo "deb http://apt.postgresql.org/pub/repos/apt ${DEBIAN_CODENAME}-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
        sudo apt-get update
    fi

    sudo apt-get install -y postgresql-${POSTGRES_VERSION} postgresql-client-${POSTGRES_VERSION}

    # Enable and start PostgreSQL
    sudo systemctl enable postgresql
    sudo systemctl start postgresql

    log_success "PostgreSQL ${POSTGRES_VERSION} installed"

    sudo -u postgres psql --version | tee -a "$LOG_FILE"
}

# Install Redis
install_redis() {
    log_step "Installing Redis"

    sudo apt-get install -y redis-server

    # Configure Redis
    sudo sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf
    sudo sed -i 's/^bind 127.0.0.1/bind 127.0.0.1/' /etc/redis/redis.conf

    # Enable and start Redis
    sudo systemctl enable redis-server
    sudo systemctl start redis-server

    log_success "Redis installed and configured"

    redis-cli --version | tee -a "$LOG_FILE"
}

# Install Nginx
install_nginx() {
    log_step "Installing Nginx"

    sudo apt-get install -y nginx

    # Enable and start Nginx
    sudo systemctl enable nginx
    sudo systemctl start nginx

    log_success "Nginx installed"

    nginx -v 2>&1 | tee -a "$LOG_FILE"
}

# Create deployment user
create_deploy_user() {
    log_step "Creating deployment user: $DEPLOY_USER"

    if id "$DEPLOY_USER" &>/dev/null; then
        log_success "User $DEPLOY_USER already exists"
        return 0
    fi

    # Create user with home directory
    sudo useradd -m -s /bin/bash "$DEPLOY_USER"

    # Add to www-data group
    sudo usermod -aG www-data "$DEPLOY_USER"

    # Create .ssh directory
    sudo mkdir -p /home/${DEPLOY_USER}/.ssh
    sudo chown -R ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh
    sudo chmod 700 /home/${DEPLOY_USER}/.ssh

    log_success "User $DEPLOY_USER created"
}

# Setup application directory
setup_app_directory() {
    log_step "Setting up application directory"

    # Create application directory
    sudo mkdir -p "$APP_DIR"
    sudo chown -R ${DEPLOY_USER}:www-data "$APP_DIR"
    sudo chmod -R 775 "$APP_DIR"

    # Create releases directory for zero-downtime deployments
    sudo mkdir -p "${APP_DIR}/releases"
    sudo mkdir -p "${APP_DIR}/shared"
    sudo mkdir -p "${APP_DIR}/shared/storage"

    # Create shared directories
    sudo mkdir -p "${APP_DIR}/shared/storage/app"
    sudo mkdir -p "${APP_DIR}/shared/storage/framework/cache"
    sudo mkdir -p "${APP_DIR}/shared/storage/framework/sessions"
    sudo mkdir -p "${APP_DIR}/shared/storage/framework/views"
    sudo mkdir -p "${APP_DIR}/shared/storage/logs"

    sudo chown -R ${DEPLOY_USER}:www-data "${APP_DIR}/shared"
    sudo chmod -R 775 "${APP_DIR}/shared"

    log_success "Application directory configured"
}

# Configure PostgreSQL database
configure_database() {
    log_step "Configuring PostgreSQL database"

    local db_name="${DB_NAME:-chom}"
    local db_user="${DB_USER:-chom}"
    local db_password="${DB_PASSWORD:-$(openssl rand -base64 32)}"

    # Create database user
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$db_user'" | grep -q 1; then
        log_success "Database user $db_user already exists"
    else
        sudo -u postgres psql -c "CREATE USER $db_user WITH ENCRYPTED PASSWORD '$db_password';"
        log_success "Database user $db_user created"
    fi

    # Create database
    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$db_name"; then
        log_success "Database $db_name already exists"
    else
        sudo -u postgres psql -c "CREATE DATABASE $db_name OWNER $db_user;"
        log_success "Database $db_name created"
    fi

    # Grant privileges
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $db_name TO $db_user;"

    log_success "Database configured"
    log_warning "Database password: $db_password"
    log_warning "Save this password to your .env file"
}

# Install monitoring tools
install_monitoring() {
    log_step "Installing monitoring tools"

    # Install Node Exporter for Prometheus
    local node_exporter_version="1.7.0"
    local node_exporter_url="https://github.com/prometheus/node_exporter/releases/download/v${node_exporter_version}/node_exporter-${node_exporter_version}.linux-amd64.tar.gz"

    cd /tmp
    wget -q "$node_exporter_url"
    tar xzf "node_exporter-${node_exporter_version}.linux-amd64.tar.gz"
    sudo mv "node_exporter-${node_exporter_version}.linux-amd64/node_exporter" /usr/local/bin/
    rm -rf "node_exporter-${node_exporter_version}.linux-amd64"*

    # Create systemd service for node_exporter
    sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable node_exporter
    sudo systemctl start node_exporter

    log_success "Node Exporter installed and running"
}

# Configure PHP-FPM pool
configure_php_fpm() {
    log_step "Configuring PHP-FPM pool"

    local pool_config="/etc/php/${PHP_VERSION}/fpm/pool.d/chom.conf"

    sudo tee "$pool_config" > /dev/null <<EOF
[chom]
user = ${DEPLOY_USER}
group = www-data
listen = /run/php/php${PHP_VERSION}-fpm-chom.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.max_requests = 500

php_admin_value[error_log] = /var/log/php${PHP_VERSION}-fpm-chom.log
php_admin_flag[log_errors] = on

php_value[session.save_handler] = redis
php_value[session.save_path] = tcp://127.0.0.1:6379

catch_workers_output = yes
decorate_workers_output = no
EOF

    sudo systemctl restart php${PHP_VERSION}-fpm

    log_success "PHP-FPM pool configured"
}

# Configure supervisor for queue workers
configure_supervisor() {
    log_step "Configuring Supervisor for Laravel queues"

    sudo tee /etc/supervisor/conf.d/chom-worker.conf > /dev/null <<EOF
[program:chom-worker]
process_name=%(program_name)s_%(process_num)02d
command=php ${APP_DIR}/current/artisan queue:work redis --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=${DEPLOY_USER}
numprocs=4
redirect_stderr=true
stdout_logfile=${APP_DIR}/shared/storage/logs/worker.log
stopwaitsecs=3600
EOF

    # Note: supervisor will be reloaded after first deployment

    log_success "Supervisor configured"
}

# Setup log rotation
setup_log_rotation() {
    log_step "Setting up log rotation"

    sudo tee /etc/logrotate.d/chom > /dev/null <<EOF
${APP_DIR}/shared/storage/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0664 ${DEPLOY_USER} www-data
    sharedscripts
    postrotate
        systemctl reload php${PHP_VERSION}-fpm > /dev/null 2>&1 || true
    endscript
}
EOF

    log_success "Log rotation configured"
}

# Harden system security
harden_security() {
    log_step "Hardening system security"

    # Disable root SSH login
    sudo sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

    # Disable password authentication (use SSH keys only)
    sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

    # Restart SSH
    sudo systemctl restart sshd

    # Configure automatic security updates
    sudo apt-get install -y unattended-upgrades
    sudo dpkg-reconfigure -plow unattended-upgrades

    log_success "Security hardening applied"
}

# Main execution
main() {
    start_timer

    print_header "Preparing landsraad.arewel.com for CHOM deployment"

    update_system
    create_deploy_user
    install_php
    install_composer
    install_nodejs
    install_postgresql
    install_redis
    install_nginx
    setup_app_directory
    configure_database
    install_monitoring
    configure_php_fpm
    configure_supervisor
    setup_log_rotation
    harden_security

    end_timer "Server preparation"

    print_header "Server Preparation Complete"
    log_success "landsraad.arewel.com is ready for CHOM deployment"
    log_info "Next steps:"
    log_info "  1. Run setup-firewall.sh --server landsraad"
    log_info "  2. Run setup-ssl.sh --domain $DOMAIN --email your@email.com"
    log_info "  3. Configure Nginx with the application configuration"
    log_info "  4. Deploy the application with deploy-application.sh"
}

main
