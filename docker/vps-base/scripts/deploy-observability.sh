#!/bin/bash
# ============================================================================
# Deploy Observability Stack on mentat_tst VPS
# Non-interactive wrapper that sources libraries and runs observability role
# ============================================================================
set -euo pipefail

LOG_PREFIX="[DEPLOY-OBSERVABILITY]"
STACK_PATH="/opt/observability-stack"
DEPLOY_DIR="$STACK_PATH/deploy"

echo "$LOG_PREFIX Starting observability deployment..."

# Wait for systemd to be fully ready (allow degraded since some services may fail initially)
max_wait=60
waited=0
while true; do
    status=$(systemctl is-system-running 2>/dev/null || echo "unknown")
    if [[ "$status" == "running" ]] || [[ "$status" == "degraded" ]]; then
        echo "$LOG_PREFIX Systemd is ready (status: $status)"
        break
    fi
    if [[ $waited -ge $max_wait ]]; then
        echo "$LOG_PREFIX WARNING: Systemd not fully ready after ${max_wait}s, proceeding anyway..."
        break
    fi
    echo "$LOG_PREFIX Waiting for systemd... (status: $status)"
    sleep 2
    waited=$((waited + 2))
done

# Check if deployment scripts exist
if [[ ! -d "$DEPLOY_DIR" ]]; then
    echo "$LOG_PREFIX ERROR: observability-stack not mounted at $STACK_PATH"
    exit 1
fi

# Set STACK_DIR for the deployment scripts
export STACK_DIR="$STACK_PATH"

# The observability-stack may be mounted read-only, so use a writable location for generated configs
# The original config/ has template files; generated configs go to /etc/observability-stack
export CONFIG_DIR="/etc/observability-stack"
mkdir -p "$CONFIG_DIR"
chmod 750 "$CONFIG_DIR"

echo "$LOG_PREFIX Using writable config directory: $CONFIG_DIR"

# Source the required libraries
echo "$LOG_PREFIX Loading deployment libraries..."
source "$DEPLOY_DIR/lib/common.sh"
source "$DEPLOY_DIR/lib/config.sh"

# Set non-interactive configuration variables
export OBSERVABILITY_IP="${HOST_IP:-10.10.100.10}"
export GRAFANA_DOMAIN=""
export USE_SSL=false
export LETSENCRYPT_EMAIL=""
export GRAFANA_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"
export METRICS_RETENTION_DAYS="${METRICS_RETENTION_DAYS:-7}"
export LOGS_RETENTION_DAYS="${LOGS_RETENTION_DAYS:-7}"
export CONFIGURE_SMTP=false
export DISABLE_IPV6="${DISABLE_IPV6:-true}"
export INSTALL_ALLOY="${INSTALL_ALLOY:-true}"
export ALLOY_VERSION="${ALLOY_VERSION:-1.5.1}"

# VPSManager monitored host IPs (for Prometheus file_sd targets)
export VPSMANAGER_HOST_IP="${VPSMANAGER_HOST_IP:-10.10.100.20}"
export VPSMANAGER_HOST_NAME="${VPSMANAGER_HOST_NAME:-landsraad_tst}"

# Hosting node IPs (additional monitored hosts)
export HOSTING_NODE_1_IP="${HOSTING_NODE_1_IP:-10.10.100.30}"
export HOSTING_NODE_1_NAME="${HOSTING_NODE_1_NAME:-richese_tst}"

echo "$LOG_PREFIX Configuration:"
echo "  OBSERVABILITY_IP: $OBSERVABILITY_IP"
echo "  GRAFANA_PASSWORD: $GRAFANA_PASSWORD"
echo "  METRICS_RETENTION_DAYS: $METRICS_RETENTION_DAYS"
echo "  LOGS_RETENTION_DAYS: $LOGS_RETENTION_DAYS"
echo "  DISABLE_IPV6: $DISABLE_IPV6"
echo "  INSTALL_ALLOY: $INSTALL_ALLOY"
echo "  VPSMANAGER_HOST: ${VPSMANAGER_HOST_NAME} (${VPSMANAGER_HOST_IP})"
echo "  HOSTING_NODE_1: ${HOSTING_NODE_1_NAME} (${HOSTING_NODE_1_IP})"

# Source the observability role script (this defines the functions)
echo "$LOG_PREFIX Loading observability role..."
source "$DEPLOY_DIR/roles/observability.sh"

# Run the main installation function
echo "$LOG_PREFIX Running observability stack installation..."
install_observability_stack

# Setup Prometheus file_sd targets for VPSManager monitored hosts
echo "$LOG_PREFIX Setting up Prometheus service discovery targets..."

