#!/bin/bash
#===============================================================================
# Monitored Host Agent Setup Script
# Installs: node_exporter, nginx-prometheus-exporter, mysqld_exporter,
#           php-fpm_exporter, promtail
#
# This script is IDEMPOTENT - safe to run multiple times.
#
# Usage: ./setup-monitored-host.sh <OBSERVABILITY_VPS_IP> <LOKI_URL> <LOKI_USER> <LOKI_PASS> [--force]
# Example: ./setup-monitored-host.sh 10.0.0.5 https://mentat.arewel.com loki mypassword
#===============================================================================

set -euo pipefail

# Force mode flag
FORCE_MODE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Versions
NODE_EXPORTER_VERSION="1.7.0"
NGINX_EXPORTER_VERSION="1.0.0"
MYSQLD_EXPORTER_VERSION="0.15.1"
PHPFPM_EXPORTER_VERSION="2.2.0"
PROMTAIL_VERSION="2.9.3"

# Script arguments (parse --force from any position)
OBSERVABILITY_IP=""
LOKI_URL=""
LOKI_USER=""
LOKI_PASS=""

for arg in "$@"; do
    case "$arg" in
        --force|-f)
            FORCE_MODE=true
            ;;
        --help|-h)
            echo "Usage: $0 <OBSERVABILITY_VPS_IP> <LOKI_URL> <LOKI_USER> <LOKI_PASS> [--force]"
            echo ""
            echo "Arguments:"
            echo "  OBSERVABILITY_VPS_IP  - IP address of the observability server"
            echo "  LOKI_URL              - URL for Loki (e.g., https://mentat.arewel.com)"
            echo "  LOKI_USER             - Loki basic auth username"
            echo "  LOKI_PASS             - Loki basic auth password"
            echo ""
            echo "Options:"
            echo "  --force, -f           - Force reinstall everything from scratch"
            echo "  --help, -h            - Show this help message"
            exit 0
            ;;
        *)
            # Assign positional arguments
            if [[ -z "$OBSERVABILITY_IP" ]]; then
                OBSERVABILITY_IP="$arg"
            elif [[ -z "$LOKI_URL" ]]; then
                LOKI_URL="$arg"
            elif [[ -z "$LOKI_USER" ]]; then
                LOKI_USER="$arg"
            elif [[ -z "$LOKI_PASS" ]]; then
                LOKI_PASS="$arg"
            fi
            ;;
    esac
