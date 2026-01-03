#!/bin/bash

###############################################################################
# Native Prometheus Installation for Debian 13
# NO DOCKER - Systemd service only
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
PROMETHEUS_VERSION="2.49.1"
PROMETHEUS_USER="prometheus"
PROMETHEUS_GROUP="prometheus"
PROMETHEUS_CONFIG_DIR="/etc/prometheus"
PROMETHEUS_DATA_DIR="/var/lib/prometheus"
PROMETHEUS_LOG_DIR="/var/log/prometheus"
PROMETHEUS_PORT=9090
DOWNLOAD_URL="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

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

create_user() {
    log_info "Creating Prometheus user and group..."

    if ! getent group "$PROMETHEUS_GROUP" > /dev/null 2>&1; then
        groupadd --system "$PROMETHEUS_GROUP"
        log_success "Created group: $PROMETHEUS_GROUP"
    fi

    if ! getent passwd "$PROMETHEUS_USER" > /dev/null 2>&1; then
        useradd --system \
            --gid "$PROMETHEUS_GROUP" \
            --no-create-home \
            --shell /bin/false \
            "$PROMETHEUS_USER"
        log_success "Created user: $PROMETHEUS_USER"
    fi
}

create_directories() {
    log_info "Creating Prometheus directories..."

    mkdir -p "$PROMETHEUS_CONFIG_DIR"
    mkdir -p "$PROMETHEUS_CONFIG_DIR/rules"
    mkdir -p "$PROMETHEUS_CONFIG_DIR/file_sd"
    mkdir -p "$PROMETHEUS_DATA_DIR"
    mkdir -p "$PROMETHEUS_LOG_DIR"

    chown -R "$PROMETHEUS_USER:$PROMETHEUS_GROUP" "$PROMETHEUS_CONFIG_DIR"
    chown -R "$PROMETHEUS_USER:$PROMETHEUS_GROUP" "$PROMETHEUS_DATA_DIR"
    chown -R "$PROMETHEUS_USER:$PROMETHEUS_GROUP" "$PROMETHEUS_LOG_DIR"

    chmod 755 "$PROMETHEUS_CONFIG_DIR"
    chmod 755 "$PROMETHEUS_DATA_DIR"
    chmod 755 "$PROMETHEUS_LOG_DIR"

    log_success "Directories created and permissions set"
}

download_prometheus() {
    log_info "Downloading Prometheus v${PROMETHEUS_VERSION}..."

    local temp_dir=$(mktemp -d)
    cd "$temp_dir"

    if ! wget -q --show-progress "$DOWNLOAD_URL"; then
        log_error "Failed to download Prometheus"
        rm -rf "$temp_dir"
        exit 1
    fi

    log_info "Extracting Prometheus..."
    tar xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

    cd "prometheus-${PROMETHEUS_VERSION}.linux-amd64"

    # Install binaries
    cp prometheus /usr/local/bin/
    cp promtool /usr/local/bin/

    # Set permissions
    chown "$PROMETHEUS_USER:$PROMETHEUS_GROUP" /usr/local/bin/prometheus
    chown "$PROMETHEUS_USER:$PROMETHEUS_GROUP" /usr/local/bin/promtool
    chmod 755 /usr/local/bin/prometheus
    chmod 755 /usr/local/bin/promtool

    # Copy consoles and console_libraries
    cp -r consoles "$PROMETHEUS_CONFIG_DIR/"
    cp -r console_libraries "$PROMETHEUS_CONFIG_DIR/"

    chown -R "$PROMETHEUS_USER:$PROMETHEUS_GROUP" "$PROMETHEUS_CONFIG_DIR/consoles"
    chown -R "$PROMETHEUS_USER:$PROMETHEUS_GROUP" "$PROMETHEUS_CONFIG_DIR/console_libraries"

    cd /
    rm -rf "$temp_dir"

    log_success "Prometheus binaries installed"
}

