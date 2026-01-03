#!/bin/bash

###############################################################################
# Native Loki Installation for Debian 13
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
LOKI_VERSION="2.9.4"
LOKI_USER="loki"
LOKI_GROUP="loki"
LOKI_CONFIG_DIR="/etc/loki"
LOKI_DATA_DIR="/var/lib/loki"
LOKI_LOG_DIR="/var/log/loki"
LOKI_PORT=3100
DOWNLOAD_URL="https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip"

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
    log_info "Creating Loki user and group..."

    if ! getent group "$LOKI_GROUP" > /dev/null 2>&1; then
        groupadd --system "$LOKI_GROUP"
        log_success "Created group: $LOKI_GROUP"
    fi

    if ! getent passwd "$LOKI_USER" > /dev/null 2>&1; then
        useradd --system \
            --gid "$LOKI_GROUP" \
            --no-create-home \
            --shell /bin/false \
            "$LOKI_USER"
        log_success "Created user: $LOKI_USER"
    fi
}

create_directories() {
    log_info "Creating Loki directories..."

    mkdir -p "$LOKI_CONFIG_DIR"
    mkdir -p "$LOKI_DATA_DIR"
    mkdir -p "$LOKI_DATA_DIR/chunks"
    mkdir -p "$LOKI_DATA_DIR/index"
    mkdir -p "$LOKI_DATA_DIR/boltdb-shipper-active"
    mkdir -p "$LOKI_DATA_DIR/boltdb-shipper-cache"
    mkdir -p "$LOKI_DATA_DIR/wal"
    mkdir -p "$LOKI_LOG_DIR"

    chown -R "$LOKI_USER:$LOKI_GROUP" "$LOKI_CONFIG_DIR"
    chown -R "$LOKI_USER:$LOKI_GROUP" "$LOKI_DATA_DIR"
    chown -R "$LOKI_USER:$LOKI_GROUP" "$LOKI_LOG_DIR"

    chmod 755 "$LOKI_CONFIG_DIR"
    chmod 755 "$LOKI_DATA_DIR"
    chmod 755 "$LOKI_LOG_DIR"

    log_success "Directories created and permissions set"
}

download_loki() {
    log_info "Downloading Loki v${LOKI_VERSION}..."

    local temp_dir=$(mktemp -d)
    cd "$temp_dir"

    if ! wget -q --show-progress "$DOWNLOAD_URL"; then
        log_error "Failed to download Loki"
        rm -rf "$temp_dir"
        exit 1
    fi

    log_info "Extracting Loki..."
    unzip -q loki-linux-amd64.zip

    # Install binary
    mv loki-linux-amd64 /usr/local/bin/loki
    chown "$LOKI_USER:$LOKI_GROUP" /usr/local/bin/loki
    chmod 755 /usr/local/bin/loki

    cd /
    rm -rf "$temp_dir"

    log_success "Loki binary installed"
}

create_config() {
    log_info "Creating Loki configuration..."

    cat > "$LOKI_CONFIG_DIR/loki.yml" <<EOF
# Loki Configuration - Native Installation
# NO DOCKER

auth_enabled: false

server:
  http_listen_address: 0.0.0.0
  http_listen_port: $LOKI_PORT
  grpc_listen_address: 0.0.0.0
  grpc_listen_port: 9096
  log_level: info

common:
  path_prefix: $LOKI_DATA_DIR
  storage:
    filesystem:
      chunks_directory: $LOKI_DATA_DIR/chunks
      rules_directory: $LOKI_CONFIG_DIR/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100

schema_config:
  configs:
    - from: 2023-01-01
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: $LOKI_DATA_DIR/boltdb-shipper-active
    cache_location: $LOKI_DATA_DIR/boltdb-shipper-cache
    cache_ttl: 24h
    shared_store: filesystem
  filesystem:
    directory: $LOKI_DATA_DIR/chunks

limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  ingestion_rate_mb: 16
  ingestion_burst_size_mb: 32
  max_query_length: 721h
  max_query_parallelism: 32
  max_streams_per_user: 10000
  max_global_streams_per_user: 10000
  max_chunks_per_query: 2000000
  max_entries_limit_per_query: 10000

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: true
  retention_period: 720h

compactor:
  working_directory: $LOKI_DATA_DIR/compactor
  shared_store: filesystem
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  retention_delete_worker_count: 150

ruler:
  storage:
    type: local
    local:
      directory: $LOKI_CONFIG_DIR/rules
  rule_path: $LOKI_DATA_DIR/rules-temp
  alertmanager_url: http://localhost:9093
  ring:
    kvstore:
      store: inmemory
  enable_api: true
  enable_alertmanager_v2: true

analytics:
  reporting_enabled: false
EOF

    chown "$LOKI_USER:$LOKI_GROUP" "$LOKI_CONFIG_DIR/loki.yml"
    chmod 644 "$LOKI_CONFIG_DIR/loki.yml"

    log_success "Configuration file created"
}

