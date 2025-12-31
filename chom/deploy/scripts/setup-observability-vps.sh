#!/bin/bash
#
# CHOM Observability Stack Setup Script
# For vanilla Debian 13 VPS
#
# Installs: Prometheus, Loki, Grafana, Alertmanager, Nginx
#

set -euo pipefail

# Configuration
PROMETHEUS_VERSION="2.54.1"
LOKI_VERSION="3.2.1"
GRAFANA_VERSION="11.3.0"
ALERTMANAGER_VERSION="0.27.0"
NODE_EXPORTER_VERSION="1.8.2"

DATA_DIR="/var/lib/observability"
CONFIG_DIR="/etc/observability"
LOG_DIR="/var/log/observability"

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

# Check Debian version
if ! grep -q "bookworm\|13" /etc/os-release 2>/dev/null; then
    log_warn "This script is designed for Debian 13 (Bookworm)"
fi

log_info "Starting Observability Stack installation..."

# =============================================================================
# SYSTEM SETUP
# =============================================================================

log_info "Updating system packages..."
sudo apt-get update -qq
sudo apt-get upgrade -y -qq

log_info "Installing dependencies..."
sudo apt-get install -y -qq \
    curl \
    wget \
    gnupg \
    apt-transport-https \
    unzip \
    jq \
    nginx \
    certbot \
    python3-certbot-nginx \
    ufw

# Create directories
sudo mkdir -p "$DATA_DIR"/{prometheus,loki,grafana,alertmanager}
sudo mkdir -p "$CONFIG_DIR"/{prometheus,loki,grafana,alertmanager}
sudo mkdir -p "$LOG_DIR"
sudo mkdir -p /opt/observability/bin

# Create service user
if ! id -u observability &>/dev/null; then
sudo useradd --system --no-create-home --shell /usr/sbin/nologin observability
fi

# =============================================================================
# PROMETHEUS
# =============================================================================

log_info "Installing Prometheus ${PROMETHEUS_VERSION}..."

cd /tmp
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
tar xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

# Stop prometheus service before replacing binary
stop_and_verify_service "prometheus" "/opt/observability/bin/prometheus" || {
    log_error "Failed to stop prometheus safely"
    exit 1
}

sudo cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /opt/observability/bin/
sudo cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool" /opt/observability/bin/
rm -rf "prometheus-${PROMETHEUS_VERSION}.linux-amd64"*

# Prometheus config
cat > "$CONFIG_DIR/prometheus/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - localhost:9093

