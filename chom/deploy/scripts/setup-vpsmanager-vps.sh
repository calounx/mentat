#!/bin/bash
#
# CHOM VPSManager Setup Script
# For vanilla Debian 13 VPS
#
# Installs: Nginx, PHP-FPM, MariaDB, Redis, VPSManager
#

set -euo pipefail

# Configuration
OBSERVABILITY_IP="${OBSERVABILITY_IP:-}"
VPSMANAGER_REPO="https://github.com/calounx/vpsmanager.git"

# Versions
PHP_VERSIONS=("8.2" "8.4")
MARIADB_VERSION="11.4"
REDIS_VERSION="7"
NODE_EXPORTER_VERSION="1.8.2"

# Paths
VPSMANAGER_DIR="/opt/vpsmanager"
CONFIG_DIR="/etc/vpsmanager"
LOG_DIR="/var/log/vpsmanager"
WWW_DIR="/var/www"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Helper: Write to system files (requires sudo)
write_system_file() {
    local file="$1"
    sudo tee "$file" > /dev/null
}

# Stop service and verify binary is not in use before replacement
stop_and_verify_service() {
    local service_name="$1"
    local binary_path="$2"
    local max_wait=30
    local waited=0

    # Check if service exists
    if ! systemctl list-unit-files | grep -q "^${service_name}.service"; then
        log_info "Service ${service_name} does not exist yet, skipping stop"
        return 0
    fi

    # Stop service if running
    if systemctl is-active --quiet "$service_name"; then
        log_info "Stopping ${service_name}..."
sudo systemctl stop "$service_name" || {
            log_error "Failed to stop ${service_name}"
            return 1
        }
    fi

    # Wait for binary to be released
    while [[ $waited -lt $max_wait ]]; do
        if ! lsof "$binary_path" &>/dev/null; then
            log_success "${service_name} stopped and binary released"
            return 0
        fi
        sleep 1
        ((waited++))
    done

    log_error "Timeout waiting for ${binary_path} to be released"
    return 1
}

# Check if user has sudo access
if ! sudo -n true 2>/dev/null; then
    log_error "This script requires passwordless sudo access"
    log_error "Please run: sudo visudo and add: $USER ALL=(ALL) NOPASSWD:ALL"
    exit 1
fi

log_info "Starting VPSManager installation..."

# =============================================================================
# SYSTEM SETUP
# =============================================================================

log_info "Updating system packages..."
sudo apt-get update -qq
sudo apt-get upgrade -y -qq

log_info "Installing base dependencies..."
sudo apt-get install -y -qq \
    curl \
    wget \
    gnupg \
    apt-transport-https \
    unzip \
    git \
    jq \
    certbot \
    python3-certbot-nginx \
    ufw \
    fail2ban \
    htop \
    ncdu

# Create directories
sudo mkdir -p "$VPSMANAGER_DIR"
sudo mkdir -p "$CONFIG_DIR"
sudo mkdir -p "$LOG_DIR"
sudo mkdir -p "$WWW_DIR"

# =============================================================================
# NGINX
# =============================================================================

log_info "Installing Nginx..."

sudo apt-get install -y -qq nginx

# Basic nginx optimization
write_system_file /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
    multi_accept on;
    use epoll;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

# =============================================================================
# PHP
# =============================================================================

log_info "Installing PHP..."

# Add PHP repository
sudo wget -qO /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list > /dev/null
sudo apt-get update -qq

for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    log_info "Installing PHP ${PHP_VERSION}..."
sudo apt-get install -y -qq \
        "php${PHP_VERSION}-fpm" \
        "php${PHP_VERSION}-cli" \
        "php${PHP_VERSION}-common" \
        "php${PHP_VERSION}-mysql" \
        "php${PHP_VERSION}-xml" \
        "php${PHP_VERSION}-mbstring" \
        "php${PHP_VERSION}-curl" \
        "php${PHP_VERSION}-zip" \
        "php${PHP_VERSION}-gd" \
        "php${PHP_VERSION}-intl" \
        "php${PHP_VERSION}-bcmath" \
        "php${PHP_VERSION}-redis" \
        "php${PHP_VERSION}-imagick" \
        "php${PHP_VERSION}-opcache"
