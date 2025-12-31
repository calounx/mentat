#!/bin/bash
#
# CHOM VPSManager Setup Script - OPTIMIZED VERSION
# For Debian 12 (Bookworm) and Debian 13 (Trixie)
#
# Installs: Nginx, PHP-FPM, MariaDB, Redis, VPSManager
#

set -euo pipefail

# =============================================================================
# LIBRARY IMPORT
# =============================================================================

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_PATH="${SCRIPT_DIR}/../lib/deploy-common.sh"

if [[ ! -f "$LIB_PATH" ]]; then
    echo "ERROR: Cannot find shared library at: $LIB_PATH"
    exit 1
fi

# shellcheck source=../lib/deploy-common.sh
source "$LIB_PATH"

# Initialize deployment logging
init_deployment_log

# =============================================================================
# CONFIGURATION
# =============================================================================

# Domain configuration (can be overridden via environment variables)
DOMAIN="${DOMAIN:-landsraad.arewel.com}"
SSL_EMAIL="${SSL_EMAIL:-admin@arewel.com}"

OBSERVABILITY_IP="${OBSERVABILITY_IP:-}"
VPSMANAGER_REPO="https://github.com/calounx/vpsmanager.git"

# Versions - Dynamic and OS Default
PHP_VERSIONS=("8.2" "8.3" "8.4")  # 8.3 is latest stable (recommended), 8.4 is newest, from packages.sury.org
MARIADB_VERSION="10.11"           # From Debian default repos (same in Debian 12/13)
REDIS_VERSION="7"                 # From Debian default repos

# Node Exporter - dynamically fetch latest from GitHub (with fallback)
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-$(get_github_version "Node Exporter" "prometheus/node_exporter" "1.10.2")}"

# Paths
VPSMANAGER_DIR="/opt/vpsmanager"
CONFIG_DIR="/etc/vpsmanager"
LOG_DIR="/var/log/vpsmanager"
WWW_DIR="/var/www"

# =============================================================================
# FULL CLEANUP BEFORE INSTALLATION
# =============================================================================

