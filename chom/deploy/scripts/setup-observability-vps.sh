#!/bin/bash
#
# CHOM Observability Stack Setup Script
# For Debian 12 (Bookworm) and Debian 13 (Trixie)
#
# Installs: Prometheus, Loki, Grafana, Alertmanager, Nginx
#

set -euo pipefail

# Configuration - Dynamic Version Detection
# Fetch latest stable versions from GitHub releases (fallback to hardcoded if API fails)
PROMETHEUS_VERSION="${PROMETHEUS_VERSION:-$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/' 2>/dev/null || echo '3.8.1')}"
LOKI_VERSION="${LOKI_VERSION:-$(curl -s https://api.github.com/repos/grafana/loki/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/' 2>/dev/null || echo '3.6.3')}"
ALERTMANAGER_VERSION="${ALERTMANAGER_VERSION:-$(curl -s https://api.github.com/repos/prometheus/alertmanager/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/' 2>/dev/null || echo '0.27.0')}"
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/' 2>/dev/null || echo '1.10.2')}"
# Grafana installed via APT - version managed by repository

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

# Enhanced stop service with force-kill capabilities - NEVER FAILS
stop_and_verify_service() {
    local service_name="$1"
    local binary_path="$2"
    local max_wait=30
    local waited=0

    log_info "Attempting to stop ${service_name}..."

    # Check if service exists
    if ! systemctl list-unit-files | grep -q "^${service_name}.service"; then
        log_info "Service ${service_name} does not exist yet, skipping stop"
        return 0
    fi

    # Step 0: Disable service to prevent auto-restart during binary replacement
    if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
        log_info "Disabling ${service_name} to prevent auto-restart..."
        sudo systemctl disable "$service_name" 2>/dev/null || log_warn "Disable returned error, continuing..."
    fi

    # Step 1: Graceful systemctl stop
    if systemctl is-active --quiet "$service_name"; then
        log_info "Stopping ${service_name} gracefully..."
        sudo systemctl stop "$service_name" 2>/dev/null || log_warn "Graceful stop returned error, continuing..."
    fi

    # Step 2: Wait for binary to be released
    log_info "Waiting up to ${max_wait}s for ${binary_path} to be released..."
    while [[ $waited -lt $max_wait ]]; do
        if ! lsof "$binary_path" 2>/dev/null | grep -q "$binary_path"; then
            log_success "${service_name} stopped and binary released"
            return 0
        fi
        sleep 1
        ((waited++))
    done

    # Step 3: Force kill with SIGTERM then SIGKILL
    log_warn "Binary still in use after ${max_wait}s, force killing processes..."
    local pids=$(lsof -t "$binary_path" 2>/dev/null)
    if [[ -n "$pids" ]]; then
        log_info "Sending SIGTERM to PIDs: $pids"
        echo "$pids" | xargs -r sudo kill -15 2>/dev/null || true
        sleep 2

        # Check if still running
        pids=$(lsof -t "$binary_path" 2>/dev/null)
        if [[ -n "$pids" ]]; then
            log_warn "Processes still alive, sending SIGKILL to PIDs: $pids"
            echo "$pids" | xargs -r sudo kill -9 2>/dev/null || true
            sleep 1
        fi
    fi

    # Step 4: Nuclear option - fuser -k
    if lsof "$binary_path" 2>/dev/null | grep -q "$binary_path"; then
        log_warn "Binary STILL in use, using fuser -k (nuclear option)..."
        sudo fuser -k -TERM "$binary_path" 2>/dev/null || true
        sleep 2
        sudo fuser -k -KILL "$binary_path" 2>/dev/null || true
        sleep 1
    fi

    # Step 5: Final verification
    if lsof "$binary_path" 2>/dev/null | grep -q "$binary_path"; then
        log_warn "Binary may still be in use, but proceeding anyway (will be overwritten)"
    else
        log_success "Binary successfully released after force kill"
    fi

    # ALWAYS return success - we've done our best
    return 0
}