done

# PHP optimization for WordPress
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    write_system_file "/etc/php/${PHP_VERSION}/fpm/conf.d/99-wordpress.ini" << 'EOF'
upload_max_filesize = 64M
post_max_size = 64M
memory_limit = 256M
max_execution_time = 300
max_input_vars = 3000
opcache.enable = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 8
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 2
EOF
done

# =============================================================================
# MARIADB
# =============================================================================

log_info "Installing MariaDB..."

# Use Debian default MariaDB (Debian 13 has MariaDB 10.11)
# Third-party repos don't support Debian 13 (trixie) yet
sudo apt-get install -y -qq mariadb-server mariadb-client

# Generate root password
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)

# Secure installation
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"

# Use .my.cnf to avoid password in process list
# Create secure temporary file to prevent race condition attacks
MYSQL_CNF_FILE=$(mktemp -t mysql.XXXXXX)
sudo chmod 600 "$MYSQL_CNF_FILE"  # Set permissions before writing sensitive data

write_system_file "$MYSQL_CNF_FILE" << EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOF

sudo mysql --defaults-extra-file="$MYSQL_CNF_FILE" << 'SQL'
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL

# Securely clean up temporary file
shred -u "$MYSQL_CNF_FILE" 2>/dev/null || rm -f "$MYSQL_CNF_FILE"

# MariaDB optimization
write_system_file /etc/mysql/mariadb.conf.d/99-optimization.cnf << 'EOF'
[mysqld]
innodb_buffer_pool_size = 256M
innodb_log_file_size = 64M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
max_connections = 200
query_cache_type = 1
query_cache_size = 32M
query_cache_limit = 2M
EOF

sudo systemctl restart mariadb

# =============================================================================
# REDIS
# =============================================================================

log_info "Installing Redis..."

sudo apt-get install -y -qq redis-server

# Redis optimization
sed -i 's/^# maxmemory .*/maxmemory 128mb/' /etc/redis/redis.conf
sed -i 's/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf

sudo systemctl restart redis-server

# =============================================================================
# COMPOSER
# =============================================================================

log_info "Installing Composer..."

curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# =============================================================================
# VPSMANAGER
# =============================================================================

log_info "Installing VPSManager..."

# Clone VPSManager repository
if [[ -d "$VPSMANAGER_DIR/.git" ]]; then
    cd "$VPSMANAGER_DIR"
    git pull
else
    git clone "$VPSMANAGER_REPO" "$VPSMANAGER_DIR" || {
        log_warn "Could not clone VPSManager repo, creating placeholder"
sudo mkdir -p "$VPSMANAGER_DIR/bin"
    }
fi

# Install dependencies if composer.json exists
if [[ -f "$VPSMANAGER_DIR/composer.json" ]]; then
    cd "$VPSMANAGER_DIR"
    composer install --no-dev --optimize-autoloader
fi

# Create vpsmanager symlink
if [[ -f "$VPSMANAGER_DIR/bin/vpsmanager" ]]; then
    sudo ln -sf "$VPSMANAGER_DIR/bin/vpsmanager" /usr/local/bin/vpsmanager
fi

# VPSManager config
sudo mkdir -p "$CONFIG_DIR"
write_system_file "$CONFIG_DIR/config.yaml" << EOF
# VPSManager Configuration
php:
  default_version: "8.2"
  supported_versions:
    - "8.2"
    - "8.4"

observability:
  enabled: true
  prometheus_url: "http://${OBSERVABILITY_IP:-localhost}:9090"
  loki_url: "http://${OBSERVABILITY_IP:-localhost}:3100"

