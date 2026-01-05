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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# Check Debian version
if ! grep -q "trixie\|13" /etc/os-release 2>/dev/null; then
    log_warn "This script is designed for Debian 13 (Trixie)"
    log_info "Detected: $(lsb_release -sc 2>/dev/null || echo 'unknown')"
fi

log_info "Starting Observability Stack installation..."

# =============================================================================
# SYSTEM SETUP
# =============================================================================

log_info "Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq

log_info "Installing dependencies..."
# Install essential packages for Debian 13 (Trixie)
apt-get install -y -qq \
    curl \
    wget \
    gnupg \
    lsb-release \
    apt-transport-https \
    unzip \
    jq \
    nginx \
    certbot \
    python3-certbot-nginx \
    ufw

# Create directories
mkdir -p "$DATA_DIR"/{prometheus,loki,grafana,alertmanager}
mkdir -p "$CONFIG_DIR"/{prometheus,loki,grafana,alertmanager}
mkdir -p "$LOG_DIR"
mkdir -p /opt/observability/bin

# Create service user
if ! id -u observability &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin observability
fi

# =============================================================================
# PROMETHEUS
# =============================================================================

log_info "Installing Prometheus ${PROMETHEUS_VERSION}..."

cd /tmp
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
tar xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /opt/observability/bin/
cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool" /opt/observability/bin/
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

mkdir -p "$CONFIG_DIR/prometheus/rules"
mkdir -p "$CONFIG_DIR/prometheus/targets"

# Prometheus systemd service
cat > /etc/systemd/system/prometheus.service << EOF
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
    --web.enable-lifecycle \\
    --web.external-url=https://mentat.arewel.com/prometheus \\
    --web.route-prefix=/prometheus
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

chown -R observability:observability "$DATA_DIR/prometheus" "$CONFIG_DIR/prometheus"

# =============================================================================
# NODE EXPORTER
# =============================================================================

log_info "Installing Node Exporter ${NODE_EXPORTER_VERSION}..."

cd /tmp
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /opt/observability/bin/
rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"*

cat > /etc/systemd/system/node_exporter.service << 'EOF'
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
mv loki-linux-amd64 /opt/observability/bin/loki
chmod +x /opt/observability/bin/loki
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

mkdir -p "$DATA_DIR/loki"/{chunks,rules,compactor}

cat > /etc/systemd/system/loki.service << EOF
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

chown -R observability:observability "$DATA_DIR/loki" "$CONFIG_DIR/loki"

# =============================================================================
# ALERTMANAGER
# =============================================================================

log_info "Installing Alertmanager ${ALERTMANAGER_VERSION}..."

cd /tmp
wget -q "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
tar xzf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager" /opt/observability/bin/
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

cat > /etc/systemd/system/alertmanager.service << EOF
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
    --storage.path=${DATA_DIR}/alertmanager \\
    --web.external-url=https://mentat.arewel.com/alertmanager \\
    --web.route-prefix=/alertmanager
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

chown -R observability:observability "$DATA_DIR/alertmanager" "$CONFIG_DIR/alertmanager"

# =============================================================================
# GRAFANA
# =============================================================================

log_info "Installing Grafana ${GRAFANA_VERSION}..."

# Add Grafana repo
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
apt-get update -qq
apt-get install -y -qq grafana

# Configure Grafana
cat > /etc/grafana/provisioning/datasources/datasources.yaml << 'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090/prometheus
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

cat > /etc/nginx/sites-available/observability << 'EOF'
# Observability Stack - HTTP (redirect to HTTPS after SSL setup)
server {
    listen 80;
    server_name mentat.arewel.com _;

    # ACME challenge for Let's Encrypt
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
        default_type "text/plain";
        try_files $uri =404;
    }

    # Default: Grafana at root
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Prometheus at /prometheus
    location /prometheus {
        proxy_pass http://127.0.0.1:9090/prometheus;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # AlertManager at /alertmanager
    location /alertmanager {
        proxy_pass http://127.0.0.1:9093;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Loki at /loki
    location /loki {
        proxy_pass http://127.0.0.1:3100;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Loki-Org-Id default;
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

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp      # Nginx/Grafana
ufw allow 443/tcp     # HTTPS
ufw allow 3100/tcp    # Loki (for log ingestion from monitored hosts)
ufw allow 9090/tcp    # Prometheus (for federation if needed)
ufw --force enable

# =============================================================================
# START SERVICES
# =============================================================================

log_info "Starting services..."

systemctl daemon-reload

systemctl enable --now prometheus
systemctl enable --now node_exporter
systemctl enable --now loki
systemctl enable --now alertmanager
systemctl enable --now grafana-server
systemctl restart nginx

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
chmod 600 /root/.observability-credentials

if $ALL_OK; then
    log_success "Installation completed successfully!"
else
    log_warn "Installation completed with some warnings"
fi