# Cleanup port conflicts by killing processes using specific ports
cleanup_port_conflicts() {
    local ports=("$@")

    log_info "Checking for port conflicts on ports: ${ports[*]}"

    for port in "${ports[@]}"; do
        local pids=$(sudo lsof -ti ":$port" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            log_warn "Port $port is in use by PIDs: $pids"
            log_info "Killing processes on port $port..."
            echo "$pids" | xargs -r sudo kill -15 2>/dev/null || true
            sleep 2

            # Check if still running
            pids=$(sudo lsof -ti ":$port" 2>/dev/null || true)
            if [[ -n "$pids" ]]; then
                log_warn "Processes still alive on port $port, force killing..."
                echo "$pids" | xargs -r sudo kill -9 2>/dev/null || true
                sleep 1
            fi

            # Final check
            pids=$(sudo lsof -ti ":$port" 2>/dev/null || true)
            if [[ -n "$pids" ]]; then
                log_warn "Port $port may still be in use, but proceeding..."
            else
                log_success "Port $port cleared"
            fi
        fi
    done
}

# Full cleanup before installation - stops all services and kills processes
run_full_cleanup() {
    log_info "=========================================="
    log_info "  RUNNING FULL CLEANUP"
    log_info "=========================================="

    # List of all observability services
    local services=("prometheus" "node_exporter" "loki" "alertmanager" "grafana-server")

    # Stop all services
    log_info "Stopping all observability services..."
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            log_info "Stopping $service..."
            sudo systemctl stop "$service" 2>/dev/null || log_warn "Could not stop $service gracefully"
        fi
    done

    # Wait a moment for graceful shutdown
    sleep 3

    # Kill any remaining processes
    log_info "Killing any remaining observability processes..."
    local process_patterns=("prometheus" "node_exporter" "loki" "alertmanager" "grafana-server")
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
    cleanup_port_conflicts 9090 9100 3100 9093 3000

    # Remove old binaries if they exist and are locked
    log_info "Ensuring old binaries can be replaced..."
    local binaries=(
        "/opt/observability/bin/prometheus"
        "/opt/observability/bin/node_exporter"
        "/opt/observability/bin/loki"
        "/opt/observability/bin/alertmanager"
    )

    for binary in "${binaries[@]}"; do
        if [[ -f "$binary" ]]; then
            # Try to remove any lingering locks
            sudo fuser -k "$binary" 2>/dev/null || true
        fi
    done

    log_success "Full cleanup completed!"
    log_info "=========================================="
    sleep 2
}

# Check if user has sudo access
if ! sudo -n true 2>/dev/null; then
    log_error "This script requires passwordless sudo access"
    log_error "Please run: sudo visudo and add: $USER ALL=(ALL) NOPASSWD:ALL"
    exit 1
fi

# =============================================================================
# OS DETECTION AND COMPATIBILITY
# =============================================================================

log_info "Detecting operating system..."

# Detect OS and version
if [[ ! -f /etc/os-release ]]; then
    log_error "Cannot detect OS - /etc/os-release not found"
    exit 1
fi

# shellcheck source=/dev/null
source /etc/os-release

# Check if Debian
if [[ "$ID" != "debian" ]]; then
    log_error "This script only supports Debian (detected: $ID)"
    exit 1
fi

# Detect Debian version
DEBIAN_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)
DEBIAN_CODENAME="$VERSION_CODENAME"

case "$DEBIAN_VERSION" in
    12)
        log_info "Detected: Debian 12 (Bookworm)"
        ;;
    13)
        log_info "Detected: Debian 13 (Trixie)"
        ;;
    *)
        log_warn "Unsupported Debian version: $DEBIAN_VERSION ($DEBIAN_CODENAME)"
        log_warn "This script is tested on Debian 12 (Bookworm) and 13 (Trixie)"
        log_warn "Continuing anyway, but you may encounter issues..."
        ;;
esac

log_info "Starting Observability Stack installation..."

# Display detected versions
log_info "Component versions to be installed:"
log_info "  - Prometheus: ${PROMETHEUS_VERSION}"
log_info "  - Loki: ${LOKI_VERSION}"
log_info "  - Alertmanager: ${ALERTMANAGER_VERSION}"
log_info "  - Node Exporter: ${NODE_EXPORTER_VERSION}"
log_info "  - Grafana: Latest from APT repository"

# =============================================================================
# PRE-INSTALLATION CLEANUP
# =============================================================================

# Run full cleanup BEFORE any installation to ensure idempotency
run_full_cleanup

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
    ufw \
    lsof \
    psmisc

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
stop_and_verify_service "prometheus" "/opt/observability/bin/prometheus"

sudo cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus" /opt/observability/bin/
sudo cp "prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool" /opt/observability/bin/
rm -rf "prometheus-${PROMETHEUS_VERSION}.linux-amd64"*

# Prometheus config
write_system_file "$CONFIG_DIR/prometheus/prometheus.yml" << 'EOF'
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
stop_and_verify_service "node_exporter" "/opt/observability/bin/node_exporter"

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
stop_and_verify_service "loki" "/opt/observability/bin/loki"

sudo mv loki-linux-amd64 /opt/observability/bin/loki
sudo chmod +x /opt/observability/bin/loki
rm -f loki-linux-amd64.zip

# Loki config
write_system_file "$CONFIG_DIR/loki/loki.yml" << EOF
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
stop_and_verify_service "alertmanager" "/opt/observability/bin/alertmanager"

sudo cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager" /opt/observability/bin/
rm -rf "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64"*

# Alertmanager config
write_system_file "$CONFIG_DIR/alertmanager/alertmanager.yml" << 'EOF'
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
wget -q -O - https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null
sudo apt-get update -qq
sudo apt-get install -y -qq grafana

# Configure Grafana
write_system_file /etc/grafana/provisioning/datasources/datasources.yaml << 'EOF'
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
sudo sed -i "s/;admin_password = admin/admin_password = ${GRAFANA_ADMIN_PASSWORD}/" /etc/grafana/grafana.ini

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

sudo ln -sf /etc/nginx/sites-available/observability /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

sudo nginx -t

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
# PRE-START PORT VALIDATION
# =============================================================================

log_info "Validating ports are available before starting services..."

# Critical ports that must be free
REQUIRED_PORTS=(9090 9100 3100 9093 3000)

for port in "${REQUIRED_PORTS[@]}"; do
    if lsof -ti ":$port" &>/dev/null; then
        log_warn "Port $port is still in use, attempting to free it..."
        cleanup_port_conflicts "$port"

        # Verify port is now free
        if lsof -ti ":$port" &>/dev/null; then
            log_error "Failed to free port $port. Cannot start services."
            log_error "Please manually investigate: sudo lsof -i :$port"
            exit 1
        fi
    fi
    log_info "Port $port is available"
done

log_success "All required ports are available"

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
write_system_file /root/.observability-credentials << EOF
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