paths:
  www_root: "${WWW_DIR}"
  log_dir: "${LOG_DIR}"
  backup_dir: "/var/backups/vpsmanager"

security:
  ssh_port: 22
  fail2ban_enabled: true
EOF

# =============================================================================
# NODE EXPORTER (for observability)
# =============================================================================

log_info "Installing Node Exporter..."

cd /tmp
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

# Stop node_exporter service before replacing binary
stop_and_verify_service "node_exporter" "/usr/local/bin/node_exporter" || {
    log_error "Failed to stop node_exporter safely"
    exit 1
}

sudo cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"*

sudo useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter || true

write_system_file /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter

# =============================================================================
# VPSMANAGER DASHBOARD
# =============================================================================

log_info "Setting up VPSManager Dashboard..."

# Create dashboard directory
sudo mkdir -p /var/www/dashboard

# Generate dashboard credentials
DASHBOARD_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 16)
DASHBOARD_PASSWORD_HASH=$(php -r "echo password_hash('${DASHBOARD_PASSWORD}', PASSWORD_BCRYPT);")

write_system_file /var/www/dashboard/index.php << 'DASHBOARD_EOF'
<?php
// VPSManager Dashboard with Security Hardening
session_start();

$auth_file = '/etc/vpsmanager/dashboard-auth.php';
if (file_exists($auth_file)) {
    require $auth_file;
}

// Rate limiting configuration
$attempts_file = '/tmp/dashboard_login_attempts_' . md5($_SERVER['REMOTE_ADDR']);
$max_attempts = 5;
$lockout_duration = 300; // 5 minutes

function check_rate_limit($attempts_file, $max_attempts, $lockout_duration) {
    if (file_exists($attempts_file)) {
        $attempts = json_decode(file_get_contents($attempts_file), true);
        if (!is_array($attempts)) $attempts = [];

        // Clean old attempts
        $recent_attempts = array_filter($attempts, function($time) use ($lockout_duration) {
            return (time() - $time) < $lockout_duration;
        });

        if (count($recent_attempts) >= $max_attempts) {
            return false;
        }
    }
    return true;
}

function record_failed_attempt($attempts_file) {
    $attempts = file_exists($attempts_file)
        ? json_decode(file_get_contents($attempts_file), true)
        : [];
    if (!is_array($attempts)) $attempts = [];

    $attempts[] = time();
    file_put_contents($attempts_file, json_encode($attempts));
    chmod($attempts_file, 0600);
}

function clear_attempts($attempts_file) {
    @unlink($attempts_file);
}

function get_uptime() {
    // SECURITY: Use native PHP instead of shell_exec
    if (file_exists('/proc/uptime')) {
        $uptime_seconds = (int) explode(' ', file_get_contents('/proc/uptime'))[0];
        $days = floor($uptime_seconds / 86400);
        $hours = floor(($uptime_seconds % 86400) / 3600);
        return "{$days}d {$hours}h";
    }
    return 'N/A';
}