create_config() {
    log_info "Creating Prometheus configuration..."

    cat > "$PROMETHEUS_CONFIG_DIR/prometheus.yml" <<'EOF'
# Prometheus Configuration - Native Installation
# NO DOCKER

global:
  scrape_interval: 15s
  scrape_timeout: 10s
  evaluation_interval: 15s
  external_labels:
    cluster: 'chom-production'
    environment: 'production'

# AlertManager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - localhost:9093

# Load rules
rule_files:
  - "rules/*.yml"

# Scrape configurations
scrape_configs:
  # Prometheus self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          service: 'prometheus'

  # Node Exporter - System metrics
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
        labels:
          service: 'node_exporter'
          instance: 'monitoring-server'

  # CHOM Application Server
  - job_name: 'chom_app'
    static_configs:
      - targets: ['landsraad.arewel.com:9100']
        labels:
          service: 'app_server'
          instance: 'landsraad'

  # CHOM Application Metrics
  - job_name: 'chom'
    metrics_path: '/metrics'
    scrape_interval: 30s
    static_configs:
      - targets: ['landsraad.arewel.com']
        labels:
          service: 'chom_application'

  # AlertManager
  - job_name: 'alertmanager'
    static_configs:
      - targets: ['localhost:9093']
        labels:
          service: 'alertmanager'

  # Grafana
  - job_name: 'grafana'
    static_configs:
      - targets: ['localhost:3000']
        labels:
          service: 'grafana'

  # Loki
  - job_name: 'loki'
    static_configs:
      - targets: ['localhost:3100']
        labels:
          service: 'loki'

# Remote write (optional - for long-term storage)
# remote_write:
#   - url: http://localhost:9009/api/v1/push
EOF

    chown "$PROMETHEUS_USER:$PROMETHEUS_GROUP" "$PROMETHEUS_CONFIG_DIR/prometheus.yml"
    chmod 644 "$PROMETHEUS_CONFIG_DIR/prometheus.yml"

    log_success "Configuration file created"
}

create_systemd_service() {
    log_info "Creating systemd service..."

    cat > /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus Time Series Database
Documentation=https://prometheus.io/docs/introduction/overview/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$PROMETHEUS_USER
Group=$PROMETHEUS_GROUP

ExecStart=/usr/local/bin/prometheus \\
    --config.file=$PROMETHEUS_CONFIG_DIR/prometheus.yml \\
    --storage.tsdb.path=$PROMETHEUS_DATA_DIR \\
    --storage.tsdb.retention.time=30d \\
    --storage.tsdb.retention.size=10GB \\
    --web.console.templates=$PROMETHEUS_CONFIG_DIR/consoles \\
    --web.console.libraries=$PROMETHEUS_CONFIG_DIR/console_libraries \\
    --web.listen-address=0.0.0.0:$PROMETHEUS_PORT \\
    --web.enable-lifecycle \\
    --web.enable-admin-api

ExecReload=/bin/kill -HUP \$MAINPID

Restart=on-failure
RestartSec=5s

StandardOutput=journal
StandardError=journal
SyslogIdentifier=prometheus

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$PROMETHEUS_DATA_DIR $PROMETHEUS_LOG_DIR
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

create_alert_rules() {
    log_info "Creating default alert rules..."

    cat > "$PROMETHEUS_CONFIG_DIR/rules/chom-alerts.yml" <<'EOF'
groups:
  - name: chom_application_alerts
    interval: 30s
    rules:
      # Instance down
      - alert: InstanceDown
        expr: up == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Instance {{ \$labels.instance }} is down"
          description: "{{ \$labels.instance }} of job {{ \$labels.job }} has been down for more than 5 minutes."

      # High CPU usage
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ \$labels.instance }}"
          description: "CPU usage is above 80% for 10 minutes on {{ \$labels.instance }}"

      # High memory usage
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High memory usage on {{ \$labels.instance }}"
          description: "Memory usage is above 90% on {{ \$labels.instance }}"

      # Disk space running out
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space on {{ \$labels.instance }}"
          description: "Disk space is below 10% on {{ \$labels.instance }}"

      # High HTTP error rate
      - alert: HighHTTPErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High HTTP error rate"
          description: "HTTP 5xx error rate is above 10 req/s"

      # Slow HTTP response time
      - alert: SlowHTTPResponse
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 2
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Slow HTTP response time"
          description: "95th percentile response time is above 2 seconds"

      # Database query performance
      - alert: SlowDatabaseQueries
        expr: rate(db_query_duration_seconds_sum[5m]) / rate(db_query_duration_seconds_count[5m]) > 1
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Slow database queries detected"
          description: "Average database query time is above 1 second"