run_full_cleanup() {
    log_info "=========================================="
    log_info "  RUNNING FULL CLEANUP"
    log_info "=========================================="

    # List of all VPSManager services
    local services=("nginx" "php8.2-fpm" "php8.3-fpm" "php8.4-fpm" "mariadb" "redis-server" "node_exporter" "fail2ban")

    # Stop all services (except fail2ban which we'll restart)
    log_info "Stopping VPSManager services..."
    for service in "${services[@]}"; do
        if [[ "$service" == "fail2ban" ]]; then
            continue  # Don't stop fail2ban during cleanup
        fi
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            log_info "Stopping $service..."
            sudo systemctl stop "$service" 2>/dev/null || log_warn "Could not stop $service gracefully"
        fi
    done

    # Wait a moment for graceful shutdown
    sleep 3

    # Kill any remaining processes
    log_info "Killing any remaining VPSManager processes..."
    local process_patterns=("nginx" "php-fpm" "node_exporter")
    for pattern in "${process_patterns[@]}"; do
        local pids=$(pgrep -f "$pattern" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            log_warn "Found running $pattern processes: $pids"
            echo "$pids" | xargs -r sudo kill -15 2>/dev/null || true
        fi
    done

    sleep 2

    # Force kill any stubborn processes
    for pattern in "${process_patterns[@]}"; do
        local pids=$(pgrep -f "$pattern" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            log_warn "Force killing stubborn $pattern processes: $pids"
            echo "$pids" | xargs -r sudo kill -9 2>/dev/null || true
        fi
    done

    # Clean up port conflicts
    cleanup_port_conflicts 80 443 8080 9100 3306 6379

    # Remove old binaries if they exist and are locked
    log_info "Ensuring old binaries can be replaced..."
    local binaries=(
        "/usr/local/bin/node_exporter"
    )

    for binary in "${binaries[@]}"; do
        if [[ -f "$binary" ]]; then
            # Try to remove any lingering locks
            sudo fuser -k "$binary" 2>/dev/null || true
        fi
    done

    # Remove old MariaDB repository files (Debian 13 not supported by MariaDB official repos)
    log_info "Removing old MariaDB repository configuration..."
    sudo rm -f /etc/apt/sources.list.d/mariadb.list
    sudo rm -f /etc/apt/trusted.gpg.d/mariadb.gpg

    # Clean up any other potentially problematic repo files from previous runs
    sudo rm -f /etc/apt/sources.list.d/php.list 2>/dev/null || true

    log_success "Full cleanup completed!"
    log_info "=========================================="
    sleep 2
}

# =============================================================================
# PREREQUISITES
# =============================================================================

# Check sudo access using shared library
check_sudo_access

# Detect and validate Debian OS using shared library
detect_debian_os

log_info "Starting VPSManager installation..."

# Display versions
log_info "Component versions to be installed:"
log_info "  - PHP: ${PHP_VERSIONS[*]}"
log_info "  - MariaDB: ${MARIADB_VERSION} (from Debian ${DEBIAN_VERSION} repos)"
log_info "  - Redis: ${REDIS_VERSION}.x (from Debian ${DEBIAN_VERSION} repos)"
log_info "  - Node Exporter: ${NODE_EXPORTER_VERSION}"
log_info "  - Nginx: Latest from Debian ${DEBIAN_VERSION} repos"

# Run full cleanup BEFORE any installation to ensure idempotency
run_full_cleanup

# =============================================================================
# SYSTEM SETUP - OPTIMIZED WITH SINGLE APT-GET UPDATE
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
    ncdu \
    lsof \
    psmisc

# Create directories
sudo mkdir -p "$VPSMANAGER_DIR"
sudo mkdir -p "$CONFIG_DIR"
sudo mkdir -p "$LOG_DIR"
sudo mkdir -p "$WWW_DIR"

# =============================================================================
# PHP REPOSITORY SETUP - BEFORE APT-GET UPDATE (OPTIMIZATION #2)
# =============================================================================

log_info "Setting up PHP repository..."

# Add PHP repository
sudo wget -qO /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list > /dev/null

# SINGLE apt-get update after repository setup (instead of TWO updates)
log_info "Updating package index with new repository..."
sudo apt-get update -qq

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
# PHP - BATCH INSTALLATION (OPTIMIZATION #3)
# =============================================================================

log_info "Installing PHP versions: ${PHP_VERSIONS[*]}..."

# Build package list for ALL PHP versions
PHP_PACKAGES=()
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    PHP_PACKAGES+=(
        "php${PHP_VERSION}-fpm"
        "php${PHP_VERSION}-cli"
        "php${PHP_VERSION}-common"
        "php${PHP_VERSION}-mysql"
        "php${PHP_VERSION}-xml"
        "php${PHP_VERSION}-mbstring"
        "php${PHP_VERSION}-curl"
        "php${PHP_VERSION}-zip"
        "php${PHP_VERSION}-gd"
        "php${PHP_VERSION}-intl"
        "php${PHP_VERSION}-bcmath"
        "php${PHP_VERSION}-redis"
        "php${PHP_VERSION}-imagick"
        "php${PHP_VERSION}-opcache"
    )
done

# SINGLE apt-get install for ALL PHP versions (instead of loop)
log_info "Installing ${#PHP_PACKAGES[@]} PHP packages in batch..."
sudo apt-get install -y -qq "${PHP_PACKAGES[@]}"

log_success "All PHP versions installed successfully"

# =============================================================================
# PHP CONFIGURATION - PARALLEL WRITING (OPTIMIZATION #6)
# =============================================================================

log_info "Writing PHP configuration files in parallel..."

# PHP optimization for WordPress - write all configs in parallel
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    (
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
        log_info "PHP ${PHP_VERSION} configuration written"
    ) &
done

# Wait for all background PHP config writes to complete
wait

log_success "All PHP configurations written"

# =============================================================================
# MARIADB
# =============================================================================

log_info "Installing MariaDB..."

# Use Debian default repositories (works on both Debian 12 and 13)
# Debian 12 (Bookworm): MariaDB 10.11
# Debian 13 (Trixie): MariaDB 10.11
# Note: Third-party MariaDB repos may not support latest Debian versions yet
sudo apt-get install -y -qq mariadb-server mariadb-client

# =============================================================================
# MARIADB OPTIMIZATION - WRITE CONFIG BEFORE FIRST START (OPTIMIZATION #5)
# =============================================================================

log_info "Writing MariaDB optimization config..."

# MariaDB optimization and security hardening - write BEFORE first start
write_system_file /etc/mysql/mariadb.conf.d/99-optimization.cnf << 'EOF'
[mysqld]
# Security - Bind to localhost only (not exposed to network)
bind-address = 127.0.0.1

# Performance optimization
innodb_buffer_pool_size = 256M
innodb_log_file_size = 64M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
max_connections = 200
query_cache_type = 1
query_cache_size = 32M
query_cache_limit = 2M

# Additional security hardening
local-infile = 0
skip-symbolic-links = 1
EOF

log_success "MariaDB configuration written (optimization applied before first start)"

# =============================================================================
# MARIADB SECURITY SETUP
# =============================================================================

# Check if MariaDB is already secured (idempotency check)
if ! sudo mysql -u root -e "SELECT 1" &>/dev/null; then
    # MariaDB already secured, load existing password
    if [[ -f /root/.vpsmanager-credentials ]]; then
        source /root/.vpsmanager-credentials
        log_info "MariaDB already secured, using existing credentials"
        MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"

        if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
            log_error "MariaDB secured but password not found in credentials file"
            log_error "Manual intervention required. Reset MariaDB root password first."
            exit 1
        fi
    else
        # Credentials file missing - this can happen if previous installation was incomplete
        # We need to reset MariaDB root password
        log_warn "MariaDB secured but credentials file missing at /root/.vpsmanager-credentials"
        log_warn "This usually means a previous installation was incomplete"
        log_info "Resetting MariaDB root password..."

        # Stop MariaDB
        sudo systemctl stop mariadb || true

        # Start MariaDB in skip-grant-tables mode to reset password
        sudo systemctl set-environment MYSQLD_OPTS="--skip-grant-tables --skip-networking"
        sudo systemctl start mariadb
        sleep 3

        # Generate new password using shared library function
        MYSQL_ROOT_PASSWORD=$(generate_password 24)

        # Reset password
        sudo mysql -u root << EOF
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF

        # Stop and restart MariaDB normally
        sudo systemctl stop mariadb
        sudo systemctl unset-environment MYSQLD_OPTS
        sudo systemctl start mariadb
        sleep 2

        log_success "MariaDB root password reset successfully"

        # Now run secure installation queries with the new password
        MYSQL_CNF_FILE=$(mktemp)
        sudo chmod 600 "$MYSQL_CNF_FILE"

        cat > "$MYSQL_CNF_FILE" << EOF
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

        shred -u "$MYSQL_CNF_FILE" 2>/dev/null || rm -f "$MYSQL_CNF_FILE"
        log_success "MariaDB secure installation completed"
    fi
else
    # First run - MariaDB not secured yet
    log_info "Securing MariaDB for the first time..."

    # Generate root password using shared library function
    MYSQL_ROOT_PASSWORD=$(generate_password 24)

    # Secure installation - Set root password
    sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"

    # Use .my.cnf to avoid password in process list
    # Create secure temporary file with proper permissions BEFORE writing
    MYSQL_CNF_FILE=$(mktemp)
    sudo chmod 600 "$MYSQL_CNF_FILE"  # Set permissions IMMEDIATELY

    # Write credentials to temp file
    cat > "$MYSQL_CNF_FILE" << EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOF

    # Run secure installation queries
    sudo mysql --defaults-extra-file="$MYSQL_CNF_FILE" << 'SQL'
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL

    # Securely clean up temporary file
    shred -u "$MYSQL_CNF_FILE" 2>/dev/null || rm -f "$MYSQL_CNF_FILE"

    log_success "MariaDB secured successfully"
fi

log_success "MariaDB configured: localhost-only binding, production-ready"

# =============================================================================
# REDIS - FIX SUDO BUG (OPTIMIZATION #4)
# =============================================================================

log_info "Installing Redis..."

sudo apt-get install -y -qq redis-server

# Redis optimization - FIX: Add sudo prefix to sed commands
log_info "Configuring Redis memory limits..."
sudo sed -i 's/^# maxmemory .*/maxmemory 128mb/' /etc/redis/redis.conf
sudo sed -i 's/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf

log_success "Redis installed and configured"

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
    - "8.3"
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

# Stop node_exporter service before replacing binary (using shared library function)
stop_and_verify_service "node_exporter" "/usr/local/bin/node_exporter"

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
sudo systemctl enable node_exporter

# =============================================================================
# VPSMANAGER DASHBOARD
# =============================================================================

log_info "Setting up VPSManager Dashboard..."

# Create dashboard directory
sudo mkdir -p /var/www/dashboard

# Generate dashboard credentials using shared library function
DASHBOARD_PASSWORD=$(generate_password 16)

# Hash password without exposing in process list
# Use a temporary file to pass password to PHP securely
PASS_TEMP=$(mktemp)
chmod 600 "$PASS_TEMP"
echo -n "${DASHBOARD_PASSWORD}" > "$PASS_TEMP"
DASHBOARD_PASSWORD_HASH=$(php -r "echo password_hash(file_get_contents('${PASS_TEMP}'), PASSWORD_BCRYPT);")
shred -u "$PASS_TEMP" 2>/dev/null || rm -f "$PASS_TEMP"

write_system_file /var/www/dashboard/index.php << 'DASHBOARD_EOF'
<?php
// VPSManager Dashboard with Security Hardening
session_start();

$auth_file = '/etc/vpsmanager/dashboard-auth.php';
if (file_exists($auth_file)) {
    require $auth_file;
}

// Rate limiting configuration
// Use secure directory instead of /tmp (world-readable)
$attempts_dir = '/var/lib/vpsmanager/sessions';
if (!is_dir($attempts_dir)) {
    mkdir($attempts_dir, 0700, true);
}
$attempts_file = $attempts_dir . '/login_attempts_' . md5($_SERVER['REMOTE_ADDR']);
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
log_info "Configuring nginx for ${DOMAIN}..."

write_system_file /etc/nginx/sites-available/dashboard << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    root /var/www/dashboard;
    index index.php;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    # Deny access to sensitive files
    location ~ /\.ht {
        deny all;
    }

    location ~ /\.git {
        deny all;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/dashboard /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
sudo nginx -t

# =============================================================================
# FIREWALL
# =============================================================================

log_info "Configuring firewall..."

configure_firewall_base  # Use shared library function for base rules

# Add VPSManager-specific ports
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

# =============================================================================
# PRE-START PORT VALIDATION (OPTIMIZATION #8)
# =============================================================================

log_info "Validating ports are available before starting services..."

# Use shared library function for port validation
validate_ports_available 80 443 8080 9100 3306 6379

# =============================================================================
# START SERVICES - OPTIMIZED WITH BATCH ENABLE AND PARALLEL START (OPTIMIZATION #8)
# =============================================================================

log_info "Starting services..."

sudo systemctl daemon-reload

# Batch enable services
log_info "Enabling services..."
ENABLE_SERVICES=("nginx" "mariadb" "redis-server" "node_exporter" "fail2ban")
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    ENABLE_SERVICES+=("php${PHP_VERSION}-fpm")
done

# Enable all services in batch
for service in "${ENABLE_SERVICES[@]}"; do
    sudo systemctl enable "$service" &
done
wait

log_success "All services enabled"

# Start PHP-FPM services first (parallel start)
log_info "Starting PHP-FPM services in parallel..."
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    sudo systemctl start "php${PHP_VERSION}-fpm" &
done

# =============================================================================
# PARALLEL PHP SOCKET WAITING (OPTIMIZATION #7)
# =============================================================================

log_info "Waiting for PHP-FPM sockets to be ready..."

# Start background jobs to wait for each PHP socket in parallel
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    (
        SOCKET_PATH="/run/php/php${PHP_VERSION}-fpm.sock"
        timeout 30 bash -c "until [ -S '${SOCKET_PATH}' ]; do sleep 0.5; done" || {
            log_error "Timeout waiting for ${SOCKET_PATH}"
            exit 1
        }
        log_success "PHP ${PHP_VERSION} FPM socket ready"
    ) &
done

# Wait for ALL PHP socket checks to complete
wait

log_success "All PHP-FPM sockets ready"

# Start remaining services (can start in parallel now that PHP is ready)
log_info "Starting remaining services..."
sudo systemctl start nginx &
sudo systemctl start mariadb &
sudo systemctl start redis-server &
sudo systemctl start node_exporter &
sudo systemctl start fail2ban &

# Wait for all service starts to complete
wait

log_success "All services started"

# Final nginx configuration test and reload
log_info "Testing Nginx configuration..."
nginx -t && systemctl reload nginx

# =============================================================================
# VERIFICATION (OPTIMIZATION #9 - USE SHARED LIBRARY)
# =============================================================================

log_info "Verifying installation..."

# Build list of services to verify
VERIFY_SERVICES=("nginx" "mariadb" "redis-server" "node_exporter" "fail2ban")
for PHP_VERSION in "${PHP_VERSIONS[@]}"; do
    VERIFY_SERVICES+=("php${PHP_VERSION}-fpm")
done

# Use shared library function for verification
if verify_services "${VERIFY_SERVICES[@]}"; then
    ALL_OK=true
else
    ALL_OK=false
fi

# =============================================================================
# SSL/HTTPS CONFIGURATION
# =============================================================================

log_info "=========================================="
log_info "  SSL/HTTPS CONFIGURATION"
log_info "=========================================="

# Check if domain is configured and accessible
if [[ -n "$DOMAIN" ]] && [[ "$DOMAIN" != "localhost" ]] && [[ "$DOMAIN" != "_" ]]; then
    log_info "Domain configured: ${DOMAIN}"
    log_info "SSL Email: ${SSL_EMAIL}"

    # Check domain DNS resolution
    if check_domain_accessible "$DOMAIN"; then
        log_info "Domain DNS is correctly configured"
        log_info "Setting up Let's Encrypt SSL certificate..."

        # Setup SSL with auto-renewal
        if setup_ssl_with_renewal "$DOMAIN" "$SSL_EMAIL"; then
            log_success "SSL/HTTPS configured successfully!"
            log_success "VPSManager is now accessible at: https://${DOMAIN}"
            SSL_CONFIGURED=true
        else
            log_warn "SSL setup failed or was skipped"
            log_warn "VPSManager is accessible via HTTP at: http://${DOMAIN}"
            log_warn "You can set up SSL later with: sudo certbot --nginx -d ${DOMAIN}"
            SSL_CONFIGURED=false
        fi
    else
        log_warn "Domain ${DOMAIN} is not accessible or DNS not configured"
        log_warn "Skipping SSL setup - you can configure it later with certbot"
        log_warn "VPSManager is accessible via HTTP at: http://$(get_ip_address)"
        SSL_CONFIGURED=false
    fi
else
    log_warn "No domain configured (DOMAIN=${DOMAIN})"
    log_warn "Skipping SSL setup - services accessible via IP address only"
    log_warn "To enable SSL, set DOMAIN and SSL_EMAIL environment variables and re-run"
    SSL_CONFIGURED=false
fi

log_info "=========================================="

# =============================================================================
# SUMMARY
# =============================================================================

IP_ADDRESS=$(get_ip_address)  # Use shared library function

echo ""
echo "=========================================="
echo "  VPSManager Installed!"
echo "=========================================="
echo ""

# Display URLs based on SSL configuration
if [[ "$SSL_CONFIGURED" == "true" ]]; then
    echo "Access URLs (HTTPS - SSL Configured):"
    echo "  - VPSManager:    https://${DOMAIN}"
    echo "  - Node Exporter: http://${IP_ADDRESS}:9100 (internal)"
else
    echo "Access URLs (HTTP - SSL Not Configured):"
    if [[ -n "$DOMAIN" ]] && [[ "$DOMAIN" != "_" ]]; then
        echo "  - VPSManager:    http://${DOMAIN} or http://${IP_ADDRESS}"
    else
        echo "  - VPSManager:    http://${IP_ADDRESS}"
    fi
    echo "  - Node Exporter: http://${IP_ADDRESS}:9100"
fi

echo ""
echo "Dashboard Credentials:"
echo "  - Password: ${DASHBOARD_PASSWORD}"
echo ""
echo "MySQL Credentials:"
echo "  - Root Password: ${MYSQL_ROOT_PASSWORD}"
echo ""
echo "PHP Versions: ${PHP_VERSIONS[*]}"
echo ""
echo "Credentials saved: /root/.vpsmanager-credentials"
if [[ "$SSL_CONFIGURED" == "true" ]]; then
    echo "SSL Status: ✓ Enabled (Auto-renewal configured)"
else
    echo "SSL Status: ✗ Not configured"
    if [[ -n "$DOMAIN" ]] && [[ "$DOMAIN" != "_" ]]; then
        echo "To enable SSL: sudo certbot --nginx -d ${DOMAIN} --email ${SSL_EMAIL}"
    fi
fi
echo ""

# Save credentials
write_system_file /root/.vpsmanager-credentials << EOF
DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
DOMAIN=${DOMAIN}
SSL_EMAIL=${SSL_EMAIL}
SSL_CONFIGURED=${SSL_CONFIGURED}
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
    if [[ "$SSL_CONFIGURED" == "true" ]]; then
        log_success "System is production-ready with HTTPS enabled!"
    else
        log_warn "System is functional but SSL is not configured"
    fi

    # Display deployment log location
    if [[ -f "$DEPLOYMENT_LOG_FILE" ]]; then
        echo ""
        echo "Deployment log saved: $DEPLOYMENT_LOG_FILE"
        echo "View with: cat $DEPLOYMENT_LOG_FILE"
    fi

    exit 0
else
    log_error "Installation completed with failures - some services did not start"
    log_error "Check logs with: journalctl -xeu <service-name>"

    # Display deployment log location even on failure
    if [[ -f "$DEPLOYMENT_LOG_FILE" ]]; then
        echo ""
        echo "Deployment log saved: $DEPLOYMENT_LOG_FILE"
    fi

    exit 1
fi