if (!isset($_SESSION['authenticated']) || $_SESSION['authenticated'] !== true) {
    $error_message = '';

    if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['password'])) {
        if (!check_rate_limit($attempts_file, $max_attempts, $lockout_duration)) {
            http_response_code(429);
            $error_message = 'Too many failed attempts. Try again in 5 minutes.';
            error_log("Dashboard: Rate limit exceeded from {$_SERVER['REMOTE_ADDR']}");
            sleep(2); // Slow down attacker
        } elseif (password_verify($_POST['password'], $password_hash ?? '')) {
            // Success - clear attempts
            clear_attempts($attempts_file);

            // Regenerate session ID to prevent fixation
            session_regenerate_id(true);
            $_SESSION['authenticated'] = true;
            $_SESSION['login_time'] = time();
            $_SESSION['ip'] = $_SERVER['REMOTE_ADDR'];

            // Log successful login
            error_log("Dashboard: Successful login from {$_SERVER['REMOTE_ADDR']}");

            header('Location: /');
            exit;
        } else {
            // Failed attempt
            record_failed_attempt($attempts_file);
            error_log("Dashboard: Failed login attempt from {$_SERVER['REMOTE_ADDR']}");
            $error_message = 'Invalid password';
            sleep(2); // Slow down brute force
        }
    }
    ?>
    <!DOCTYPE html>
    <html>
    <head>
        <title>VPSManager Login</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
    </head>
    <body style="font-family: sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #f5f5f5;">
        <form method="post" style="padding: 2rem; border: 1px solid #ccc; border-radius: 8px; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
            <h2 style="margin-top: 0;">VPSManager Dashboard</h2>
            <?php if ($error_message): ?>
            <div style="color: #dc2626; background: #fee2e2; padding: 0.75rem; border-radius: 4px; margin-bottom: 1rem;">
                <?= htmlspecialchars($error_message) ?>
            </div>
            <?php endif; ?>
            <input type="password" name="password" placeholder="Password" required style="padding: 0.5rem; width: 200px; border: 1px solid #ccc; border-radius: 4px;"><br><br>
            <button type="submit" style="padding: 0.5rem 1rem; background: #2563eb; color: white; border: none; border-radius: 4px; cursor: pointer;">Login</button>
        </form>
    </body>
    </html>
    <?php
    exit;
}

// Session validation
if (isset($_SESSION['ip']) && $_SESSION['ip'] !== $_SERVER['REMOTE_ADDR']) {
    session_destroy();
    header('Location: /');
    exit;
}

// Dashboard content
$sites = [];
$www_dir = '/var/www';
foreach (glob("$www_dir/*/public") as $path) {
    $domain = basename(dirname($path));
    if ($domain !== 'dashboard') {
        $sites[] = $domain;
    }
}