# Function to create Prometheus target files for a host
create_host_targets() {
    local targets_dir="$1"
    local host_ip="$2"
    local host_name="$3"
    local app_name="$4"

    # Node Exporter target
    cat > "$targets_dir/${app_name}-node.yaml" << EOF
# ${app_name} Node Exporter Targets (auto-generated)
- targets:
    - "${host_ip}:9100"
  labels:
    host: "${host_name}"
    env: "test"
    role: "vps"
    app: "${app_name}"
EOF

    # Nginx Exporter target
    cat > "$targets_dir/${app_name}-nginx.yaml" << EOF
# ${app_name} Nginx Exporter Targets (auto-generated)
- targets:
    - "${host_ip}:9113"
  labels:
    host: "${host_name}"
    env: "test"
    role: "vps"
    app: "${app_name}"
EOF

    # MySQL Exporter target
    cat > "$targets_dir/${app_name}-mysql.yaml" << EOF
# ${app_name} MySQL Exporter Targets (auto-generated)
- targets:
    - "${host_ip}:9104"
  labels:
    host: "${host_name}"
    env: "test"
    role: "vps"
    app: "${app_name}"
EOF

    # PHP-FPM Exporter target
    cat > "$targets_dir/${app_name}-phpfpm.yaml" << EOF
# ${app_name} PHP-FPM Exporter Targets (auto-generated)
- targets:
    - "${host_ip}:9253"
  labels:
    host: "${host_name}"
    env: "test"
    role: "vps"
    app: "${app_name}"
EOF

    echo "$LOG_PREFIX Created target files for ${host_name} (${host_ip}) as ${app_name}"
}

setup_prometheus_targets() {
    local targets_dir="/etc/prometheus/targets"
    mkdir -p "$targets_dir"

    # Create target files for VPSManager host (primary)
    create_host_targets "$targets_dir" "$VPSMANAGER_HOST_IP" "$VPSMANAGER_HOST_NAME" "vpsmanager"

    # Create target files for hosting node 1 (richese)
    if [[ -n "$HOSTING_NODE_1_IP" ]] && [[ "$HOSTING_NODE_1_IP" != "" ]]; then
        create_host_targets "$targets_dir" "$HOSTING_NODE_1_IP" "$HOSTING_NODE_1_NAME" "hosting1"
    fi

    # Set permissions
    chown -R prometheus:prometheus "$targets_dir" 2>/dev/null || true
    chmod 644 "$targets_dir"/*.yaml 2>/dev/null || true
}
setup_prometheus_targets

# Reload Prometheus to pick up new targets
if systemctl is-active --quiet prometheus; then
    echo "$LOG_PREFIX Reloading Prometheus configuration..."
    kill -HUP $(pidof prometheus) 2>/dev/null || systemctl reload prometheus 2>/dev/null || true
fi

echo ""
echo "$LOG_PREFIX ========================================"
echo "$LOG_PREFIX Observability deployment complete!"
echo "$LOG_PREFIX ========================================"
echo "$LOG_PREFIX Services:"
echo "  - Prometheus:    http://${OBSERVABILITY_IP}:9090"
echo "  - Grafana:       http://${OBSERVABILITY_IP}:3000 (admin/${GRAFANA_PASSWORD})"
echo "  - Loki:          http://${OBSERVABILITY_IP}:3100"
echo "  - Tempo:         http://${OBSERVABILITY_IP}:3200"
echo "  - Alertmanager:  http://${OBSERVABILITY_IP}:9093"
echo "  - Node Exporter: http://${OBSERVABILITY_IP}:9100"
if [[ "${INSTALL_ALLOY:-true}" == "true" ]]; then
    echo "  - Alloy:         http://${OBSERVABILITY_IP}:12345 (telemetry collector)"
fi
echo ""
echo "$LOG_PREFIX Monitored Targets:"
echo "  - VPSManager:    ${VPSMANAGER_HOST_NAME} (${VPSMANAGER_HOST_IP})"
echo "    - node_exporter:   :9100"
echo "    - nginx_exporter:  :9113"
echo "    - mysqld_exporter: :9104"
echo "    - phpfpm_exporter: :9253"
if [[ -n "$HOSTING_NODE_1_IP" ]] && [[ "$HOSTING_NODE_1_IP" != "" ]]; then
    echo "  - Hosting Node:  ${HOSTING_NODE_1_NAME} (${HOSTING_NODE_1_IP})"
    echo "    - node_exporter:   :9100"
    echo "    - nginx_exporter:  :9113"
    echo "    - mysqld_exporter: :9104"
    echo "    - phpfpm_exporter: :9253"
fi
echo ""
