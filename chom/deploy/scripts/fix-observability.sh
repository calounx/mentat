#!/bin/bash
#
# Emergency Fix Script for Observability Stack
# Run this on the observability server to diagnose and fix issues
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "================================"
echo "  Observability Stack Diagnostics"
echo "================================"
echo ""

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
    log_error "Please run with sudo"
    exit 1
fi

CONFIG_DIR="/etc/observability"
DATA_DIR="/var/lib/observability"

# 1. Check directories exist
log_info "Checking directories..."
for dir in "$CONFIG_DIR/prometheus" "$CONFIG_DIR/loki" "$CONFIG_DIR/alertmanager" \
           "$DATA_DIR/prometheus" "$DATA_DIR/loki" "$DATA_DIR/alertmanager"; do
    if [ -d "$dir" ]; then
        echo "  ✓ $dir exists"
    else
        log_warn "$dir missing - creating..."
        mkdir -p "$dir"
        chown -R observability:observability "$dir"
    fi
done

# 2. Check config files exist
log_info "Checking config files..."

if [ ! -f "$CONFIG_DIR/prometheus/prometheus.yml" ]; then
    log_error "Prometheus config missing!"
    log_info "Creating basic prometheus.yml..."
    cat > "$CONFIG_DIR/prometheus/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - localhost:9093

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
EOF
    chown observability:observability "$CONFIG_DIR/prometheus/prometheus.yml"
    log_success "Created prometheus.yml"
else
    echo "  ✓ Prometheus config exists"
fi

if [ ! -f "$CONFIG_DIR/loki/loki.yml" ]; then
    log_error "Loki config missing!"
    log_info "Creating basic loki.yml..."
    cat > "$CONFIG_DIR/loki/loki.yml" << EOF
auth_enabled: false

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
EOF
    chown observability:observability "$CONFIG_DIR/loki/loki.yml"
    log_success "Created loki.yml"
else
    echo "  ✓ Loki config exists"
fi

if [ ! -f "$CONFIG_DIR/alertmanager/alertmanager.yml" ]; then
    log_error "Alertmanager config missing!"
    log_info "Creating basic alertmanager.yml..."
    cat > "$CONFIG_DIR/alertmanager/alertmanager.yml" << 'EOF'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'default'

receivers:
  - name: 'default'
EOF
    chown observability:observability "$CONFIG_DIR/alertmanager/alertmanager.yml"
    log_success "Created alertmanager.yml"
else
    echo "  ✓ Alertmanager config exists"
fi

# 3. Check binaries exist
log_info "Checking binaries..."
for bin in prometheus promtool node_exporter loki alertmanager; do
    if [ -f "/opt/observability/bin/$bin" ]; then
        echo "  ✓ $bin exists"
    else
        log_error "$bin binary missing!"
    fi
done

# 4. Check systemd services exist
log_info "Checking systemd services..."
for svc in prometheus node_exporter loki alertmanager grafana-server; do
    if systemctl list-unit-files | grep -q "^${svc}.service"; then
        echo "  ✓ $svc.service exists"
    else
        log_warn "$svc.service missing"
    fi
done

# 5. Check permissions
log_info "Checking permissions..."
chown -R observability:observability "$DATA_DIR"
chown -R observability:observability "$CONFIG_DIR"
chown -R observability:observability /opt/observability/bin

# 6. Try to start services
log_info "Attempting to start services..."

for svc in prometheus node_exporter loki alertmanager grafana-server; do
    log_info "Starting $svc..."
    systemctl daemon-reload
    systemctl enable $svc 2>/dev/null || true
    systemctl restart $svc 2>/dev/null || {
        log_error "$svc failed to start"
        journalctl -u $svc -n 20 --no-pager
        continue
    }

    sleep 2

    if systemctl is-active --quiet $svc; then
        log_success "$svc is running"
    else
        log_error "$svc is not running"
        echo "Last 10 log lines:"
        journalctl -u $svc -n 10 --no-pager
    fi
done

# 7. Check if ports are listening
log_info "Checking ports..."
echo ""
netstat -tlnp 2>/dev/null | grep -E ':(3000|9090|3100|9093|9100)' || log_warn "No services listening on expected ports"

echo ""
echo "================================"
echo "  Summary"
echo "================================"
echo ""

for svc in prometheus node_exporter loki alertmanager grafana-server nginx; do
    if systemctl is-active --quiet $svc; then
        log_success "$svc: RUNNING"
    else
        log_error "$svc: STOPPED"
    fi
done

echo ""
log_info "Check web access:"
echo "  Grafana:     http://$(hostname -I | awk '{print $1}'):3000"
echo "  Prometheus:  http://$(hostname -I | awk '{print $1}'):9090"
echo "  Loki:        http://$(hostname -I | awk '{print $1}'):3100"
echo ""