$system_info = [
    'hostname' => gethostname(),
    'uptime' => get_uptime(), // SECURITY: Native PHP instead of shell_exec
    'load' => sys_getloadavg()[0],
    'memory_used' => round(memory_get_usage(true) / 1024 / 1024, 2) . ' MB',
    'disk_free' => round(disk_free_space('/') / 1024 / 1024 / 1024, 2) . ' GB',
];
?>
<!DOCTYPE html>
<html>
<head>
    <title>VPSManager Dashboard</title>
    <style>
        body { font-family: sans-serif; margin: 2rem; background: #f5f5f5; }
        .card { background: white; padding: 1.5rem; border-radius: 8px; margin-bottom: 1rem; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; }
        .stat { text-align: center; }
        .stat-value { font-size: 2rem; font-weight: bold; color: #2563eb; }
        .stat-label { color: #666; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 0.75rem; text-align: left; border-bottom: 1px solid #eee; }
        .badge { display: inline-block; padding: 0.25rem 0.5rem; border-radius: 4px; font-size: 0.875rem; }
        .badge-green { background: #dcfce7; color: #166534; }
    </style>
</head>
<body>
    <h1>VPSManager Dashboard</h1>

    <div class="card">
        <h2>System Status</h2>
        <div class="grid">
            <div class="stat">
                <div class="stat-value"><?= count($sites) ?></div>
                <div class="stat-label">Active Sites</div>
            </div>
            <div class="stat">
                <div class="stat-value"><?= $system_info['load'] ?></div>
                <div class="stat-label">Load Average</div>
            </div>
            <div class="stat">
                <div class="stat-value"><?= $system_info['disk_free'] ?></div>
                <div class="stat-label">Disk Free</div>
            </div>
        </div>
    </div>

    <div class="card">
        <h2>Sites</h2>
        <table>
            <tr><th>Domain</th><th>Status</th></tr>
            <?php foreach ($sites as $site): ?>
            <tr>
                <td><a href="https://<?= htmlspecialchars($site) ?>" target="_blank"><?= htmlspecialchars($site) ?></a></td>
                <td><span class="badge badge-green">Active</span></td>
            </tr>
            <?php endforeach; ?>
            <?php if (empty($sites)): ?>
            <tr><td colspan="2">No sites configured yet</td></tr>
            <?php endif; ?>
        </table>
    </div>

    <div class="card">
        <h2>Server Info</h2>
        <p><strong>Hostname:</strong> <?= htmlspecialchars($system_info['hostname']) ?></p>
        <p><strong>Uptime:</strong> <?= htmlspecialchars($system_info['uptime']) ?></p>
    </div>
</body>
</html>
DASHBOARD_EOF

# Dashboard auth file
write_system_file /etc/vpsmanager/dashboard-auth.php << EOF
<?php
\$password_hash = '${DASHBOARD_PASSWORD_HASH}';
EOF
sudo chmod 600 /etc/vpsmanager/dashboard-auth.php

# Dashboard nginx config
write_system_file /etc/nginx/sites-available/dashboard << 'EOF'
server {
    listen 8080;
    server_name _;
    root /var/www/dashboard;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/dashboard /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# =============================================================================
# FIREWALL
# =============================================================================

log_info "Configuring firewall..."

sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw allow 8080/tcp    # Dashboard
sudo ufw allow 9100/tcp    # Node exporter (for observability)
sudo ufw --force enable

# =============================================================================
# FAIL2BAN
# =============================================================================

log_info "Configuring Fail2ban..."

write_system_file /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true

[nginx-http-auth]
enabled = true

[nginx-botsearch]
enabled = true
EOF

sudo systemctl restart fail2ban

# =============================================================================
# START SERVICES
# =============================================================================

log_info "Starting services..."

sudo systemctl daemon-reload

for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
sudo systemctl enable --now "php${PHP_VERSION}-fpm"
done

sudo systemctl enable --now nginx
sudo systemctl enable --now mariadb
sudo systemctl enable --now redis-server
sudo systemctl enable --now fail2ban

nginx -t && systemctl reload nginx

# =============================================================================
# VERIFICATION
# =============================================================================

log_info "Verifying installation..."

SERVICES=("nginx" "mariadb" "redis-server" "php8.2-fpm" "node_exporter" "fail2ban")
ALL_OK=true

for svc in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc"; then
        log_success "$svc is running"
    else
        log_error "$svc failed to start"
        ALL_OK=false
    fi
done

# =============================================================================
# SUMMARY
# =============================================================================

IP_ADDRESS=$(hostname -I | awk '{print $1}')

echo ""
echo "=========================================="
echo "  VPSManager Installed!"
echo "=========================================="
echo ""
echo "Services:"
echo "  - Dashboard:     http://${IP_ADDRESS}:8080"
echo "  - Node Exporter: http://${IP_ADDRESS}:9100"
echo ""
echo "Dashboard Credentials:"
echo "  - Password: ${DASHBOARD_PASSWORD}"
echo ""
echo "MySQL Credentials:"
echo "  - Root Password: ${MYSQL_ROOT_PASSWORD}"
echo ""
echo "PHP Versions: ${PHP_VERSIONS[*]}"
echo ""
echo "IMPORTANT: Save these credentials! They will not be shown again."
echo ""

# Save credentials
write_system_file /root/.vpsmanager-credentials << EOF
DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
EOF
sudo chmod 600 /root/.vpsmanager-credentials

if [[ -n "${OBSERVABILITY_IP}" ]]; then
    echo "Observability Integration:"
    echo "  - Prometheus: http://${OBSERVABILITY_IP}:9090"
    echo "  - Add this host to Prometheus targets with IP: ${IP_ADDRESS}"
fi

echo ""

if $ALL_OK; then
    log_success "Installation completed successfully!"
    exit 0
else
    log_error "Installation completed with failures - some services did not start"
    log_error "Check logs with: journalctl -xeu <service-name>"
    exit 1
fi