create_systemd_service() {
    log_info "Creating systemd service..."

    cat > /etc/systemd/system/loki.service <<EOF
[Unit]
Description=Loki Log Aggregation System
Documentation=https://grafana.com/docs/loki/latest/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$LOKI_USER
Group=$LOKI_GROUP

ExecStart=/usr/local/bin/loki \\
    -config.file=$LOKI_CONFIG_DIR/loki.yml

ExecReload=/bin/kill -HUP \$MAINPID

Restart=on-failure
RestartSec=5s

StandardOutput=journal
StandardError=journal
SyslogIdentifier=loki

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$LOKI_DATA_DIR $LOKI_LOG_DIR
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
    log_info "Creating Loki alert rules..."

    mkdir -p "$LOKI_CONFIG_DIR/rules/fake"

    cat > "$LOKI_CONFIG_DIR/rules/fake/chom-log-alerts.yml" <<'EOF'
groups:
  - name: chom_log_alerts
    interval: 1m
    rules:
      # High error rate in logs
      - alert: HighLogErrorRate
        expr: |
          sum(rate({job="chom"} |= "ERROR" [5m])) > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate in application logs"
          description: "More than 10 errors per second detected in logs"

      # Critical errors
      - alert: CriticalErrorsInLogs
        expr: |
          sum(rate({job="chom"} |~ "CRITICAL|FATAL" [5m])) > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Critical errors detected in logs"
          description: "CRITICAL or FATAL errors found in application logs"

      # Database connection errors
      - alert: DatabaseConnectionErrors
        expr: |
          sum(rate({job="chom"} |~ "database.*connection.*error|SQLSTATE" [5m])) > 1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Database connection errors detected"
          description: "Multiple database connection errors in logs"

      # PHP errors
      - alert: PHPErrors
        expr: |
          sum(rate({job="chom"} |~ "PHP Fatal error|PHP Warning" [5m])) > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High PHP error rate"
          description: "Multiple PHP errors detected in logs"
EOF

    chown -R "$LOKI_USER:$LOKI_GROUP" "$LOKI_CONFIG_DIR/rules"
    chmod 644 "$LOKI_CONFIG_DIR/rules/fake/chom-log-alerts.yml"

    log_success "Alert rules created"
}

configure_firewall() {
    log_info "Configuring firewall for Loki..."

    if command -v ufw &> /dev/null; then
        ufw allow "$LOKI_PORT/tcp" comment "Loki HTTP"
        ufw allow 9096/tcp comment "Loki gRPC"
        log_success "UFW rules added"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port="$LOKI_PORT/tcp"
        firewall-cmd --permanent --add-port=9096/tcp
        firewall-cmd --reload
        log_success "Firewalld rules added"
    else
        log_warning "No firewall detected. Please manually open ports $LOKI_PORT and 9096"
    fi
}

start_service() {
    log_info "Starting Loki service..."

    systemctl enable loki
    systemctl start loki

    sleep 3

    if systemctl is-active --quiet loki; then
        log_success "Loki is running"

        # Test endpoint
        if curl -s http://localhost:$LOKI_PORT/ready | grep -q "ready"; then
            log_success "Loki health check passed"
        else
            log_warning "Loki started but health check failed"
        fi
    else
        log_error "Failed to start Loki"
        systemctl status loki --no-pager
        exit 1
    fi
}

show_status() {
    echo ""
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN} Loki Installation Complete${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Version:        ${BOLD}$LOKI_VERSION${NC}"
    echo -e "Config:         ${BOLD}$LOKI_CONFIG_DIR/loki.yml${NC}"
    echo -e "Data Directory: ${BOLD}$LOKI_DATA_DIR${NC}"
    echo -e "HTTP API:       ${BOLD}http://localhost:$LOKI_PORT${NC}"
    echo -e "gRPC Port:      ${BOLD}9096${NC}"
    echo ""
    echo -e "${BOLD}Useful Commands:${NC}"
    echo "  systemctl status loki           - Check service status"
    echo "  systemctl restart loki          - Restart service"
    echo "  journalctl -u loki -f           - View logs"
    echo "  curl http://localhost:$LOKI_PORT/ready  - Health check"
    echo ""
    echo -e "${BOLD}Query Examples:${NC}"
    echo "  # Get labels:"
    echo "  curl -s http://localhost:$LOKI_PORT/loki/api/v1/labels"
    echo ""
    echo "  # Query logs:"
    echo "  curl -G -s http://localhost:$LOKI_PORT/loki/api/v1/query_range \\"
    echo "    --data-urlencode 'query={job=\"chom\"}' \\"
    echo "    --data-urlencode 'limit=10'"
    echo ""
    echo -e "${BOLD}Configuration Files:${NC}"
    echo "  Main config:    $LOKI_CONFIG_DIR/loki.yml"
    echo "  Alert rules:    $LOKI_CONFIG_DIR/rules/"
    echo "  Service file:   /etc/systemd/system/loki.service"
    echo ""
}

main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║     Native Loki Installation - Debian 13                  ║"
    echo "║     NO DOCKER - Systemd Service Only                      ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_root
    install_dependencies
    create_user
    create_directories
    download_loki
    create_config
    create_alert_rules
    create_systemd_service
    configure_firewall
    start_service
    show_status
}

main "$@"
