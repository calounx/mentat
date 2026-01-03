#!/bin/bash

###############################################################################
# Native Promtail Installation for Debian 13
# NO DOCKER - Direct binary with systemd service
###############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
PROMTAIL_VERSION="2.9.4"
PROMTAIL_USER="promtail"
PROMTAIL_GROUP="promtail"
PROMTAIL_CONFIG_DIR="/etc/promtail"
PROMTAIL_DATA_DIR="/var/lib/promtail"
PROMTAIL_LOG_DIR="/var/log/promtail"
PROMTAIL_PORT=9080
LOKI_URL="http://mentat.arewel.com:3100"
DOWNLOAD_URL="https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

install_dependencies() {
    log_info "Installing dependencies..."
    apt-get update -qq
    apt-get install -y -qq wget unzip curl
    log_success "Dependencies installed"
}

create_user() {
    log_info "Creating Promtail user and group..."

    if ! getent group "$PROMTAIL_GROUP" > /dev/null 2>&1; then
        groupadd --system "$PROMTAIL_GROUP"
        log_success "Created group: $PROMTAIL_GROUP"
    fi

    if ! getent passwd "$PROMTAIL_USER" > /dev/null 2>&1; then
        useradd --system \
            --gid "$PROMTAIL_GROUP" \
            --no-create-home \
            --shell /bin/false \
            "$PROMTAIL_USER"
        log_success "Created user: $PROMTAIL_USER"
    fi

    # Add promtail to adm group for log file access
    usermod -a -G adm "$PROMTAIL_USER"
}

create_directories() {
    log_info "Creating Promtail directories..."

    mkdir -p "$PROMTAIL_CONFIG_DIR"
    mkdir -p "$PROMTAIL_DATA_DIR"
    mkdir -p "$PROMTAIL_LOG_DIR"

    chown -R "$PROMTAIL_USER:$PROMTAIL_GROUP" "$PROMTAIL_CONFIG_DIR"
    chown -R "$PROMTAIL_USER:$PROMTAIL_GROUP" "$PROMTAIL_DATA_DIR"
    chown -R "$PROMTAIL_USER:$PROMTAIL_GROUP" "$PROMTAIL_LOG_DIR"

    chmod 755 "$PROMTAIL_CONFIG_DIR"
    chmod 755 "$PROMTAIL_DATA_DIR"
    chmod 755 "$PROMTAIL_LOG_DIR"

    log_success "Directories created and permissions set"
}

download_promtail() {
    log_info "Downloading Promtail v${PROMTAIL_VERSION}..."

    local temp_dir=$(mktemp -d)
    cd "$temp_dir"

    if ! wget -q --show-progress "$DOWNLOAD_URL"; then
        log_error "Failed to download Promtail"
        rm -rf "$temp_dir"
        exit 1
    fi

    log_info "Extracting Promtail..."
    unzip -q promtail-linux-amd64.zip

    # Install binary
    mv promtail-linux-amd64 /usr/local/bin/promtail
    chown "$PROMTAIL_USER:$PROMTAIL_GROUP" /usr/local/bin/promtail
    chmod 755 /usr/local/bin/promtail

    cd /
    rm -rf "$temp_dir"

    log_success "Promtail binary installed"
}