rule_files:
  - /etc/observability/prometheus/rules/*.yml

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']

  # CHOM monitored hosts will be added here dynamically
  # Example:
  # - job_name: 'chom_hosts'
  #   file_sd_configs:
  #     - files:
  #       - /etc/observability/prometheus/targets/*.json
EOF

sudo mkdir -p "$CONFIG_DIR/prometheus/rules"
sudo mkdir -p "$CONFIG_DIR/prometheus/targets"

# Prometheus systemd service
write_system_file /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=observability
Group=observability
Type=simple
ExecStart=/opt/observability/bin/prometheus \\
    --config.file=${CONFIG_DIR}/prometheus/prometheus.yml \\
    --storage.tsdb.path=${DATA_DIR}/prometheus \\
    --storage.tsdb.retention.time=15d \\
    --web.listen-address=:9090 \\
    --web.enable-lifecycle
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo chown -R observability:observability "$DATA_DIR/prometheus" "$CONFIG_DIR/prometheus"

# =============================================================================
# NODE EXPORTER
# =============================================================================

log_info "Installing Node Exporter ${NODE_EXPORTER_VERSION}..."

cd /tmp
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

# Stop node_exporter service before replacing binary
stop_and_verify_service "node_exporter" "/opt/observability/bin/node_exporter" || {
    log_error "Failed to stop node_exporter safely"
    exit 1
}

sudo cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /opt/observability/bin/
rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"*

write_system_file /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=observability
Group=observability
Type=simple
ExecStart=/opt/observability/bin/node_exporter
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# =============================================================================
# LOKI
# =============================================================================

log_info "Installing Loki ${LOKI_VERSION}..."

cd /tmp
wget -q "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip"
unzip -qq "loki-linux-amd64.zip"

# Stop loki service before replacing binary
stop_and_verify_service "loki" "/opt/observability/bin/loki" || {
    log_error "Failed to stop loki safely"
    exit 1
}

sudo mv loki-linux-amd64 /opt/observability/bin/loki
sudo chmod +x /opt/observability/bin/loki
rm -f loki-linux-amd64.zip

# Loki config
cat > "$CONFIG_DIR/loki/loki.yml" << EOF
auth_enabled: true

server:
  http_listen_port: 3100

common:
  path_prefix: ${DATA_DIR}/loki
  storage:
    filesystem:
      chunks_directory: ${DATA_DIR}/loki/chunks
      rules_directory: ${DATA_DIR}/loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 720h
  allow_structured_metadata: true
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20

compactor:
  working_directory: ${DATA_DIR}/loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  delete_request_store: filesystem
EOF

sudo mkdir -p "$DATA_DIR/loki"/{chunks,rules,compactor}

write_system_file /etc/systemd/system/loki.service << EOF
[Unit]
Description=Loki
Wants=network-online.target
After=network-online.target

[Service]
User=observability
Group=observability
Type=simple
ExecStart=/opt/observability/bin/loki -config.file=${CONFIG_DIR}/loki/loki.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo chown -R observability:observability "$DATA_DIR/loki" "$CONFIG_DIR/loki"

# =============================================================================
# ALERTMANAGER
# =============================================================================

log_info "Installing Alertmanager ${ALERTMANAGER_VERSION}..."

cd /tmp
wget -q "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
tar xzf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"

# Stop alertmanager service before replacing binary
stop_and_verify_service "alertmanager" "/opt/observability/bin/alertmanager" || {
    log_error "Failed to stop alertmanager safely"
    exit 1
}

sudo cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager" /opt/observability/bin/
rm -rf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64"*

# Alertmanager config
cat > "$CONFIG_DIR/alertmanager/alertmanager.yml" << 'EOF'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'default'

receivers:
  - name: 'default'
    # Configure email/slack here
    # email_configs:
    #   - to: 'alerts@example.com'
EOF

write_system_file /etc/systemd/system/alertmanager.service << EOF
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=observability
Group=observability
Type=simple
ExecStart=/opt/observability/bin/alertmanager \\
    --config.file=${CONFIG_DIR}/alertmanager/alertmanager.yml \\
    --storage.path=${DATA_DIR}/alertmanager
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo chown -R observability:observability "$DATA_DIR/alertmanager" "$CONFIG_DIR/alertmanager"

# =============================================================================
# GRAFANA
# =============================================================================

log_info "Installing Grafana ${GRAFANA_VERSION}..."

# Add Grafana repo
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
sudo apt-get update -qq
sudo apt-get install -y -qq grafana

# Configure Grafana
cat > /etc/grafana/provisioning/datasources/datasources.yaml << 'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true

  - name: Loki
    type: loki
    access: proxy
    url: http://localhost:3100
    jsonData:
      httpHeaderName1: 'X-Loki-Org-Id'
    secureJsonData:
      httpHeaderValue1: 'default'
EOF

# Generate admin password
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
sed -i "s/;admin_password = admin/admin_password = ${GRAFANA_ADMIN_PASSWORD}/" /etc/grafana/grafana.ini

# =============================================================================
# NGINX REVERSE PROXY
# =============================================================================

log_info "Configuring Nginx..."

write_system_file /etc/nginx/sites-available/observability << 'EOF'
# Grafana
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Prometheus (internal only by default)
server {
    listen 9090;
    server_name localhost;

    location / {
        proxy_pass http://127.0.0.1:9090;
    }
}
EOF

ln -sf /etc/nginx/sites-available/observability /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t

# =============================================================================
# FIREWALL
# =============================================================================

log_info "Configuring firewall..."

sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp      # Nginx/Grafana
sudo ufw allow 443/tcp     # HTTPS
sudo ufw allow 3100/tcp    # Loki (for log ingestion from monitored hosts)
sudo ufw allow 9090/tcp    # Prometheus (for federation if needed)
sudo ufw --force enable

# =============================================================================
# START SERVICES
# =============================================================================

log_info "Starting services..."

sudo systemctl daemon-reload

sudo systemctl enable --now prometheus
sudo systemctl enable --now node_exporter
sudo systemctl enable --now loki
sudo systemctl enable --now alertmanager
sudo systemctl enable --now grafana-server
sudo systemctl restart nginx

# Wait for services to start
sleep 5

# =============================================================================
# VERIFICATION
# =============================================================================

log_info "Verifying installation..."

SERVICES=("prometheus" "node_exporter" "loki" "alertmanager" "grafana-server" "nginx")
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
echo "  Observability Stack Installed!"
echo "=========================================="
echo ""
echo "Services:"
echo "  - Grafana:      http://${IP_ADDRESS}:80"
echo "  - Prometheus:   http://${IP_ADDRESS}:9090"
echo "  - Loki:         http://${IP_ADDRESS}:3100"
echo "  - Alertmanager: http://${IP_ADDRESS}:9093"
echo ""
echo "Grafana Credentials:"
echo "  - Username: admin"
echo "  - Password: ${GRAFANA_ADMIN_PASSWORD}"
echo ""
echo "IMPORTANT: Save this password! It will not be shown again."
echo ""

# Save credentials
cat > /root/.observability-credentials << EOF
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
EOF
sudo chmod 600 /root/.observability-credentials

if $ALL_OK; then
    log_success "Installation completed successfully!"
    exit 0
else
    log_error "Installation completed with failures - some services did not start"
    log_error "Check logs with: journalctl -xeu <service-name>"
    exit 1
fi
