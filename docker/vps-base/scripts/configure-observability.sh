#!/bin/bash
# ============================================================================
# Configure and Start Observability Stack on mentat_tst VPS
# This script assumes all binaries are already installed and just configures
# and starts the services.
# ============================================================================
set -euo pipefail

LOG_PREFIX="[CONFIGURE-OBSERVABILITY]"
STACK_PATH="/opt/observability-stack"
DEPLOY_DIR="$STACK_PATH/deploy"

echo "$LOG_PREFIX Starting observability configuration..."

# Set configuration variables
export STACK_DIR="$STACK_PATH"
export CONFIG_DIR="/etc/observability-stack"
mkdir -p "$CONFIG_DIR"
chmod 750 "$CONFIG_DIR"

# Configuration from environment or defaults
export OBSERVABILITY_IP="${HOST_IP:-10.10.100.10}"
export GRAFANA_DOMAIN=""
export USE_SSL=false
export LETSENCRYPT_EMAIL=""
export GRAFANA_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"
export METRICS_RETENTION_DAYS="${METRICS_RETENTION_DAYS:-7}"
export LOGS_RETENTION_DAYS="${LOGS_RETENTION_DAYS:-7}"
export CONFIGURE_SMTP=false
export DISABLE_IPV6="${DISABLE_IPV6:-true}"

echo "$LOG_PREFIX Configuration:"
echo "  OBSERVABILITY_IP: $OBSERVABILITY_IP"
echo "  GRAFANA_PASSWORD: $GRAFANA_PASSWORD"
echo "  METRICS_RETENTION_DAYS: $METRICS_RETENTION_DAYS"
echo "  LOGS_RETENTION_DAYS: $LOGS_RETENTION_DAYS"

# Source the library files
echo "$LOG_PREFIX Loading libraries..."
source "$DEPLOY_DIR/lib/common.sh"
source "$DEPLOY_DIR/lib/config.sh"

# ============================================================================
# Configuration Generation
# ============================================================================

echo "$LOG_PREFIX Generating configurations..."

# Generate Prometheus config
generate_prometheus_config

# Generate Loki config
generate_loki_config

# Generate Grafana config
generate_grafana_config

# Generate Alertmanager config
generate_alertmanager_config

# Generate Nginx config
generate_nginx_config

# Generate global config
generate_global_config

# ============================================================================
# Service Management
# ============================================================================

echo "$LOG_PREFIX Starting services..."

# Make sure systemd units exist (they should from previous install attempt)
systemctl daemon-reload

# List of services to enable and start
services=(
    prometheus
    loki
    tempo
    alertmanager
    grafana-server
    node_exporter
    nginx
)

for svc in "${services[@]}"; do
    echo "$LOG_PREFIX Starting $svc..."
    systemctl enable "$svc" 2>/dev/null || true
    systemctl start "$svc" 2>/dev/null || {
        echo "$LOG_PREFIX WARNING: Failed to start $svc, checking status..."
        systemctl status "$svc" --no-pager || true
        journalctl -u "$svc" --no-pager -n 10 || true
    }
done

# ============================================================================
# Verification
# ============================================================================

echo ""
echo "$LOG_PREFIX ========================================"
echo "$LOG_PREFIX Service Status"
echo "$LOG_PREFIX ========================================"

for svc in "${services[@]}"; do
    status=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
    if [[ "$status" == "active" ]]; then
        echo "$LOG_PREFIX   [OK] $svc is running"
    else
        echo "$LOG_PREFIX   [FAIL] $svc is $status"
    fi
done

echo ""
echo "$LOG_PREFIX ========================================"
echo "$LOG_PREFIX Configuration Complete!"
echo "$LOG_PREFIX ========================================"
echo "$LOG_PREFIX Services:"
echo "  - Prometheus:    http://${OBSERVABILITY_IP}:9090"
echo "  - Grafana:       http://${OBSERVABILITY_IP}:3000 (admin/${GRAFANA_PASSWORD})"
echo "  - Loki:          http://${OBSERVABILITY_IP}:3100"
echo "  - Tempo:         http://${OBSERVABILITY_IP}:3200"
echo "  - Alertmanager:  http://${OBSERVABILITY_IP}:9093"
echo "  - Node Exporter: http://${OBSERVABILITY_IP}:9100"
echo ""