EOF

    chown "$PROMETHEUS_USER:$PROMETHEUS_GROUP" "$PROMETHEUS_CONFIG_DIR/rules/chom-alerts.yml"
    chmod 644 "$PROMETHEUS_CONFIG_DIR/rules/chom-alerts.yml"

    log_success "Alert rules created"
}

validate_config() {
    log_info "Validating Prometheus configuration..."

    if /usr/local/bin/promtool check config "$PROMETHEUS_CONFIG_DIR/prometheus.yml"; then
        log_success "Configuration is valid"
    else
        log_error "Configuration validation failed"
        exit 1
    fi
}

configure_firewall() {
    log_info "Configuring firewall for Prometheus..."

    if command -v ufw &> /dev/null; then
        ufw allow "$PROMETHEUS_PORT/tcp" comment "Prometheus"
        log_success "UFW rule added for port $PROMETHEUS_PORT"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port="$PROMETHEUS_PORT/tcp"
        firewall-cmd --reload
        log_success "Firewalld rule added for port $PROMETHEUS_PORT"
    else
        log_warning "No firewall detected. Please manually open port $PROMETHEUS_PORT"
    fi
}

start_service() {
    log_info "Starting Prometheus service..."

    systemctl enable prometheus
    systemctl start prometheus

    sleep 3

    if systemctl is-active --quiet prometheus; then
        log_success "Prometheus is running"

        # Test endpoint
        if curl -s http://localhost:$PROMETHEUS_PORT/-/healthy > /dev/null; then
            log_success "Prometheus health check passed"
        else
            log_warning "Prometheus started but health check failed"
        fi
    else
        log_error "Failed to start Prometheus"
        systemctl status prometheus --no-pager
        exit 1
    fi
}

show_status() {
    echo ""
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN} Prometheus Installation Complete${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Version:        ${BOLD}$PROMETHEUS_VERSION${NC}"
    echo -e "Config:         ${BOLD}$PROMETHEUS_CONFIG_DIR/prometheus.yml${NC}"
    echo -e "Data Directory: ${BOLD}$PROMETHEUS_DATA_DIR${NC}"
    echo -e "Web UI:         ${BOLD}http://localhost:$PROMETHEUS_PORT${NC}"
    echo ""
    echo -e "${BOLD}Useful Commands:${NC}"
    echo "  systemctl status prometheus     - Check service status"
    echo "  systemctl restart prometheus    - Restart service"
    echo "  journalctl -u prometheus -f     - View logs"
    echo "  promtool check config /etc/prometheus/prometheus.yml - Validate config"
    echo ""
    echo -e "${BOLD}Configuration Files:${NC}"
    echo "  Main config:    $PROMETHEUS_CONFIG_DIR/prometheus.yml"
    echo "  Alert rules:    $PROMETHEUS_CONFIG_DIR/rules/"
    echo "  Service file:   /etc/systemd/system/prometheus.service"
    echo ""
}

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║     Native Prometheus Installation - Debian 13            ║"
    echo "║     NO DOCKER - Systemd Service Only                      ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_root
    create_user
    create_directories
    download_prometheus
    create_config
    create_alert_rules
    create_systemd_service
    validate_config
    configure_firewall
    start_service
    show_status
}

main "$@"