create_config() {
    log_info "Creating Promtail configuration..."

    cat > "$PROMTAIL_CONFIG_DIR/promtail.yml" <<EOF
# Promtail Configuration - Native Installation
# NO DOCKER

server:
  http_listen_address: 0.0.0.0
  http_listen_port: $PROMTAIL_PORT
  grpc_listen_address: 0.0.0.0
  grpc_listen_port: 9095
  log_level: info

positions:
  filename: $PROMTAIL_DATA_DIR/positions.yaml

clients:
  - url: $LOKI_URL/loki/api/v1/push
    backoff_config:
      min_period: 1s
      max_period: 60s
      max_retries: 10
    timeout: 10s

scrape_configs:
  # System logs
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: system
          host: \${HOSTNAME}
          __path__: /var/log/syslog

  # Auth logs
  - job_name: auth
    static_configs:
      - targets:
          - localhost
        labels:
          job: auth
          host: \${HOSTNAME}
          __path__: /var/log/auth.log

  # CHOM Application Logs (Laravel)
  - job_name: chom
    static_configs:
      - targets:
          - localhost
        labels:
          job: chom
          application: chom
          environment: production
          host: \${HOSTNAME}
          __path__: /var/www/chom/current/storage/logs/*.log
    pipeline_stages:
      # Parse Laravel log format
      - regex:
          expression: '^\[(?P<timestamp>.*?)\] (?P<environment>\w+)\.(?P<level>\w+): (?P<message>.*?)( \{(?P<context>.*)\})? \{(?P<extra>.*)\}$$'
      - labels:
          level:
          environment:
      - timestamp:
          source: timestamp
          format: '2006-01-02 15:04:05'
      - output:
          source: message

  # CHOM Queue Worker Logs
  - job_name: chom_queue
    static_configs:
      - targets:
          - localhost
        labels:
          job: chom_queue
          application: chom
          component: queue
          host: \${HOSTNAME}
          __path__: /var/www/chom/current/storage/logs/queue*.log

  # CHOM Scheduler Logs
  - job_name: chom_scheduler
    static_configs:
      - targets:
          - localhost
        labels:
          job: chom_scheduler
          application: chom
          component: scheduler
          host: \${HOSTNAME}
          __path__: /var/www/chom/current/storage/logs/scheduler*.log

  # Nginx Access Logs
  - job_name: nginx_access
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx_access
          host: \${HOSTNAME}
          __path__: /var/log/nginx/*access.log
    pipeline_stages:
      - regex:
          expression: '^(?P<remote_addr>[\d\.]+) - (?P<remote_user>[\w-]+|\-) \[(?P<time_local>.*?)\] "(?P<method>\w+) (?P<request>.*?) (?P<protocol>HTTP/[\d\.]+)" (?P<status>\d+) (?P<body_bytes_sent>\d+) "(?P<http_referer>.*?)" "(?P<http_user_agent>.*?)"$$'
      - labels:
          method:
          status:

  # Nginx Error Logs
  - job_name: nginx_error
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx_error
          host: \${HOSTNAME}
          __path__: /var/log/nginx/*error.log

  # PHP-FPM Logs
  - job_name: php_fpm
    static_configs:
      - targets:
          - localhost
        labels:
          job: php_fpm
          host: \${HOSTNAME}
          __path__: /var/log/php*-fpm.log

  # MariaDB Error Logs
  - job_name: mariadb
    static_configs:
      - targets:
          - localhost
        labels:
          job: mariadb
          host: \${HOSTNAME}
          __path__: /var/log/mysql/error.log

  # Systemd Journal (for services)
  - job_name: journal
    journal:
      max_age: 12h
      labels:
        job: systemd-journal
        host: \${HOSTNAME}
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'
      - source_labels: ['__journal__hostname']
        target_label: 'hostname'
      - source_labels: ['__journal_priority']
        target_label: 'priority'
EOF

    chown "$PROMTAIL_USER:$PROMTAIL_GROUP" "$PROMTAIL_CONFIG_DIR/promtail.yml"
    chmod 644 "$PROMTAIL_CONFIG_DIR/promtail.yml"

    log_success "Configuration file created"
}

create_systemd_service() {
    log_info "Creating systemd service..."

    cat > /etc/systemd/system/promtail.service <<EOF
[Unit]
Description=Promtail Log Collector
Documentation=https://grafana.com/docs/loki/latest/clients/promtail/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$PROMTAIL_USER
Group=$PROMTAIL_GROUP
SupplementaryGroups=adm

ExecStart=/usr/local/bin/promtail \\
    -config.file=$PROMTAIL_CONFIG_DIR/promtail.yml

ExecReload=/bin/kill -HUP \$MAINPID

Restart=on-failure
RestartSec=5s

StandardOutput=journal
StandardError=journal
SyslogIdentifier=promtail

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$PROMTAIL_DATA_DIR $PROMTAIL_LOG_DIR
ReadOnlyPaths=/var/log /var/www/chom/current/storage/logs
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Systemd service created"
}

configure_log_permissions() {
    log_info "Configuring log file permissions..."

    # Ensure promtail can read CHOM logs
    if [[ -d "/var/www/chom/current/storage/logs" ]]; then
        chmod 755 /var/www/chom/current/storage/logs
        chmod 644 /var/www/chom/current/storage/logs/*.log 2>/dev/null || true
        log_success "CHOM log permissions configured"
    else
        log_warning "CHOM logs directory not found at /var/www/chom/current/storage/logs"
    fi
}

start_service() {
    log_info "Starting Promtail service..."

    systemctl enable promtail
    systemctl start promtail

    sleep 3

    if systemctl is-active --quiet promtail; then
        log_success "Promtail is running"

        # Test endpoint
        if curl -s http://localhost:$PROMTAIL_PORT/ready 2>/dev/null | grep -q "ready"; then
            log_success "Promtail health check passed"
        else
            log_warning "Promtail started but health check failed"
        fi
    else
        log_error "Failed to start Promtail"
        systemctl status promtail --no-pager
        exit 1
    fi
}

show_status() {
    echo ""
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN} Promtail Installation Complete${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Version:        ${BOLD}$PROMTAIL_VERSION${NC}"
    echo -e "Config:         ${BOLD}$PROMTAIL_CONFIG_DIR/promtail.yml${NC}"
    echo -e "Data Directory: ${BOLD}$PROMTAIL_DATA_DIR${NC}"
    echo -e "HTTP API:       ${BOLD}http://localhost:$PROMTAIL_PORT${NC}"
    echo -e "Loki Target:    ${BOLD}$LOKI_URL${NC}"
    echo ""
    echo -e "${BOLD}Useful Commands:${NC}"
    echo "  systemctl status promtail       - Check service status"
    echo "  systemctl restart promtail      - Restart service"
    echo "  journalctl -u promtail -f       - View logs"
    echo "  curl http://localhost:$PROMTAIL_PORT/metrics - View metrics"
    echo ""
    echo -e "${BOLD}Log Sources Configured:${NC}"
    echo "  - System logs (/var/log/syslog)"
    echo "  - Auth logs (/var/log/auth.log)"
    echo "  - CHOM application logs"
    echo "  - Nginx access and error logs"
    echo "  - PHP-FPM logs"
    echo "  - MariaDB logs"
    echo "  - Systemd journal"
    echo ""
    echo -e "${BOLD}Configuration Files:${NC}"
    echo "  Main config:    $PROMTAIL_CONFIG_DIR/promtail.yml"
    echo "  Positions file: $PROMTAIL_DATA_DIR/positions.yaml"
    echo "  Service file:   /etc/systemd/system/promtail.service"
    echo ""
}

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║     Native Promtail Installation - Debian 13              ║"
    echo "║     NO DOCKER - Systemd Service Only                      ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_root
    install_dependencies
    create_user
    create_directories
    download_promtail
    create_config
    create_systemd_service
    configure_log_permissions
    start_service
    show_status
}

main "$@"