done

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_skip() {
    echo -e "${GREEN}[SKIP]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

#===============================================================================
# VERSION CHECK FUNCTIONS
#===============================================================================

check_binary_version() {
    local binary="$1"
    local expected_version="$2"
    local version_flag="${3:---version}"

    if [[ "$FORCE_MODE" == "true" ]]; then
        return 1
    fi

    if [[ ! -x "$binary" ]]; then
        return 1
    fi

    local current_version
    current_version=$("$binary" "$version_flag" 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    if [[ "$current_version" == "$expected_version" ]]; then
        return 0
    fi
    return 1
}

is_node_exporter_installed() {
    check_binary_version "/usr/local/bin/node_exporter" "$NODE_EXPORTER_VERSION"
}

is_nginx_exporter_installed() {
    check_binary_version "/usr/local/bin/nginx-prometheus-exporter" "$NGINX_EXPORTER_VERSION"
}

is_mysqld_exporter_installed() {
    check_binary_version "/usr/local/bin/mysqld_exporter" "$MYSQLD_EXPORTER_VERSION"
}

is_phpfpm_exporter_installed() {
    check_binary_version "/usr/local/bin/php-fpm_exporter" "$PHPFPM_EXPORTER_VERSION"
}

is_promtail_installed() {
    check_binary_version "/usr/local/bin/promtail" "$PROMTAIL_VERSION" "-version"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
    fi
}

check_args() {
    if [[ -z "$OBSERVABILITY_IP" ]]; then
        echo "Usage: $0 <OBSERVABILITY_VPS_IP> <LOKI_URL> <LOKI_USER> <LOKI_PASS>"
        echo ""
        echo "Arguments:"
        echo "  OBSERVABILITY_VPS_IP  - IP address of the observability server"
        echo "  LOKI_URL              - URL for Loki (e.g., https://mentat.arewel.com)"
        echo "  LOKI_USER             - Loki basic auth username"
        echo "  LOKI_PASS             - Loki basic auth password"
        exit 1
    fi
}

get_hostname() {
    HOSTNAME=$(hostname -f 2>/dev/null || hostname)
    log_info "Hostname: $HOSTNAME"
}

#===============================================================================
# SYSTEM PREPARATION
#===============================================================================

prepare_system() {
    log_info "Preparing system..."

    apt-get update -qq
    apt-get install -y -qq wget curl unzip ufw

    log_success "System packages verified/installed"
}

configure_firewall() {
    log_info "Configuring firewall..."

    # Force mode resets firewall
    if [[ "$FORCE_MODE" == "true" ]]; then
        log_info "Force mode: resetting firewall..."
        ufw --force reset
    fi

    # Allow SSH (idempotent - ufw handles duplicates)
    ufw allow 22/tcp

    # Allow Prometheus scraping from observability VPS
    # Check if rules already exist to avoid duplicate warnings
    if ! ufw status | grep -q "$OBSERVABILITY_IP.*9100"; then
        ufw allow from "$OBSERVABILITY_IP" to any port 9100 proto tcp  # node_exporter
    fi
    if ! ufw status | grep -q "$OBSERVABILITY_IP.*9113"; then
        ufw allow from "$OBSERVABILITY_IP" to any port 9113 proto tcp  # nginx_exporter
    fi
    if ! ufw status | grep -q "$OBSERVABILITY_IP.*9104"; then
        ufw allow from "$OBSERVABILITY_IP" to any port 9104 proto tcp  # mysqld_exporter
    fi
    if ! ufw status | grep -q "$OBSERVABILITY_IP.*9253"; then
        ufw allow from "$OBSERVABILITY_IP" to any port 9253 proto tcp  # phpfpm_exporter
    fi

    # Enable firewall if not already enabled
    ufw --force enable

    log_success "Firewall configured"
}

#===============================================================================
# NODE EXPORTER
#===============================================================================

install_node_exporter() {
    if is_node_exporter_installed; then
        log_skip "Node Exporter ${NODE_EXPORTER_VERSION} already installed"
        systemctl is-active --quiet node_exporter || systemctl start node_exporter
        return
    fi

    log_info "Installing Node Exporter ${NODE_EXPORTER_VERSION}..."

    systemctl stop node_exporter 2>/dev/null || true
    useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true

    cd /tmp
    wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

    cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
    chown node_exporter:node_exporter /usr/local/bin/node_exporter

    rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64" "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

    cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
    --collector.systemd \
    --collector.processes

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl restart node_exporter

    log_success "Node Exporter installed (port 9100)"
}

#===============================================================================
# NGINX EXPORTER
#===============================================================================

install_nginx_exporter() {
    # Check if nginx is installed
    if ! command -v nginx &> /dev/null; then
        log_warn "Nginx not found, skipping nginx_exporter"
        return
    fi

    if is_nginx_exporter_installed; then
        log_skip "Nginx Exporter ${NGINX_EXPORTER_VERSION} already installed"
        systemctl is-active --quiet nginx_exporter || systemctl start nginx_exporter
        return
    fi

    log_info "Installing Nginx Prometheus Exporter ${NGINX_EXPORTER_VERSION}..."

    systemctl stop nginx_exporter 2>/dev/null || true
    useradd --no-create-home --shell /bin/false nginx_exporter 2>/dev/null || true

    cd /tmp
    wget -q "https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${NGINX_EXPORTER_VERSION}/nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz"
    tar xzf "nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz"

    cp nginx-prometheus-exporter /usr/local/bin/
    chown nginx_exporter:nginx_exporter /usr/local/bin/nginx-prometheus-exporter

    rm -rf nginx-prometheus-exporter "nginx-prometheus-exporter_${NGINX_EXPORTER_VERSION}_linux_amd64.tar.gz"

    # Enable nginx stub_status if not already enabled
    if ! grep -q "stub_status" /etc/nginx/sites-enabled/* 2>/dev/null && \
       ! grep -q "stub_status" /etc/nginx/conf.d/* 2>/dev/null; then
        log_info "Enabling Nginx stub_status..."
        cat > /etc/nginx/conf.d/stub_status.conf << 'EOF'
server {
    listen 127.0.0.1:8080;
    server_name localhost;

    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
EOF
        nginx -t && systemctl reload nginx
    fi

    cat > /etc/systemd/system/nginx_exporter.service << 'EOF'
[Unit]
Description=Nginx Prometheus Exporter
Wants=network-online.target
After=network-online.target nginx.service

[Service]
User=nginx_exporter
Group=nginx_exporter
Type=simple
ExecStart=/usr/local/bin/nginx-prometheus-exporter \
    --nginx.scrape-uri=http://127.0.0.1:8080/nginx_status

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nginx_exporter
    systemctl restart nginx_exporter

    log_success "Nginx Exporter installed (port 9113)"
}

#===============================================================================
# MYSQL EXPORTER
#===============================================================================

install_mysqld_exporter() {
    # Check if MySQL/MariaDB is installed
    if ! command -v mysql &> /dev/null && ! command -v mariadb &> /dev/null; then
        log_warn "MySQL/MariaDB not found, skipping mysqld_exporter"
        return
    fi

    if is_mysqld_exporter_installed; then
        log_skip "MySQL Exporter ${MYSQLD_EXPORTER_VERSION} already installed"
        return
    fi

    log_info "Installing MySQL Exporter ${MYSQLD_EXPORTER_VERSION}..."

    systemctl stop mysqld_exporter 2>/dev/null || true
    useradd --no-create-home --shell /bin/false mysqld_exporter 2>/dev/null || true

    cd /tmp
    wget -q "https://github.com/prometheus/mysqld_exporter/releases/download/v${MYSQLD_EXPORTER_VERSION}/mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-amd64.tar.gz"
    tar xzf "mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-amd64.tar.gz"

    cp "mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-amd64/mysqld_exporter" /usr/local/bin/
    chown mysqld_exporter:mysqld_exporter /usr/local/bin/mysqld_exporter

    rm -rf "mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-amd64" "mysqld_exporter-${MYSQLD_EXPORTER_VERSION}.linux-amd64.tar.gz"

    # Create credentials file only if it doesn't exist
    mkdir -p /etc/mysqld_exporter
    if [[ ! -f /etc/mysqld_exporter/.my.cnf ]]; then
        cat > /etc/mysqld_exporter/.my.cnf << 'EOF'
[client]
user=exporter
password=CHANGE_ME_EXPORTER_PASSWORD
host=localhost
EOF
        chmod 600 /etc/mysqld_exporter/.my.cnf
        chown mysqld_exporter:mysqld_exporter /etc/mysqld_exporter/.my.cnf
    fi

    cat > /etc/systemd/system/mysqld_exporter.service << 'EOF'
[Unit]
Description=MySQL Exporter
Wants=network-online.target
After=network-online.target mysql.service mariadb.service

[Service]
User=mysqld_exporter
Group=mysqld_exporter
Type=simple
ExecStart=/usr/local/bin/mysqld_exporter \
    --config.my-cnf=/etc/mysqld_exporter/.my.cnf \
    --collect.global_status \
    --collect.info_schema.innodb_metrics \
    --collect.auto_increment.columns \
    --collect.info_schema.processlist \
    --collect.binlog_size \
    --collect.info_schema.tablestats \
    --collect.global_variables \
    --collect.info_schema.query_response_time \
    --collect.info_schema.userstats \
    --collect.info_schema.tables \
    --collect.perf_schema.tablelocks \
    --collect.perf_schema.file_events \
    --collect.perf_schema.eventswaits \
    --collect.perf_schema.indexiowaits \
    --collect.perf_schema.tableiowaits

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable mysqld_exporter

    log_warn "MySQL Exporter installed but NOT started"
    log_warn "Please create the MySQL user and update /etc/mysqld_exporter/.my.cnf"
    log_warn "Then run: systemctl start mysqld_exporter"

    echo ""
    echo "MySQL commands to run as root:"
    echo "  CREATE USER IF NOT EXISTS 'exporter'@'localhost' IDENTIFIED BY 'YOUR_PASSWORD';"
    echo "  GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';"
    echo "  FLUSH PRIVILEGES;"
    echo ""
}

#===============================================================================
# PHP-FPM EXPORTER
#===============================================================================

install_phpfpm_exporter() {
    # Check if PHP-FPM is installed
    if ! systemctl list-units --type=service | grep -q "php.*fpm"; then
        log_warn "PHP-FPM not found, skipping phpfpm_exporter"
        return
    fi

    if is_phpfpm_exporter_installed; then
        log_skip "PHP-FPM Exporter ${PHPFPM_EXPORTER_VERSION} already installed"
        systemctl is-active --quiet phpfpm_exporter || systemctl start phpfpm_exporter
        return
    fi

    log_info "Installing PHP-FPM Exporter ${PHPFPM_EXPORTER_VERSION}..."

    systemctl stop phpfpm_exporter 2>/dev/null || true
    useradd --no-create-home --shell /bin/false phpfpm_exporter 2>/dev/null || true

    cd /tmp
    wget -q "https://github.com/hipages/php-fpm_exporter/releases/download/v${PHPFPM_EXPORTER_VERSION}/php-fpm_exporter_${PHPFPM_EXPORTER_VERSION}_linux_amd64"
    mv "php-fpm_exporter_${PHPFPM_EXPORTER_VERSION}_linux_amd64" /usr/local/bin/php-fpm_exporter
    chmod +x /usr/local/bin/php-fpm_exporter
    chown phpfpm_exporter:phpfpm_exporter /usr/local/bin/php-fpm_exporter

    # Find PHP-FPM socket or configure status page
    PHP_FPM_SOCKET=""
    PHP_FPM_STATUS=""

    # Try to find the socket
    for sock in /run/php/php*-fpm.sock /var/run/php*-fpm.sock /run/php-fpm/*.sock; do
        if [[ -S "$sock" ]]; then
            PHP_FPM_SOCKET="$sock"
            break
        fi
    done

    if [[ -n "$PHP_FPM_SOCKET" ]]; then
        log_info "Found PHP-FPM socket: $PHP_FPM_SOCKET"
        # Enable status page in PHP-FPM pool
        PHP_FPM_CONF=$(find /etc/php -name "www.conf" 2>/dev/null | head -1)
        if [[ -n "$PHP_FPM_CONF" ]]; then
            if ! grep -q "^pm.status_path" "$PHP_FPM_CONF"; then
                log_info "Enabling PHP-FPM status page..."
                echo "pm.status_path = /status" >> "$PHP_FPM_CONF"
                systemctl restart "$(systemctl list-units --type=service | grep "php.*fpm" | awk '{print $1}')"
            fi
        fi
        PHP_FPM_STATUS="unix://${PHP_FPM_SOCKET};/status"
    else
        # Try TCP
        PHP_FPM_STATUS="tcp://127.0.0.1:9000/status"
    fi

    cat > /etc/systemd/system/phpfpm_exporter.service << EOF
[Unit]
Description=PHP-FPM Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=phpfpm_exporter
Group=phpfpm_exporter
Type=simple
ExecStart=/usr/local/bin/php-fpm_exporter server \\
    --phpfpm.scrape-uri="${PHP_FPM_STATUS}" \\
    --web.listen-address=":9253"

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Add phpfpm_exporter to www-data group to access socket
    usermod -a -G www-data phpfpm_exporter 2>/dev/null || true

    systemctl daemon-reload
    systemctl enable phpfpm_exporter
    systemctl restart phpfpm_exporter

    log_success "PHP-FPM Exporter installed (port 9253)"
}

#===============================================================================
# PROMTAIL (Log Shipper)
#===============================================================================

install_promtail() {
    if [[ -z "$LOKI_URL" ]]; then
        log_warn "LOKI_URL not provided, skipping Promtail"
        return
    fi

    if is_promtail_installed; then
        log_skip "Promtail ${PROMTAIL_VERSION} already installed"
        systemctl is-active --quiet promtail || systemctl start promtail
        return
    fi

    log_info "Installing Promtail ${PROMTAIL_VERSION}..."

    systemctl stop promtail 2>/dev/null || true
    useradd --no-create-home --shell /bin/false promtail 2>/dev/null || true

    mkdir -p /etc/promtail
    mkdir -p /var/lib/promtail

    cd /tmp
    wget -q "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"
    unzip -o promtail-linux-amd64.zip
    chmod +x promtail-linux-amd64
    mv promtail-linux-amd64 /usr/local/bin/promtail

    rm -f promtail-linux-amd64.zip

    # Create Promtail configuration
    cat > /etc/promtail/promtail.yaml << EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: ${LOKI_URL}/loki/api/v1/push
    basic_auth:
      username: ${LOKI_USER}
      password: ${LOKI_PASS}

scrape_configs:
  # Nginx access logs
  - job_name: nginx_access
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx_access
          host: ${HOSTNAME}
          __path__: /var/log/nginx/access.log

  # Nginx error logs
  - job_name: nginx_error
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx_error
          host: ${HOSTNAME}
          __path__: /var/log/nginx/error.log

  # PHP error logs
  - job_name: php_error
    static_configs:
      - targets:
          - localhost
        labels:
          job: php_error
          host: ${HOSTNAME}
          __path__: /var/log/php*-fpm.log

  # MySQL slow query log
  - job_name: mysql_slow
    static_configs:
      - targets:
          - localhost
        labels:
          job: mysql_slow
          host: ${HOSTNAME}
          __path__: /var/log/mysql/mysql-slow.log
    pipeline_stages:
      - multiline:
          firstline: '^# Time:'
          max_wait_time: 3s

  # Syslog
  - job_name: syslog
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          host: ${HOSTNAME}
          __path__: /var/log/syslog

  # Auth log
  - job_name: auth
    static_configs:
      - targets:
          - localhost
        labels:
          job: auth
          host: ${HOSTNAME}
          __path__: /var/log/auth.log

  # WordPress debug logs (common paths)
  - job_name: wordpress
    static_configs:
      - targets:
          - localhost
        labels:
          job: wordpress
          host: ${HOSTNAME}
          __path__: /var/www/*/wp-content/debug.log
EOF

    # Add promtail to adm group to read logs
    usermod -a -G adm promtail
    usermod -a -G www-data promtail 2>/dev/null || true

    chown -R promtail:promtail /etc/promtail /var/lib/promtail

    cat > /etc/systemd/system/promtail.service << 'EOF'
[Unit]
Description=Promtail
Wants=network-online.target
After=network-online.target

[Service]
User=promtail
Group=promtail
Type=simple
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail.yaml

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable promtail
    systemctl restart promtail

    log_success "Promtail installed and configured"
}

#===============================================================================
# SUMMARY
#===============================================================================

print_summary() {
    echo ""
    echo "=========================================="
    echo -e "${GREEN}Monitored Host Setup Complete!${NC}"
    echo "=========================================="
    echo ""
    echo "Host: $HOSTNAME"
    echo ""
    echo "Installed exporters:"

    if systemctl is-active --quiet node_exporter; then
        echo -e "  ${GREEN}✓${NC} Node Exporter      (port 9100)"
    fi

    if systemctl is-active --quiet nginx_exporter; then
        echo -e "  ${GREEN}✓${NC} Nginx Exporter     (port 9113)"
    fi

    if systemctl is-enabled --quiet mysqld_exporter 2>/dev/null; then
        if systemctl is-active --quiet mysqld_exporter; then
            echo -e "  ${GREEN}✓${NC} MySQL Exporter     (port 9104)"
        else
            echo -e "  ${YELLOW}!${NC} MySQL Exporter     (port 9104) - needs configuration"
        fi
    fi

    if systemctl is-active --quiet phpfpm_exporter; then
        echo -e "  ${GREEN}✓${NC} PHP-FPM Exporter   (port 9253)"
    fi

    if systemctl is-active --quiet promtail; then
        echo -e "  ${GREEN}✓${NC} Promtail           (log shipping)"
    fi

    echo ""
    echo "Firewall:"
    echo "  Allowed connections from: $OBSERVABILITY_IP"
    echo ""
    echo "Next steps:"
    echo "1. Add this host to the observability server's global.yaml"
    echo "2. Reload Prometheus on the observability server"
    echo ""

    if systemctl is-enabled --quiet mysqld_exporter 2>/dev/null && ! systemctl is-active --quiet mysqld_exporter; then
        echo -e "${YELLOW}MySQL Exporter requires additional setup:${NC}"
        echo "1. Create MySQL user for exporter"
        echo "2. Update /etc/mysqld_exporter/.my.cnf with credentials"
        echo "3. Run: systemctl start mysqld_exporter"
        echo ""
    fi
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    echo ""
    echo "=========================================="
    echo "Monitored Host Agent Setup"
    echo "=========================================="
    if [[ "$FORCE_MODE" == "true" ]]; then
        echo -e "${YELLOW}>>> FORCE MODE: Reinstalling everything from scratch <<<${NC}"
    fi
    echo ""

    check_root
    check_args
    get_hostname
    prepare_system
    configure_firewall

    install_node_exporter
    install_nginx_exporter
    install_mysqld_exporter
    install_phpfpm_exporter
    install_promtail

    print_summary
}

main "$@"
